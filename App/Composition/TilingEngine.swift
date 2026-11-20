import AppKit
import ApplicationServices
import Combine
import OSLog

/// Core background actor & manager orchestrating BSP auto-tiling and layout presets (Phase 26b).
/// Pure layout calculation runs without blocking; only the final frame writes land on MainActor.
/// Off by default; instant restore of pre-tiling frames on disable; zero idle CPU while disabled.
@MainActor
final class TilingEngine: ObservableObject {
    static let shared = TilingEngine()

    /// The solid dock's frame on a screen (nil when hidden/auto-hiding); windows keep clear of it.
    var dockFrame: (NSScreen) -> CGRect? = { _ in nil }

    /// The area tiling lays windows out in: the screen's visible frame less a solid dock. The desktop
    /// window box is drawn **underneath** every window and reserves nothing (WM revamp §4), so the
    /// old 56 pt edge-rail trim is gone and this no longer depends on the strip setting. Shared with
    /// the layout-restore path, so a restored frame lands where a fresh tile would.
    func workArea(of screen: NSScreen) -> CGRect {
        DockReserve.workArea(visible: screen.visibleFrame, screen: screen.frame, dock: dockFrame(screen))
    }

    // MARK: - UserDefaults Keys
    static let enabledKey = "com.katikati.tiling.enabled"
    static let presetKey = "com.katikati.tiling.preset"
    static let innerGapKey = "com.katikati.tiling.innerGap"
    static let outerGapKey = "com.katikati.tiling.outerGap"
    static let displayPresetsKey = "com.katikati.tiling.displayPresets"
    static let mainRatioKey = "com.katikati.tiling.mainRatio"
    static let mirroredKey = "com.katikati.tiling.mirrored"
    static let floatingAppsKey = "com.katikati.tiling.floatingApps"
    static let displayLayoutsKey = "com.katikati.tiling.displayLayouts"

    // MARK: - Published State
    @Published private(set) var isEnabled: Bool = UserDefaults.standard.bool(forKey: enabledKey)
    @Published private(set) var preset: TilingLayoutPreset = {
        UserDefaults.standard.string(forKey: presetKey).flatMap(TilingLayoutPreset.init(rawValue:)) ?? .bsp
    }()
    /// Per-display overrides of `preset`, keyed by display name.
    @Published private(set) var displayPresets: [String: TilingLayoutPreset] = {
        let raw = UserDefaults.standard.dictionary(forKey: displayPresetsKey) as? [String: String] ?? [:]
        return raw.compactMapValues(TilingLayoutPreset.init(rawValue:))
    }()
    /// Per-display catalog layout (slot-capped); wins over `displayPresets`/`preset` on that display.
    @Published private(set) var displayLayouts: [String: LayoutCatalog] = {
        let raw = UserDefaults.standard.dictionary(forKey: displayLayoutsKey) as? [String: String] ?? [:]
        return raw.compactMapValues(LayoutCatalog.init(rawValue:))
    }()
    @Published private(set) var gaps: TilingGaps = {
        let inner = UserDefaults.standard.object(forKey: innerGapKey) as? CGFloat ?? 8
        let outer = UserDefaults.standard.object(forKey: outerGapKey) as? CGFloat ?? 8
        return TilingGaps(inner: inner, outer: outer)
    }()
    @Published private(set) var options: TilingLayoutOptions = {
        let d = UserDefaults.standard
        return TilingLayoutOptions(
            mainRatio: d.object(forKey: mainRatioKey) as? CGFloat ?? 0.55,
            mirrored: d.bool(forKey: mirroredKey)
        )
    }()
    @Published private(set) var policy: TilingPolicy = {
        if let raw = UserDefaults.standard.string(forKey: floatingAppsKey) {
            return TilingPolicy.parse(patterns: raw)
        }
        return TilingPolicy()
    }()

