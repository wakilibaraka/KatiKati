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

    // MARK: - Ribbon State

    static let stripWidthKey = "com.katikati.tiling.stripWidth"

    /// Width new ribbon columns are born with; cycling a column updates it too.
    @Published private(set) var stripWidth: ColumnWidthPreset = {
        UserDefaults.standard.string(forKey: stripWidthKey).flatMap(ColumnWidthPreset.init(rawValue:)) ?? .half
    }()
    /// One strip per display, keyed like the trees; seeded from the tree and written back each pass.
    private var strips: [String: ScrollingStripState] = [:]
    /// Scroll offset per display, so the camera does not jitter between passes.
    private var stripOffsets: [String: CGFloat] = [:]
    /// What we last asked each window to be. A parked window is granted less than it asks for, so
    /// comparing against the granted frame alone would re-fire AX on every snapshot (RT-4).
    private var lastRequestedFrames: [CGWindowID: CGRect] = [:]
    /// Watches the frontmost window so a parked column is revealed on activation, a click or
    /// ⌘-Tab. The snapshot stream does not publish on every focus change, NSWorkspace's activation
    /// notification does not reach this agent app, and its `frontmostApplication` goes stale here,
    /// so the WindowServer's front-to-back window list is the source: one read per 500 ms while the
    /// ribbon is on, and nothing at all otherwise.
    private var focusTimer: DispatchSourceTimer?
    private var lastFocusedCG: CGWindowID?

    /// True when the active display list is the strip; used where a preset-dependent rule applies
    /// to the whole engine (hand-move adoption, restore on quit).
    private var isRibbonActive: Bool {
        preset == .ribbon || displayPresets.values.contains(.ribbon)
    }

    #if DEBUG
    /// Live-check trace (`KATIKATI_RIBBON_DEBUG=1`): who the engine thinks is focused, where the
    /// strip put the camera, and which columns it parked. Debug builds only; no idle work otherwise.
    private func ribbonDebug(_ line: @autoclosure () -> String) {
        guard ProcessInfo.processInfo.environment["KATIKATI_RIBBON_DEBUG"] != nil else { return }
        let url = URL(fileURLWithPath: "/tmp/ribbon-debug.log")
        let data = Data(((line()) + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
    #endif

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
            startFocusObservation()
            reapplyLayout()
        }
    }

    func stop() {
        snapshotSink?.cancel()
        snapshotSink = nil
        focusTimer?.cancel()
        focusTimer = nil
        lastFocusedCG = nil
    }

    private func startFocusObservation() {
        guard focusTimer == nil else { return }
        #if DEBUG
        ribbonDebug("focus-watch start")
        #endif
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            self?.pollFrontmostWindow()
        }
        timer.resume()
        focusTimer = timer
        pollFrontmostWindow()
    }

    /// Reads who the user is actually looking at. The engine's own frames are not trusted: a parked
    /// window's granted frame is off-screen and says nothing about focus. `NSWorkspace`'s frontmost
    /// app is stale for this agent app, so the WindowServer's front-to-back list is the source: the
    /// first layer-0 window the strip manages is the one the user just activated, clicked or
    /// ⌘-Tabbed to.
    private func pollFrontmostWindow() {
        guard isEnabled, isRibbonActive, let snapshot = lastSnapshot else { return }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return }
        let ownPID = ProcessInfo.processInfo.processIdentifier

        var picked: (CGWindowID, WindowRecord)?
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) != ownPID,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  ((info[kCGWindowBounds as String] as? [String: Any])?["Width"] as? CGFloat ?? 0) > 40,
                  let number = info[kCGWindowNumber as String] as? CGWindowID, number != 0
            else { continue }
            if let record = snapshot.windows.values.first(where: { $0.cgWindowID == number }) {
                picked = (number, record)
                break
            }
        }

        guard let (number, record) = picked, number != lastFocusedCG else { return }
        grantFocus(to: record, cg: number)
    }

    /// Makes `record` the strip's focus and re-lays the strip, so `StripCamera` reveals its column.
    private func grantFocus(to record: WindowRecord, cg: CGWindowID) {
        let screens = NSScreen.screens
        guard let screen = screens.first(where: {
            resolveScreen(for: record, screens: screens, primaryMaxY: screens[0].frame.maxY) === $0
        }) ?? screens.first else { return }
        let key = screenKey(for: screen)
        guard var tree = trees[key], tree.contains(record.id) else { return }
        lastFocusedCG = cg
        guard strips[key]?.focusedID != record.id else { return }
        tree.focus(record.id)
        trees[key] = tree
        if var state = strips[key] {
            state.focus(record.id)
            strips[key] = state
        }
        #if DEBUG
        ribbonDebug("focus cg=\(cg) id=\(record.id.rawValue) key=\(key)")
        #endif
        reapplyLayout()
    }

    // MARK: - Settings Updaters

    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)

        if on {
            releasedWindowIDs.removeAll()
            startFocusObservation()
            if let snap = lastSnapshot { reconcile(with: snap) } else { reapplyLayout() }
        } else {
            restorePreTilingFrames()
            trees.removeAll()
            strips.removeAll()
            stripOffsets.removeAll()
            releasedWindowIDs.removeAll()
            lastAppliedFrames.removeAll()
            lastRequestedFrames.removeAll()
        }
    }

    /// Ribbon-only: put windows back where the strip found them when the app quits. Every other
    /// preset keeps the existing behaviour (restore only when tiling is switched off).
    func restoreOnQuitIfNeeded() {
        guard isEnabled, preset == .ribbon || displayPresets.values.contains(.ribbon) else { return }
        restorePreTilingFrames()
    }

    /// Applies one of the ribbon's eight pictures. Chain turns the strip on; the others pick the
    /// catalog picture that draws that shape.
    func applyQuickLayout(_ picture: RibbonQuickLayout) {
        guard let screen = activeScreen() ?? NSScreen.screens.first else { return }
        if let catalog = picture.catalog {
            setLayout(catalog, for: screen)
        } else {
            setPreset(.ribbon, for: screen)
        }
        if !isEnabled { setEnabled(true) }
    }

    /// Runs `body` on the active display's strip, seeding it from the tree when the strip is new.
    private func mutateStrip(_ body: (inout ScrollingStripState) -> Void) {
        guard isEnabled, let key = activeScreenKey() else { return }
        var state = strips[key]
            ?? ScrollingStripState(windowIDs: trees[key]?.allWindowIDs ?? [], width: stripWidth)
        body(&state)
        strips[key] = state
        reapplyLayout()
    }

    func cycleStripWidth() {
        mutateStrip { $0.cycleWidth() }
        if let width = strips[activeScreenKey() ?? ""]?.width { stripWidth = width }
        UserDefaults.standard.set(stripWidth.rawValue, forKey: Self.stripWidthKey)
    }

    /// The width the strip gives its focused column; falls back to the width new columns start at.
    /// The Settings picker binds to this, and ⌃⌥⇧R cycles the same value.
    var focusedColumnWidth: ColumnWidthPreset {
        guard let key = activeScreenKey(), let column = strips[key]?.focusedColumn else { return stripWidth }
        return column.width
    }

    /// Settings › Tiling row: set the focused column's width, and remember it as the width new
    /// columns are born with — the same two effects cycling with ⌃⌥⇧R has.
    func setStripColumnWidth(_ width: ColumnWidthPreset) {
        stripWidth = width
        UserDefaults.standard.set(width.rawValue, forKey: Self.stripWidthKey)
        mutateStrip { $0.setWidth(width) }
    }

    /// Focus a neighbouring column of the active display's strip, and bring its window forward.
    func focusStripColumn(_ offset: Int) {
        guard isEnabled, let key = activeScreenKey() else { return }
        var state = strips[key]
            ?? ScrollingStripState(windowIDs: trees[key]?.allWindowIDs ?? [], width: stripWidth)
        state.focusColumn(offset)
        strips[key] = state
        if let id = state.focusedID, var tree = trees[key] {
            tree.focus(id)
            trees[key] = tree
            activateWindow(id)
        }
        reapplyLayout()
    }

    func moveStripColumn(_ offset: Int) { mutateStrip { $0.swapFocused(offset) } }

    func stackStripLeft() { mutateStrip { $0.stackLeft() } }

    func toggleStripTabs() { mutateStrip { $0.toggleTabs() } }

    func focusStripTab(_ offset: Int) { mutateStrip { $0.focusTab(offset) } }

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
        lastRequestedFrames = lastRequestedFrames.filter { liveCGIDs.contains($0.key) }
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
                    if moved && !releasedWindowIDs.contains(cg) && !policy.alwaysTiles(bundleIdentifier: record.bundleIdentifier) && isRibbonActive {
                        // In the ribbon a hand-move is an adoption, not a release: the strip keeps the
                        // window and focuses it, so a drag out of a parked column ends with that
                        // column revealed instead of the window falling out of tiling.
                        for (screenKey, var tree) in trees where tree.contains(record.id) {
                            tree.focus(record.id)
                            trees[screenKey] = tree
                        }
                    } else if moved && !releasedWindowIDs.contains(cg) && !policy.alwaysTiles(bundleIdentifier: record.bundleIdentifier) {
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

            // Snapshot the frame tiling is about to displace. The live AX frame wins over the
            // snapshot's: a parked window's record can still carry the column frame from before the
            // user (or a restore) moved it, and capturing that leaves the restore with nothing to
            // put back, so the window stays in its column when tiling is switched off or the app
            // quits. A record the tracker has not sampled at all also lands here.
            if preTilingFrames[cg] == nil {
                let frame = axElement(for: record.pid, cgWindowID: cg).flatMap(WindowSnapService.frame(of:))
                    ?? record.bounds
                if let frame { preTilingFrames[cg] = frame }
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
            var targetFrames: [WindowID: CGRect]
            var parked: [WindowID: StripParking.Side] = [:]
            if let catalogLayout = layout(for: screen) {
                targetFrames = resolveFrames(tree, on: screen, workArea: workArea)
                overflow += max(0, eligible.count - catalogLayout.slots)
            } else if preset(for: screen) == .ribbon {
                // A strip never shrinks a column to fit — it scrolls — so the usable-size guard is
                // deliberately skipped here, otherwise a ¼ column would evict its own windows.
                let ribbon = ribbonFrames(tree, on: screen, workArea: workArea, activeID: activeIDByScreen[key])
                targetFrames = ribbon.frames
                parked = ribbon.parked
            } else {
                targetFrames = resolveFrames(tree, on: screen, workArea: workArea)
                let newcomers = eligible.map { $0.0.id }.filter { tree.contains($0) }.reversed()
                for id in newcomers where !WindowFit.allUsable(Array(targetFrames.values)) && tree.count > 1 {
                    tree.remove(id)
                    overflow += 1
                    targetFrames = resolveFrames(tree, on: screen, workArea: workArea)
                }
            }
            trees[key] = tree

            // Apply frames via AX
            applyFrames(targetFrames, records: snapshot.windows, primaryMaxY: primaryMaxY, area: workArea, parked: parked)
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
            // A focus grant must lay out the strip, not the catalogue: resolving the plain tree here
            // would write column frames the strip never asked for and leave the revealed window off
            // screen while the camera had already scrolled to its column.
            if preset(for: screen) == .ribbon {
                let ribbon = ribbonFrames(tree, on: screen, workArea: workArea, activeID: nil)
                applyFrames(ribbon.frames, records: lastWindows, primaryMaxY: primaryMaxY, area: workArea, parked: ribbon.parked)
                continue
            }
            let targetFrames = resolveFrames(tree, on: screen, workArea: workArea)

            applyFrames(targetFrames, records: lastWindows, primaryMaxY: primaryMaxY, area: workArea)
        }
    }

    /// The active display's strip, synced with its tree and resolved with the camera. Columns that
    /// fall outside the viewport are parked at the edge macOS will accept.
    private func ribbonFrames(
        _ tree: TilingTree,
        on screen: NSScreen,
        workArea: CGRect,
        activeID: WindowID?
    ) -> (frames: [WindowID: CGRect], parked: [WindowID: StripParking.Side]) {
        let key = screenKey(for: screen)
        var state = strips[key] ?? ScrollingStripState(windowIDs: tree.allWindowIDs, width: stripWidth)
        state.sync(with: tree.allWindowIDs)
        // The frontmost window wins, not the tree's last salt: a click, a ⌘-Tab, or activating the
        // app must bring a parked column on screen even when the tree never saw that window become
        // active. The tree focus is only the fallback.
        if let focused = activeID ?? tree.focusedID { state.focus(focused) }
        strips[key] = state

        let content = CGRect(
            x: workArea.minX + gaps.outer,
            y: workArea.minY + gaps.outer,
            width: max(0, workArea.width - 2 * gaps.outer),
            height: max(0, workArea.height - 2 * gaps.outer)
        )
        let laid = TilingLayout.resolveRibbon(
            state: state, in: content, gap: gaps.inner, camera: stripOffsets[key] ?? 0
        )
        stripOffsets[key] = laid.camera
        #if DEBUG
        ribbonDebug("ribbon screen=\(key) tree=\(tree.focusedID?.rawValue ?? "-") active=\(activeID?.rawValue ?? "-") strip=\(state.focusedIndex) camera=\(laid.camera) content=\(laid.contentWidth) parked=\(laid.parked.map { "\($0.key.rawValue):\($0.value)" }.sorted().joined(separator: ","))")
        #endif

        let screens = NSScreen.screens
        let neighbourLeft = screens.contains { other in
            other !== screen && abs(other.frame.maxX - screen.frame.minX) < 1
        }
        let neighbourRight = screens.contains { other in
            other !== screen && abs(other.frame.minX - screen.frame.maxX) < 1
        }

        var frames = laid.frames
        var parked: [WindowID: StripParking.Side] = [:]
        for (id, edge) in laid.parked {
            let neighbour = edge == .left ? neighbourLeft : neighbourRight
            let side = StripParking.side(forEdge: edge, neighbourOnEdge: neighbour)
            frames[id] = StripParking.parked(frames[id] ?? content, in: workArea, side: side)
            parked[id] = side
        }
        return (frames, parked)
    }

    // MARK: - AX Frame Writing

    private func applyFrames(
        _ targetFrames: [WindowID: CGRect],
        records: [WindowID: WindowRecord],
        primaryMaxY: CGFloat,
        area: CGRect,
        parked: [WindowID: StripParking.Side] = [:]
    ) {
        guard !targetFrames.isEmpty else { return }
        // Never move windows while a button is held: a drag must not be fought frame by frame. The
        // next snapshot after the drag applies the column the window now belongs to.
        guard NSEvent.pressedMouseButtons == 0 else { return }
        isApplyingLayout = true
        defer { isApplyingLayout = false }

        for (winID, cocoaFrame) in targetFrames {
            guard let record = records[winID], let cg = record.cgWindowID ?? CGWindowID(winID.rawValue) else { continue }

            let quartz = CGRect(origin: SnapPosition.accessibilityOrigin(of: cocoaFrame, primaryMaxY: primaryMaxY), size: cocoaFrame.size)

            // Skip AX IPC when the window is already where we asked (a parked window is granted
            // less than it asked for, so the granted frame alone would never match). The repeat
            // check has to compare this request with the last one, not with where the window sits:
            // a revealed column asks for a new frame while the window is still in its park band.
            if let currentBounds = record.bounds {
                if WindowFit.isNearlyEqual(currentBounds, quartz, tolerance: 2) {
                    lastAppliedFrames[cg] = currentBounds
                    continue
                }
                // A parked column is granted less than it asked for (the OS clamps it into the edge),
                // so an identical repeat request can be trusted. An on-screen column has to actually
                // be there before the write is skipped — otherwise a reveal that was parked earlier
                // is never re-asked and the window stays off screen.
                if parked[winID] != nil,
                   lastRequestedFrames[cg].map({ WindowFit.isNearlyEqual($0, quartz, tolerance: 2) }) == true {
                    continue
                }
            }

            guard let element = AXElementCache.shared.element(pid: record.pid, cgWindowID: cg) ?? axElement(for: record.pid, cgWindowID: cg) else { continue }

            let quartzArea = CGRect(origin: SnapPosition.accessibilityOrigin(of: area, primaryMaxY: primaryMaxY), size: area.size)

            // Snapshot bounds are Quartz (top-left); store what the app really took (it may clamp to a minimum size)
            // in the same space or the window reads as hand-moved. Parked windows are written without
            // the work-area clamp, or the clamp would pull them straight back on screen.
            lastRequestedFrames[cg] = quartz
            lastAppliedFrames[cg] = WindowSnapService.place(
                element, quartzFrame: quartz, within: parked[winID] == nil ? quartzArea : nil
            ) ?? quartz
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
