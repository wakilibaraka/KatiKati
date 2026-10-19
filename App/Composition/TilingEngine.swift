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

    private func workArea(of screen: NSScreen) -> CGRect {
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

    func preset(for screen: NSScreen) -> TilingLayoutPreset { displayPresets[screen.localizedName] ?? preset }

    func setPreset(_ newPreset: TilingLayoutPreset, forDisplay name: String) {
        guard displayPresets[name] != newPreset else { return }
        displayPresets[name] = newPreset
        UserDefaults.standard.set(displayPresets.mapValues(\.rawValue), forKey: Self.displayPresetsKey)
        if isEnabled { reapplyLayout() }
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

    // MARK: - Hotkey Actions

    func cycleLayout() {
        // Cycles the display under the pointer's key window; with one display this is the global preset.
        let all = TilingLayoutPreset.allCases
        let screen = NSScreen.main ?? NSScreen.screens.first
        let current = screen.map(preset(for:)) ?? preset
        guard let idx = all.firstIndex(of: current) else { return }
        let next = all[(idx + 1) % all.count]
        if NSScreen.screens.count > 1, let screen { setPreset(next, forDisplay: screen.localizedName) } else { setPreset(next) }
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

        reconcile(with: snapshot)
    }

    private func reconcile(with snapshot: DockSnapshot) {
        guard isEnabled, AXIsProcessTrusted() else { return }

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let primaryMaxY = screens.first?.frame.maxY ?? 0

        // Group eligible windows by screen
        var eligibleByScreen: [String: [(WindowRecord, CGWindowID)]] = [:]

        for id in snapshot.orderedWindowIDs {
            guard let record = snapshot.windows[id],
                  record.status == .active || record.status == .inactive,
                  let cg = record.cgWindowID,
                  cg != 0,
                  !releasedWindowIDs.contains(cg),
                  !policy.shouldFloat(bundleIdentifier: record.bundleIdentifier),
                  isTileable(record, cg)
            else { continue }

            // Determine which screen contains this window's center
            let winCenter: CGPoint = {
                if let b = record.bounds {
                    return CGPoint(x: b.midX, y: b.midY)
                }
                return CGPoint(x: screens[0].frame.midX, y: screens[0].frame.midY)
            }()

            let pinned = policy.pinnedDisplay(bundleIdentifier: record.bundleIdentifier)
            let targetScreen = screens.first { $0.localizedName == pinned }
                ?? screens.first { $0.frame.contains(winCenter) } ?? screens[0]
            let screenKey = targetScreen.localizedName + "-\(targetScreen.frame.origin)"
            eligibleByScreen[screenKey, default: []].append((record, cg))

            // Snapshot initial frame if not yet recorded
            if preTilingFrames[cg] == nil, let b = record.bounds {
                preTilingFrames[cg] = b
            }
        }

        var overflow = 0
        defer { if overflowCount != overflow { overflowCount = overflow } }

        // Reconcile tree for each screen
        for screen in screens {
            let screenKey = screen.localizedName + "-\(screen.frame.origin)"
            let eligible = eligibleByScreen[screenKey] ?? []
            var tree = trees[screenKey] ?? TilingTree()

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

            // Resolve layout geometry; if any tile would be unusably small, the newest windows stay floating.
            let workArea = workArea(of: screen)
            var targetFrames = TilingLayout.resolve(tree: tree, preset: preset(for: screen), workArea: workArea, gaps: gaps, options: options)
            let newcomers = eligible.map { $0.0.id }.filter { tree.contains($0) }.reversed()
            for id in newcomers where !WindowFit.allUsable(Array(targetFrames.values)) && tree.count > 1 {
                tree.remove(id)
                overflow += 1
                targetFrames = TilingLayout.resolve(tree: tree, preset: preset(for: screen), workArea: workArea, gaps: gaps, options: options)
            }
            trees[screenKey] = tree

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
            let screenKey = screen.localizedName + "-\(screen.frame.origin)"
            guard let tree = trees[screenKey], !tree.isEmpty else { continue }
            let workArea = workArea(of: screen)
            let targetFrames = TilingLayout.resolve(tree: tree, preset: preset(for: screen), workArea: workArea, gaps: gaps, options: options)

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
            guard let element = AXElementCache.shared.element(pid: record.pid, cgWindowID: cg) ?? axElement(for: record.pid, cgWindowID: cg) else { continue }

            let quartz = CGRect(origin: SnapPosition.accessibilityOrigin(of: cocoaFrame, primaryMaxY: primaryMaxY), size: cocoaFrame.size)
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

        for (cg, originalCocoa) in preTilingFrames {
            var point = SnapPosition.accessibilityOrigin(of: originalCocoa, primaryMaxY: primaryMaxY)
            var size = originalCocoa.size
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

    private func activeScreenKey() -> String? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        return screen.localizedName + "-\(screen.frame.origin)"
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