    // MARK: - Internal State
    /// In-memory pre-tiling frame snapshot: restored instantly when tiling is disabled.
    private var preTilingFrames: [CGWindowID: CGRect] = [:]
    /// Per-display tiling trees, keyed by display screen identifier.
    private var trees: [String: TilingTree] = [:]
    /// Windows manually moved/dragged by the user: released from tiling for the session.
    private var releasedWindowIDs: Set<CGWindowID> = [] {
        didSet { releasedCount = releasedWindowIDs.count }
    }
    /// Windows the user moved or resized by hand and that tiling now leaves alone (shown in Settings).
    @Published private(set) var releasedCount = 0
    /// Windows left floating because tiling them would make every tile too small.
    @Published private(set) var overflowCount = 0
    /// Latest window records, so a preset/gap/swap change can write real frames without waiting for the next snapshot.
    private var lastWindows: [WindowID: WindowRecord] = [:]
    private var lastSnapshot: DockSnapshot?
    /// Last frames set by this engine: used to distinguish engine writes from user drags.
    private var lastAppliedFrames: [CGWindowID: CGRect] = [:]
    /// Re-entrancy guard during AX writes.
    private var isApplyingLayout = false
    private var snapshotSink: AnyCancellable?
    private let log = Logger(subsystem: "com.katikati.app", category: "tiling")

    private init() {}

    // MARK: - Lifecycle

