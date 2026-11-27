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

    /// True when any display draws the strip; used where a preset-dependent rule applies to the
    /// whole engine (hand-move adoption, restore on quit). Reads `drawsStrip`, not the preset alone,
    /// so a display holding a catalog layout on top of `.ribbon` is not treated as the strip.
    private var isRibbonActive: Bool {
        NSScreen.screens.contains { drawsStrip(on: $0) }
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
    /// Internal so the workspace parking path can seed it from a recovery frame: a window that was
    /// already parked when tiling first saw it must not remember the park position as its own.
    var preTilingFrames: [CGWindowID: CGRect] = [:]
    /// Per-display tiling trees, keyed by display screen identifier.
    var trees: [String: TilingTree] = [:]
    /// Windows manually moved/dragged by the user: released from tiling for the session.
    private var releasedWindowIDs: Set<CGWindowID> = [] {
        didSet { releasedCount = releasedWindowIDs.count }
    }
    /// Windows the user moved or resized by hand and that tiling now leaves alone (shown in Settings).
    @Published private(set) var releasedCount = 0
    /// Windows left floating because tiling them would make every tile too small.
    @Published private(set) var overflowCount = 0
    /// Latest window records, so a preset/gap/swap change can write real frames without waiting for the next snapshot.
    var lastWindows: [WindowID: WindowRecord] = [:]
    var lastSnapshot: DockSnapshot?
    /// Last frames set by this engine: used to distinguish engine writes from user drags.
    var lastAppliedFrames: [CGWindowID: CGRect] = [:]
    /// When each window was last moved by this engine. A snapshot that lands while a window is still
    /// travelling to the frame we wrote reads as a hand-move and releases it from tiling, which is how a
    /// workspace switch used to drop a window out of the layout (found live 2026-11-27). The hand-move
    /// detector ignores our own writes for `handMoveSettle` seconds.
    var lastAppliedAt: [CGWindowID: TimeInterval] = [:]
    private static let handMoveSettle: TimeInterval = 0.6
    /// Re-entrancy guard during AX writes.
    private var isApplyingLayout = false
    private var snapshotSink: AnyCancellable?
    let log = Logger(subsystem: "com.katikati.app", category: "tiling")

    private init() {}

    // MARK: - Lifecycle

    func start<P: Publisher>(snapshotStream: P) where P.Output == DockSnapshot, P.Failure == Never {
        snapshotSink = snapshotStream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.handleSnapshot(snapshot)
            }
        // W-10: the control socket exists only while the app runs with workspaces switched on.
        if workspacesEnabled { WorkspaceControlServer.shared.start() }
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
        #if DEBUG
        if debugPauseFocusPoll { return }
        #endif
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
            // Parked workspace windows have to come back before the tiling frames are restored, or
            // they stay off screen with nothing left to reveal them.
            revealAllParkedWorkspaces()
            restorePreTilingFrames()
            workspaceTrees.removeAll()
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
        // Workspaces own their own restoration order: every parked window first, then (for the
        // ribbon) the strip's pre-tiling frames.
        if workspacesEnabled { revealAllParkedWorkspaces() }
        guard isEnabled, isRibbonActive else { return }
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

    /// True when the display under `point` draws the strip *and* the window under the pointer is one
    /// the strip manages. The ⌥-scroll gesture acts only there: over a floating window, a full-screen
    /// app or one of our own panels the event belongs to whatever the pointer is on.
    func ribbonCoversPointer(at point: NSPoint) -> Bool {
        guard isEnabled else { return false }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return false }
        guard drawsStrip(on: screen) else { return false }
        guard let cgID = Self.frontmostWindowID(at: point) else { return false }
        let key = screenKey(for: screen)
        return trees[key]?.allWindowIDs.contains(WindowID(rawValue: "cgw-\(cgID)")) ?? false
    }

    /// The layer-0 window under a Cocoa point, in the WindowServer's front-to-back order. The strip's
    /// own frames are not used on purpose: a floating window drawn over a column still owns the event.
    /// (Quartz bounds are top-left from the main display; this converts a Cocoa point for the same
    /// single-display geometry the strip itself works in.)
    static func frontmostWindowID(at point: NSPoint) -> CGWindowID? {
        guard let main = NSScreen.screens.first else { return nil }
        let cgPoint = CGPoint(x: point.x, y: main.frame.height - point.y)
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.contains(cgPoint),
                  let number = info[kCGWindowNumber as String] as? Int else { continue }
            return CGWindowID(number)
        }
        return nil
    }

    #if DEBUG
    /// Live-check only: the active display's focused column, camera and column count.
    var debugStripState: (column: Int, camera: CGFloat, columns: Int) {
        guard let key = activeScreenKey(), let strip = strips[key] else { return (0, 0, 0) }
        return (strip.focusedIndex, stripOffsets[key] ?? 0, strip.columns.count)
    }

    /// Live-check only: whether a WindowServer window belongs to the active display's strip.
    func debugIsManaged(_ id: CGWindowID?) -> Bool {
        guard let id, let key = activeScreenKey() else { return false }
        return trees[key]?.allWindowIDs.contains(WindowID(rawValue: "cgw-\(id)")) ?? false
    }

    /// Live-check only: the focus poll would fight a scripted sequence, so it can be paused.
    var debugPauseFocusPoll = false

    /// Live-check only: every input to the ⌥-scroll gate for a point, for the check's log.
    func debugGate(at point: NSPoint) -> (managed: Bool, cg: String, preset: String) {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) })
        let cg = Self.frontmostWindowID(at: point)
        return (debugIsManaged(cg), cg.map(String.init) ?? "nil", screen.map { preset(for: $0).rawValue } ?? "-")
    }
    #endif

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

    /// True when this display is drawn as the scrolling strip. A catalog layout wins over the
    /// preset, so a display can hold both (⌘⌃1 Chain, then ⌘⌃2 Halves) and must not take the strip
    /// branch then. `reconcile` already reads it this way; every other caller has to agree, or one
    /// display alternates between column frames and catalog frames on alternate passes.
    func drawsStrip(on screen: NSScreen) -> Bool {
        layout(for: screen) == nil && preset(for: screen) == .ribbon
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

    /// Releases the currently focused window from auto-tiling (frontmost AX window first,
    /// falling back to the active screen tree's focused window).
    func releaseFocusedWindow() {
        guard isEnabled else { return }
        if let cgID = WindowSnapService.frontmostWindowCGID(), cgID != 0 {
            releaseWindow(cgWindowID: cgID)
            return
        }
        if let key = activeScreenKey(),
           let focusedID = trees[key]?.focusedID,
           let cgID = lastWindows[focusedID]?.cgWindowID, cgID != 0 {
            releaseWindow(cgWindowID: cgID)
        }
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
        lastAppliedAt = lastAppliedAt.filter { liveCGIDs.contains($0.key) }
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
                    // Still travelling to a frame we just asked for: not the user's hand.
                    if let appliedAt = lastAppliedAt[cg],
                       ProcessInfo.processInfo.systemUptime - appliedAt < Self.handMoveSettle {
                        continue
                    }
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

        // Workspaces assign and park first, so the tiling pass below only ever sees one workspace's
        // windows per display (W-4a).
        if workspacesEnabled {
            reconcileWorkspaceOwnership(with: snapshot, screens: screens, primaryMaxY: primaryMaxY)
        }
        if !didRecoverParkedWorkspaces {
            didRecoverParkedWorkspaces = true
            recoverParkedWorkspacesOnStart()
        }

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
            // Workspaces narrow this pass to the active workspace's windows; everything else is
            // parked by `reconcileWorkspaceOwnership` before the pass runs.
            guard workspaceAllowsTiling(record, on: key) else { continue }
            eligibleByScreen[key, default: []].append((record, cg))
            if record.status == .active {
                activeIDByScreen[key] = record.id
            }

            // Snapshot the frame tiling is about to displace. The live AX frame wins over the
            // snapshot's: a parked window's record can still carry the column frame from before the
            // user (or a restore) moved it, and capturing that leaves the restore with nothing to
            // put back, so the window stays in its column when tiling is switched off or the app
            // quits. A record the tracker has not sampled at all also lands here.
            // Never sample a parked window here: its live frame is the park position, and remembering
            // that as "where tiling found it" made switching tiling off write every window back off
            // screen with nothing left to bring it in (found live 2026-11-27). `parkWorkspaceWindow`
            // seeds the recovery frame instead.
            if preTilingFrames[cg] == nil, parkedWorkspaceWindows[cg] == nil {
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
            let catalogLayout = layout(for: screen)
            let isStrip = drawsStrip(on: screen)
            var targetFrames: [WindowID: CGRect]
            var parked: [WindowID: StripParking.Side] = [:]
            if let catalogLayout {
                targetFrames = resolveFrames(tree, on: screen, workArea: workArea)
                overflow += max(0, eligible.count - catalogLayout.slots)
            } else if isStrip {
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
                    // The window is leaving the tiling set, so park nothing: put it back where tiling
                    // found it. Leaving it at the edge a scrolling strip parked it against means an
                    // off-screen window that no preset can reach again.
                    if let record = snapshot.windows[id], let cg = record.cgWindowID,
                       let original = preTilingFrames[cg] {
                        writeFrame(original, pid: record.pid, cgWindowID: cg)
                        lastAppliedFrames.removeValue(forKey: cg)
                    }
                    targetFrames = resolveFrames(tree, on: screen, workArea: workArea)
                }
            }
            trees[key] = tree

            // Apply frames via AX. The strip is the one layout whose columns legitimately sit past
            // the viewport edge (the next column's peek), so its writes skip the work-area clamp.
            applyFrames(targetFrames, records: snapshot.windows, primaryMaxY: primaryMaxY,
                        clampArea: isStrip ? nil : workArea, parked: parked)
        }
    }

    func reapplyLayout() {
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
            if drawsStrip(on: screen) {
                let ribbon = ribbonFrames(tree, on: screen, workArea: workArea, activeID: nil)
                applyFrames(ribbon.frames, records: lastWindows, primaryMaxY: primaryMaxY,
                            clampArea: nil, parked: ribbon.parked)
                continue
            }
            let targetFrames = resolveFrames(tree, on: screen, workArea: workArea)

            applyFrames(targetFrames, records: lastWindows, primaryMaxY: primaryMaxY, clampArea: workArea)
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
        /// Where the app's own edge clamp is corrected, or nil to write frames exactly as solved.
        /// The strip passes nil: its columns hang past the viewport on purpose, and pulling one
        /// back on screen by its overflow would overlap the column before it.
        clampArea: CGRect?,
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

            let quartzClampArea = clampArea.map {
                CGRect(origin: SnapPosition.accessibilityOrigin(of: $0, primaryMaxY: primaryMaxY), size: $0.size)
            }

            // Snapshot bounds are Quartz (top-left); store what the app really took (it may clamp to a minimum size)
            // in the same space or the window reads as hand-moved. Parked windows are written without
            // the work-area clamp, or the clamp would pull them straight back on screen.
            lastRequestedFrames[cg] = quartz
            // Parked columns are also written unclamped: the wedge macOS grants is what the strip wants.
            let within: CGRect? = parked[winID] != nil ? nil : quartzClampArea
            lastAppliedFrames[cg] = WindowSnapService.place(
                element, quartzFrame: quartz, within: within
            ) ?? quartz
            lastAppliedAt[cg] = ProcessInfo.processInfo.systemUptime
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

    func isTileable(_ record: WindowRecord, _ cg: CGWindowID) -> Bool {
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

    func resolveScreen(for record: WindowRecord, screens: [NSScreen], primaryMaxY: CGFloat) -> NSScreen {
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

    /// The display a workspace *switch* applies to: the one under the pointer.
    ///
    /// Workspaces are per display, and the cursor is the display the user is working on. Letting the
    /// focused window decide instead stole switches from a second screen whenever the frontmost app
    /// lived on the other one — and after parking on that screen the frontmost app was often the window
    /// that had just left, so `status` and the next chord fell back to the built-in (found live
    /// 2026-11-27 while exercising workspaces on the 4K).
    func activeScreen() -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let mouse = NSEvent.mouseLocation
        if let underPointer = screens.first(where: { $0.frame.contains(mouse) }) { return underPointer }
        return focusedWindowScreen(screens: screens) ?? NSScreen.main ?? screens.first
    }

    /// The display holding the focused window, when that window is actually visible on one. Moves use
    /// this rather than the pointer: the window has to be parked on the display it is on.
    func focusedWindowScreen(screens: [NSScreen]? = nil) -> NSScreen? {
        let screens = screens ?? NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let primaryMaxY = screens.first?.frame.maxY ?? 0
        guard let activeRecord = lastSnapshot?.windows.values.first(where: { $0.status == .active }),
              let bounds = activeRecord.bounds,
              !(activeRecord.cgWindowID.map { parkedWorkspaceWindows[$0] != nil } ?? false) else { return nil }
        let center = WindowFit.cocoaCenter(ofQuartzFrame: bounds, primaryMaxY: primaryMaxY)
        return screens.first { $0.frame.contains(center) }
    }

    private func activeScreenKey() -> String? {
        activeScreen().map(screenKey(for:))
    }

    /// Writes one Quartz frame to one window. Used when a window leaves the tiling set and has to go
    /// back to the frame tiling found it in.
    func writeFrame(_ quartz: CGRect, pid: pid_t, cgWindowID: CGWindowID) {
        guard let element = AXElementCache.shared.element(pid: pid, cgWindowID: cgWindowID)
                ?? axElement(for: pid, cgWindowID: cgWindowID) else { return }
        AXMessagingPolicy.applyTimeout(element)
        var origin = quartz.origin
        var size = quartz.size
        guard let point = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return }
        // Size first, then position: the other order clamps a tall window against the bottom edge.
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, point)
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
    }

    func axElement(for pid: pid_t, cgWindowID: CGWindowID) -> AXUIElement? {
        guard pid > 0 else { return nil }
        let app = AXMessagingPolicy.applyTimeout(AXUIElementCreateApplication(pid))
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

    // MARK: - Workspaces (W-4a, W-4b, W-5)

    static let workspacesEnabledKey = "com.katikati.workspace.enabled"
    static let workspaceActiveKey = "com.katikati.workspace.active"
    static let workspaceRegistryKey = "com.katikati.workspace.registry"
    static let workspaceRulesKey = "com.katikati.workspace.rules"
    static let workspaceStoreKey = "com.katikati.workspace.store"
    /// G-W2: the bar lists only the active workspace's cards. On by default; the alternative (every
    /// card, with a badge) is what turning this off gives you.
    static let workspaceBarFilterKey = "com.katikati.workspace.barFilter"

    /// Workspaces are off until the user turns them on, so an existing install behaves exactly as
    /// it did before this layer existed (G-W3).
    @Published private(set) var workspacesEnabled: Bool = UserDefaults.standard.bool(forKey: TilingEngine.workspacesEnabledKey)
    @Published private(set) var workspaceRegistry: WorkspaceRegistry = TilingEngine.storedWorkspaceRegistry()
    @Published private(set) var workspaceRules: WorkspaceRules = TilingEngine.storedWorkspaceRules()
    /// Which workspace each display is showing.
    @Published private(set) var activeWorkspaces: [String: WorkspaceID] = TilingEngine.storedActiveWorkspaces()

    /// Which workspace each window belongs to, per display (W-1).
    var workspaceStore = TilingEngine.storedWorkspaceStore()
    /// Trees of the workspaces that are not showing. `trees` keeps holding the active one, so every
    /// existing call site reads the active workspace without knowing workspaces exist (W-4a).
    var workspaceTrees: [WorkspaceID: [String: TilingTree]] = [:]
    /// Parked windows and the frame each one must return to (W-5).
    var parkedWorkspaceWindows: [CGWindowID: WorkspaceParking.Record] = [:]
    /// Rules that said `ignore`: never tiled, never owned, never moved.
    var ignoredWorkspaceWindows: Set<WindowID> = []
    /// Bundles whose first window has already been routed, so a `route … first` rule claims one window.
    var routedBundleIDs: Set<String> = []
    var didRecoverParkedWorkspaces = false

    func isPinned(_ id: WindowID) -> Bool {
        guard workspacesEnabled else { return false }
        return workspaceRules.disposition(bundleID: lastWindows[id]?.bundleIdentifier, title: lastWindows[id]?.title) == .pin
    }

    var showsOnlyActiveWorkspace: Bool {
        (UserDefaults.standard.object(forKey: Self.workspaceBarFilterKey) as? Bool) ?? true
    }

    func activeWorkspace(on displayKey: String) -> WorkspaceID {
        activeWorkspaces[displayKey]
            ?? workspaceRegistry.workspaces(on: displayKey).first
            ?? .numbered(1)
    }

    func setActiveWorkspace(_ workspace: WorkspaceID, on displayKey: String) {
        activeWorkspaces[displayKey] = workspace
        UserDefaults.standard.set(activeWorkspaces.mapValues(\.token), forKey: Self.workspaceActiveKey)
    }

    func setWorkspacesEnabled(_ on: Bool) {
        guard on != workspacesEnabled else { return }
        workspacesEnabled = on
        UserDefaults.standard.set(on, forKey: Self.workspacesEnabledKey)
        if on {
            // First enable migrates the existing float/tile lists, so a configured install sees the
            // same behaviour it had before workspaces existed (W-2).
            if UserDefaults.standard.object(forKey: Self.workspaceRulesKey) == nil {
                setWorkspaceRules(WorkspaceRules.migrated(from: policy))
            }
            WorkspaceControlServer.shared.start()
            if isEnabled { reconcile(with: lastSnapshot ?? .empty) }
        } else {
            revealAllParkedWorkspaces()
            WorkspaceControlServer.shared.stop()
            workspaceTrees.removeAll()
            ignoredWorkspaceWindows.removeAll()
            routedBundleIDs.removeAll()
        }
    }

    func setWorkspaceRules(_ rules: WorkspaceRules) {
        guard rules != workspaceRules else { return }
        workspaceRules = rules
        UserDefaults.standard.set(rules.serialized, forKey: Self.workspaceRulesKey)
        if workspacesEnabled, isEnabled, let snapshot = lastSnapshot { reconcile(with: snapshot) }
    }

    /// Registry mutation for the workspace extensions. Deliberately *not* `setWorkspaceRegistry`:
    /// a switch or a route is mid-flight and parks its own windows, so it must not trigger the
    /// settle-side reconcile that the settings path does.
    func enableWorkspace(_ workspace: WorkspaceID) {
        var registry = workspaceRegistry
        registry.enable(workspace)
        workspaceRegistry = registry
    }

    func setWorkspaceRegistry(_ registry: WorkspaceRegistry) {
        guard registry != workspaceRegistry else { return }
        workspaceRegistry = registry
        Self.persist(registry, forKey: Self.workspaceRegistryKey)
    }
}