    func start<P: Publisher>(snapshotStream: P) where P.Output == DockSnapshot, P.Failure == Never {
        snapshotSink = snapshotStream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.handleSnapshot(snapshot)
            }
        if isEnabled {
            reapplyLayout()
        }
    }

    func stop() {
        snapshotSink?.cancel()
        snapshotSink = nil
    }

    // MARK: - Settings Updaters

    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)

        if on {
            releasedWindowIDs.removeAll()
            if let snap = lastSnapshot { reconcile(with: snap) } else { reapplyLayout() }
        } else {
            restorePreTilingFrames()
            trees.removeAll()
            releasedWindowIDs.removeAll()
            lastAppliedFrames.removeAll()
        }
    }

    /// Brings every hand-moved window back under tiling.
    func retileAll() {
        guard isEnabled, !releasedWindowIDs.isEmpty else { return }
        releasedWindowIDs.removeAll()
        lastAppliedFrames.removeAll()
        if let snap = lastSnapshot { reconcile(with: snap) }
    }

    func setPreset(_ newPreset: TilingLayoutPreset) {
        guard newPreset != preset else { return }
        preset = newPreset
        UserDefaults.standard.set(newPreset.rawValue, forKey: Self.presetKey)
        if isEnabled { reapplyLayout() }
    }

    func preset(for screen: NSScreen) -> TilingLayoutPreset {
        displayPresets[screenKey(for: screen)] ?? displayPresets[screen.localizedName] ?? preset
    }

    func setPreset(_ newPreset: TilingLayoutPreset, for screen: NSScreen) {
        setPreset(newPreset, forDisplay: screenKey(for: screen), legacyKey: screen.localizedName)
    }

    func setPreset(_ newPreset: TilingLayoutPreset, forDisplay name: String, legacyKey: String? = nil) {
        // Re-picking the current preset still has to clear a catalog layout sitting on top of it.
        let hadLayout = displayLayouts.removeValue(forKey: name) != nil
        let hadLegacyLayout = legacyKey.flatMap { displayLayouts.removeValue(forKey: $0) } != nil
        if let legacyKey { displayPresets.removeValue(forKey: legacyKey) }
        guard hadLayout || hadLegacyLayout || displayPresets[name] != newPreset else { return }
        displayPresets[name] = newPreset
        if hadLayout || hadLegacyLayout {
            UserDefaults.standard.set(displayLayouts.mapValues(\.rawValue), forKey: Self.displayLayoutsKey)
        }
        UserDefaults.standard.set(displayPresets.mapValues(\.rawValue), forKey: Self.displayPresetsKey)
        if isEnabled { reapplyLayout() }
    }

    func layout(for screen: NSScreen) -> LayoutCatalog? {
        displayLayouts[screenKey(for: screen)] ?? displayLayouts[screen.localizedName]
    }

    func setLayout(_ layout: LayoutCatalog?, for screen: NSScreen) {
        setLayout(layout, forDisplay: screenKey(for: screen), legacyKey: screen.localizedName)
    }

    /// Picks a catalog layout for one display and turns tiling on; `nil` goes back to the display's plain preset.
    func setLayout(_ layout: LayoutCatalog?, forDisplay name: String, legacyKey: String? = nil) {
        if let legacyKey { displayLayouts.removeValue(forKey: legacyKey) }
        displayLayouts[name] = layout
        UserDefaults.standard.set(displayLayouts.mapValues(\.rawValue), forKey: Self.displayLayoutsKey)
        if layout != nil, !isEnabled { setEnabled(true) } else if isEnabled { reapplyLayout() }
    }

    /// Drag-to-slot: turns `layout` on for `screen` and puts window `id` in slot `slot` (swapping with its occupant).
    func place(_ id: WindowID, inSlot slot: Int, layout: LayoutCatalog, on screen: NSScreen) {
        setLayout(layout, for: screen)
        let key = screenKey(for: screen)
        var tree = trees[key] ?? TilingTree()
        if !tree.contains(id) { tree.insert(id) }
        let ids = tree.allWindowIDs
        if ids.indices.contains(slot), ids[slot] != id { tree.swap(id, with: ids[slot]) }
        trees[key] = tree
        reapplyLayout()
    }

    /// Frames for one display's tree: a catalog layout caps the slots, otherwise the preset tiles everything.
    private func resolveFrames(_ tree: TilingTree, on screen: NSScreen, workArea: CGRect) -> [WindowID: CGRect] {
        if let layout = layout(for: screen) {
            return layout.frames(for: tree.allWindowIDs, workArea: workArea, gaps: gaps)
        }
        return TilingLayout.resolve(tree: tree, preset: preset(for: screen), workArea: workArea, gaps: gaps, options: options)
    }

    func setGaps(_ newGaps: TilingGaps) {
        guard newGaps != gaps else { return }
        gaps = newGaps
        UserDefaults.standard.set(Double(newGaps.inner), forKey: Self.innerGapKey)
        UserDefaults.standard.set(Double(newGaps.outer), forKey: Self.outerGapKey)
        if isEnabled { reapplyLayout() }
    }

    func setOptions(_ new: TilingLayoutOptions) {
        guard new != options else { return }
        options = new
        UserDefaults.standard.set(Double(new.mainRatio), forKey: Self.mainRatioKey)
        UserDefaults.standard.set(new.mirrored, forKey: Self.mirroredKey)
        if isEnabled { reapplyLayout() }
    }

    func adjustMainRatio(by delta: CGFloat) {
        if isEnabled,
           let screen = activeScreen(),
           layout(for: screen) == nil,
           preset(for: screen) == .bsp {
            let key = screenKey(for: screen)
            if var tree = trees[key], let focusedID = tree.focusedID, tree.adjustRatio(for: focusedID, by: delta) {
                trees[key] = tree
                reapplyLayout()
            }
            return
        }
        var new = options
        new.mainRatio = min(max(options.mainRatio + delta, TilingLayoutOptions.ratioRange.lowerBound), TilingLayoutOptions.ratioRange.upperBound)
        setOptions(new)
    }

    func setPolicy(_ newPolicy: TilingPolicy) {
        guard newPolicy != policy else { return }
        policy = newPolicy
        UserDefaults.standard.set(newPolicy.serializedPatterns, forKey: Self.floatingAppsKey)
        if isEnabled { reapplyLayout() }
    }

    /// Releases a window from auto-tiling immediately (e.g. after a manual Snap Zone placement).
    func releaseWindow(cgWindowID: CGWindowID) {
        guard isEnabled, cgWindowID != 0 else { return }
        releasedWindowIDs.insert(cgWindowID)
        lastAppliedFrames.removeValue(forKey: cgWindowID)
        for (key, var tree) in trees {
            if let recordID = tree.allWindowIDs.first(where: { lastWindows[$0]?.cgWindowID == cgWindowID || CGWindowID($0.rawValue) == cgWindowID }) {
                tree.remove(recordID)
                trees[key] = tree
            }
        }
        reapplyLayout()
    }

    // MARK: - Hotkey Actions

    func cycleLayout() {
        // Cycles the display containing the focused window (or pointer); with one display this is the global preset.
        let all = TilingLayoutPreset.allCases
        let screen = activeScreen()
        let current = screen.map(preset(for:)) ?? preset
        guard let idx = all.firstIndex(of: current) else { return }
        let next = all[(idx + 1) % all.count]
        if NSScreen.screens.count > 1, let screen { setPreset(next, for: screen) } else { setPreset(next) }
    }

    func focusNext() {
        guard isEnabled, let key = activeScreenKey(), var tree = trees[key] else { return }
        tree.focusNext()
        trees[key] = tree
        if let focusedID = tree.focusedID {
            activateWindow(focusedID)
        }
    }

    func focusPrevious() {
        guard isEnabled, let key = activeScreenKey(), var tree = trees[key] else { return }
        tree.focusPrevious()
        trees[key] = tree
        if let focusedID = tree.focusedID {
            activateWindow(focusedID)
        }
    }

    func swapNext() {
        guard isEnabled, let key = activeScreenKey(), var tree = trees[key] else { return }
        tree.swapWithNext()
        trees[key] = tree
        reapplyLayout()
    }

    func swapPrevious() {
        guard isEnabled, let key = activeScreenKey(), var tree = trees[key] else { return }
        tree.swapWithPrevious()
        trees[key] = tree
        reapplyLayout()
    }

    // MARK: - Snapshot Processing

    private func handleSnapshot(_ snapshot: DockSnapshot) {
        lastWindows = snapshot.windows
        lastSnapshot = snapshot
        guard isEnabled, !isApplyingLayout else { return }

        // Prune state for closed/disappeared windows so long sessions don't leak stale IDs.
        let liveCGIDs = Set(snapshot.windows.values.compactMap(\.cgWindowID))
        preTilingFrames = preTilingFrames.filter { liveCGIDs.contains($0.key) }
        lastAppliedFrames = lastAppliedFrames.filter { liveCGIDs.contains($0.key) }
        let prunedReleased = releasedWindowIDs.intersection(liveCGIDs)
        if prunedReleased != releasedWindowIDs {
            releasedWindowIDs = prunedReleased
        }

        // Defer hand-move detection while a mouse button is held down so siblings don't jump mid-drag.
        if NSEvent.pressedMouseButtons == 0 {
            // Detect user manual moves/resizes: if a window was placed by us but moved by user, release it.
            for (_, record) in snapshot.windows {
                guard let cg = record.cgWindowID, let currentBounds = record.bounds else { continue }
                if let lastApplied = lastAppliedFrames[cg] {
                    // A window that went native-fullscreen (or minimized) changed frame on its own; that is not a hand move.
                    guard isTileable(record, cg) else { lastAppliedFrames[cg] = nil; continue }
                    let moved = abs(currentBounds.minX - lastApplied.minX) > 10 ||
                                abs(currentBounds.minY - lastApplied.minY) > 10 ||
                                abs(currentBounds.width - lastApplied.width) > 10 ||
                                abs(currentBounds.height - lastApplied.height) > 10
                    if moved && !releasedWindowIDs.contains(cg) && !policy.alwaysTiles(bundleIdentifier: record.bundleIdentifier) {
                        releasedWindowIDs.insert(cg)
                        // Remove from trees so remaining windows retile smoothly
                        for (screenKey, var tree) in trees {
                            if tree.contains(record.id) {
                                tree.remove(record.id)
                                trees[screenKey] = tree
                            }
                        }
                    }
                }
            }
        }

        reconcile(with: snapshot)
    }

    private func reconcile(with snapshot: DockSnapshot) {
        guard isEnabled, AXIsProcessTrusted() else { return }

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let primaryMaxY = screens.first?.frame.maxY ?? 0

        // Group eligible windows by screen
        var eligibleByScreen: [String: [(WindowRecord, CGWindowID)]] = [:]
        var activeIDByScreen: [String: WindowID] = [:]

        for id in snapshot.orderedWindowIDs {
            guard let record = snapshot.windows[id],
                  record.status == .active || record.status == .inactive,
                  let cg = record.cgWindowID,
                  cg != 0,
                  !releasedWindowIDs.contains(cg),
                  !policy.shouldFloat(bundleIdentifier: record.bundleIdentifier),
                  isTileable(record, cg)
            else { continue }

            let targetScreen = resolveScreen(for: record, screens: screens, primaryMaxY: primaryMaxY)
            let key = screenKey(for: targetScreen)
            eligibleByScreen[key, default: []].append((record, cg))
            if record.status == .active {
                activeIDByScreen[key] = record.id
            }

            // Snapshot initial frame if not yet recorded
            if preTilingFrames[cg] == nil, let b = record.bounds {
                preTilingFrames[cg] = b
            }
        }

        var overflow = 0
        defer { if overflowCount != overflow { overflowCount = overflow } }

        // Reconcile tree for each screen
        for screen in screens {
            let key = screenKey(for: screen)
            let eligible = eligibleByScreen[key] ?? []
            var tree = trees[key] ?? TilingTree()

            let eligibleIDs = Set(eligible.map { $0.0.id })

            // Remove destroyed or moved windows
            for existingID in tree.allWindowIDs {
                if !eligibleIDs.contains(existingID) {
                    tree.remove(existingID)
                }
            }

            // Insert new eligible windows
            for (record, _) in eligible {
                if !tree.contains(record.id) {
                    tree.insert(record.id)
                }
            }

            // Keep tree focus synced with the active window on this screen
            if let activeID = activeIDByScreen[key], tree.contains(activeID) {
                tree.focus(activeID)
            }

            // Resolve layout geometry; if any tile would be unusably small, the newest windows stay floating.
            let workArea = workArea(of: screen)
            var targetFrames = resolveFrames(tree, on: screen, workArea: workArea)
            if let catalogLayout = layout(for: screen) {
                overflow += max(0, eligible.count - catalogLayout.slots)
            } else {
                let newcomers = eligible.map { $0.0.id }.filter { tree.contains($0) }.reversed()
                for id in newcomers where !WindowFit.allUsable(Array(targetFrames.values)) && tree.count > 1 {
                    tree.remove(id)
                    overflow += 1
                    targetFrames = resolveFrames(tree, on: screen, workArea: workArea)
                }
            }
            trees[key] = tree

            // Apply frames via AX
            applyFrames(targetFrames, records: snapshot.windows, primaryMaxY: primaryMaxY, area: workArea)
        }
    }

    private func reapplyLayout() {
        guard isEnabled else { return }
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let primaryMaxY = screens.first?.frame.maxY ?? 0

        for screen in screens {
            let key = screenKey(for: screen)
            guard let tree = trees[key], !tree.isEmpty else { continue }
            let workArea = workArea(of: screen)
            let targetFrames = resolveFrames(tree, on: screen, workArea: workArea)

            applyFrames(targetFrames, records: lastWindows, primaryMaxY: primaryMaxY, area: workArea)
        }
    }

    // MARK: - AX Frame Writing

    private func applyFrames(
        _ targetFrames: [WindowID: CGRect],
        records: [WindowID: WindowRecord],
        primaryMaxY: CGFloat,
        area: CGRect
    ) {
        guard !targetFrames.isEmpty else { return }
        isApplyingLayout = true
        defer { isApplyingLayout = false }

        for (winID, cocoaFrame) in targetFrames {
            guard let record = records[winID], let cg = record.cgWindowID ?? CGWindowID(winID.rawValue) else { continue }

            let quartz = CGRect(origin: SnapPosition.accessibilityOrigin(of: cocoaFrame, primaryMaxY: primaryMaxY), size: cocoaFrame.size)

            // Skip AX IPC when the window is already at the target frame within 2pt tolerance.
            if let currentBounds = record.bounds, WindowFit.isNearlyEqual(currentBounds, quartz, tolerance: 2) {
                lastAppliedFrames[cg] = currentBounds
                continue
            }

            guard let element = AXElementCache.shared.element(pid: record.pid, cgWindowID: cg) ?? axElement(for: record.pid, cgWindowID: cg) else { continue }

            let quartzArea = CGRect(origin: SnapPosition.accessibilityOrigin(of: area, primaryMaxY: primaryMaxY), size: area.size)

            // Snapshot bounds are Quartz (top-left); store what the app really took (it may clamp to a minimum size)
            // in the same space or the window reads as hand-moved.
            lastAppliedFrames[cg] = WindowSnapService.place(element, quartzFrame: quartz, within: quartzArea) ?? quartz
        }
    }

    private func restorePreTilingFrames() {
        guard AXIsProcessTrusted() else { return }
        let screens = NSScreen.screens
        let primaryMaxY = screens.first?.frame.maxY ?? 0

        isApplyingLayout = true
        defer { isApplyingLayout = false }

        for (cg, originalQuartz) in preTilingFrames {
            var point = originalQuartz.origin
            var size = originalQuartz.size
            guard let pointVal = AXValueCreate(.cgPoint, &point),
                  let sizeVal = AXValueCreate(.cgSize, &size) else { continue }

            // Find matching element
            for running in NSWorkspace.shared.runningApplications {
                if let el = AXElementCache.shared.element(pid: running.processIdentifier, cgWindowID: cg) {
                    AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, sizeVal)
                    AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, pointVal)
                    AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, sizeVal)
                    break
                }
            }
        }
        preTilingFrames.removeAll()
    }

    // MARK: - Helpers

    private func isTileable(_ record: WindowRecord, _ cg: CGWindowID) -> Bool {
        guard let element = AXElementCache.shared.element(pid: record.pid, cgWindowID: cg) ?? axElement(for: record.pid, cgWindowID: cg) else { return true }
        guard WindowSnapService.isTileable(element) else { return false }
        // A window the user tiled with macOS's own tiling (flush half/quarter we did not place) is left alone.
        if lastAppliedFrames[cg] == nil, let b = record.bounds, let primary = NSScreen.screens.first?.frame,
           let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: b.midX, y: primary.maxY - b.midY)) }) {
            let v = screen.visibleFrame
            let q = CGRect(origin: SnapPosition.accessibilityOrigin(of: v, primaryMaxY: primary.maxY), size: v.size)
            if WindowFit.isNativeTile(b, in: q) { return false }
        }
        return true
    }

    func screenKey(for screen: NSScreen) -> String {
        DisplayIdentity.uuidString(for: screen) ?? screen.localizedName
    }

    private func resolveScreen(for record: WindowRecord, screens: [NSScreen], primaryMaxY: CGFloat) -> NSScreen {
        if let pinned = policy.pinnedDisplay(bundleIdentifier: record.bundleIdentifier),
           let match = screens.first(where: { $0.localizedName == pinned || screenKey(for: $0) == pinned }) {
            return match
        }
        if let uuid = record.displayUUID,
           let match = screens.first(where: { DisplayIdentity.uuidString(for: $0) == uuid }) {
            return match
        }
        if let b = record.bounds {
            let cocoaCenter = WindowFit.cocoaCenter(ofQuartzFrame: b, primaryMaxY: primaryMaxY)
            if let match = screens.first(where: { $0.frame.contains(cocoaCenter) }) {
                return match
            }
        }
        return screens[0]
    }

    private func activeScreen() -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let primaryMaxY = screens.first?.frame.maxY ?? 0
        if let activeRecord = lastSnapshot?.windows.values.first(where: { $0.status == .active }) {
            return resolveScreen(for: activeRecord, screens: screens, primaryMaxY: primaryMaxY)
        }
        let mouse = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? screens.first
    }

    private func activeScreenKey() -> String? {
        activeScreen().map(screenKey(for:))
    }

    private func axElement(for pid: pid_t, cgWindowID: CGWindowID) -> AXUIElement? {
        guard pid > 0 else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let list = windowsRef as? [AXUIElement] else { return nil }
        return list.first { AXWindowReader.cgWindowID(for: $0) == cgWindowID }
    }

    private func activateWindow(_ winID: WindowID) {
        // Bring window to focus
        guard let cg = CGWindowID(winID.rawValue) else { return }
        for app in NSWorkspace.shared.runningApplications {
            if let el = AXElementCache.shared.element(pid: app.processIdentifier, cgWindowID: cg) {
                AXUIElementSetAttributeValue(el, kAXMainAttribute as CFString, kCFBooleanTrue)
                app.activate(options: .activateIgnoringOtherApps)
                break
            }
        }
    }
}
