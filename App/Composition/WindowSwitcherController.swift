import AppKit
import Carbon.HIToolbox
import Combine
import OSLog
import SwiftUI

/// Phase 20c — Option+Tab window switcher with live thumbnails (inspired by AltTab; written from the behaviour,
/// not copied). Idle cost is a Combine subscription on the snapshot (MRU bookkeeping) and two Carbon hot keys;
/// the 50 ms modifier timer exists only while the panel is on screen. No global event monitor, no new permission
/// beyond the Screen Recording grant already used by hover previews (without it tiles show the app icon).
@MainActor
final class WindowSwitcherController: ObservableObject {
    static let enabledKey = "com.katikati.switcher.enabled"
    /// Legacy \"grid\" / \"sidebar\" key. Read once for migration by `AppSettingsStore`, never written here.
    static let layoutKey = "com.katikati.switcher.layout"
    static let sidebarWidth: CGFloat = 340
    static let learningKey = "com.katikati.switcher.learning"

    struct Tile: Identifiable, Equatable {
        let id: String
        let title: String
        let appName: String
        let bundleID: String?
        let cgWindowID: CGWindowID?
        let isMinimized: Bool
    }

    @Published private(set) var tiles: [Tile] = []
    @Published private(set) var selection = 0
    @Published private(set) var thumbnails: [String: NSImage] = [:]
    @Published private(set) var query = ""
    @Published private(set) var isSidebar = false
    @Published private(set) var style = WindowSwitcherStyle.thumbnail
    @Published private(set) var styleConfig = WindowSwitcherStyleConfig.standard
    /// Sidebar/list only: while on, releasing the modifier no longer commits; Return, a click or Esc ends it.
    @Published var pinned = false

    private let runtime: AppRuntime
    private let settings: AppSettingsStore
    private var mru: [String] = []
    private var allTiles: [Tile] = []
    /// The modifier whose release commits: Option for ⌥Tab, Command for the opt-in ⌘Tab.
    private var trigger: NSEvent.ModifierFlags = .option
    private let commandTab = CommandTabTakeover()
    private var snapshotSink: AnyCancellable?
    private var defaultsObserver: NSObjectProtocol?
    private var forward: GlobalHotKeyMonitor?
    private var backward: GlobalHotKeyMonitor?
    private var secondaryForward: GlobalHotKeyMonitor?
    private var secondaryBackward: GlobalHotKeyMonitor?
    private var pinnedMonitors: [GlobalHotKeyMonitor] = []
    private var appliedKey: ShortcutKey?
    private var appliedSecondaryKey: ShortcutKey?
    private var panel: SwitcherPanel?
    private var modifierTimer: Timer?
    private var captureGeneration: UInt64 = 0
    private var lastRankedWindowID: String?
    private let log = Logger(subsystem: "com.katikati.app", category: "switcher")

    init(runtime: AppRuntime, settings: AppSettingsStore) {
        self.runtime = runtime
        self.settings = settings
    }

    /// Starts MRU tracking and registers the hot keys when the setting is on; re-applies on setting changes.
    func start() {
        snapshotSink = runtime.$snapshot.sink { [weak self] snapshot in self?.noteSnapshot(snapshot) }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.applyEnabled() }
        }
        commandTab.onPress = { [weak self] reverse in self?.pressed(reverse: reverse, trigger: .command) }
        commandTab.onPressCurrentApp = { [weak self] reverse in
            self?.pressed(reverse: reverse, trigger: .command, currentAppOnly: true)
        }
        applyEnabled()
    }

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    private func applyEnabled() {
        commandTab.setEnabled(isEnabled && UserDefaults.standard.bool(forKey: CommandTabTakeover.enabledKey))
        applyPrimary()
        applySecondary()
        applyPinnedHotkeys()
    }

    private func applyPrimary() {
        let key = isEnabled ? boundKey : nil
        guard key != appliedKey || (key != nil && forward == nil) else { return }
        forward?.stop(); backward?.stop()
        forward = nil; backward = nil
        appliedKey = key
        guard let key else {
            if panel != nil { cancel() }
            return
        }
        forward = makeMonitor(key, id: ShortcutAction.windowSwitcher.hotKeyID, reverse: false)
        // Shift reverses; a binding that already uses Shift has no spare modifier for it.
        if key.modifiers & ShortcutKey.shift == 0 {
            backward = makeMonitor(key, id: ShortcutAction.windowSwitcher.hotKeyID + 1, reverse: true)
        }
    }

    /// The Settings › Shortcuts binding (default ⌥Tab); nil when set to Off.
    private var boundKey: ShortcutKey? {
        let stored = ShortcutTrigger.parse(UserDefaults.standard.string(forKey: "com.katikati.shortcut.\(ShortcutAction.windowSwitcher.rawValue)"))
        return (stored ?? ShortcutAction.windowSwitcher.defaultTrigger).switcherKey
    }

    private func applySecondary() {
        let key = isEnabled ? settings.secondarySwitcherKey : nil
        guard key != appliedSecondaryKey || (key != nil && secondaryForward == nil) else { return }
        secondaryForward?.stop(); secondaryBackward?.stop()
        secondaryForward = nil; secondaryBackward = nil
        appliedSecondaryKey = key
        guard let key else { return }
        secondaryForward = makeMonitor(key, id: ShortcutAction.windowSwitcher.hotKeyID + 20, reverse: false)
        if key.modifiers & ShortcutKey.shift == 0 {
            secondaryBackward = makeMonitor(key, id: ShortcutAction.windowSwitcher.hotKeyID + 21, reverse: true)
        }
    }

    private func applyPinnedHotkeys() {
        pinnedMonitors.forEach { $0.stop() }
        pinnedMonitors = []
        guard isEnabled else { return }
        var used: Set<ShortcutKey> = []
        if let appliedKey { used.insert(appliedKey) }
        if let appliedSecondaryKey { used.insert(appliedSecondaryKey) }
        for (index, pinned) in settings.pinnedAppHotkeys.enumerated() {
            guard !used.contains(pinned.key) else {
                log.warning("Pinned hotkey for \(pinned.bundleID, privacy: .public) collides with the switcher")
                continue
            }
            guard let shortcut = carbonShortcut(pinned.key, id: ShortcutAction.windowSwitcher.hotKeyID + 30 + UInt32(index)) else { continue }
            let monitor = GlobalHotKeyMonitor(shortcut: shortcut) { [weak self] in
                self?.pressedForApp(bundleID: pinned.bundleID)
            }
            if monitor.start() == .registered {
                used.insert(pinned.key)
                pinnedMonitors.append(monitor)
            } else {
                log.warning("Pinned hotkey \(shortcut.displayGlyphs, privacy: .public) not registered")
            }
        }
    }

    private func carbonShortcut(_ key: ShortcutKey, id: UInt32) -> GlobalHotKeyShortcut? {
        guard key.isValid else { return nil }
        var mods: UInt32 = 0
        if key.modifiers & ShortcutKey.control != 0 { mods |= UInt32(controlKey) }
        if key.modifiers & ShortcutKey.option != 0 { mods |= UInt32(optionKey) }
        if key.modifiers & ShortcutKey.shift != 0 { mods |= UInt32(shiftKey) }
        if key.modifiers & ShortcutKey.command != 0 { mods |= UInt32(cmdKey) }
        return GlobalHotKeyShortcut(keyCode: UInt32(key.keyCode), carbonModifiers: mods,
                                    displayGlyphs: key.glyphs, signature: 0x5467_4567, id: id)
    }

    /// Every bound modifier must stay down; releasing any one commits.
    private static func holdFlags(_ key: ShortcutKey) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if key.modifiers & ShortcutKey.control != 0 { flags.insert(.control) }
        if key.modifiers & ShortcutKey.option != 0 { flags.insert(.option) }
        if key.modifiers & ShortcutKey.command != 0 { flags.insert(.command) }
        return flags.isEmpty ? .shift : flags   // a Shift-only binding is held by Shift
    }

    private func makeMonitor(_ key: ShortcutKey, id: UInt32, reverse: Bool) -> GlobalHotKeyMonitor? {
        var mods: UInt32 = 0
        if key.modifiers & ShortcutKey.control != 0 { mods |= UInt32(controlKey) }
        if key.modifiers & ShortcutKey.option != 0 { mods |= UInt32(optionKey) }
        if key.modifiers & ShortcutKey.shift != 0 { mods |= UInt32(shiftKey) }
        if key.modifiers & ShortcutKey.command != 0 { mods |= UInt32(cmdKey) }
        if reverse { mods |= UInt32(shiftKey) }
        let shortcut = GlobalHotKeyShortcut(keyCode: UInt32(key.keyCode), carbonModifiers: mods,
                                            displayGlyphs: reverse ? "⇧" + key.glyphs : key.glyphs,
                                            signature: 0x5467_4567, id: id)
        let holdFlags = Self.holdFlags(key)
        let monitor = GlobalHotKeyMonitor(shortcut: shortcut) { [weak self] in
            self?.pressed(reverse: reverse, trigger: holdFlags)
        }
        let status = monitor.start()
        guard status == .registered else {
            log.warning("Window switcher \(shortcut.displayGlyphs, privacy: .public) not registered: \(String(describing: status), privacy: .public)")
            return nil
        }
        return monitor
    }

    // MARK: - MRU and predictive ranking

    private static func isSwitchable(_ w: WindowRecord) -> Bool {
        switch w.status {
        case .active, .inactive, .minimized, .hidden: return true
        case .closedPending, .disappeared: return false
        }
    }

    private func noteSnapshot(_ snapshot: DockSnapshot) {
        let alive = Set(snapshot.windows.values.filter(Self.isSwitchable).map(\.id.rawValue))
        let active = snapshot.windows.values.first { $0.status == .active }
        let activeID = active?.id.rawValue
        let next = WindowSwitcherModel.updatedMRU(mru, active: activeID, alive: alive)
        if next != mru { mru = next }
        guard settings.predictiveRankingEnabled, let active,
              activeID != lastRankedWindowID else { return }
        var ranker = loadRanker()
        ranker.record(bundleID: active.bundleIdentifier ?? "", title: active.title,
                      at: ProcessInfo.processInfo.systemUptime)
        saveRanker(ranker)
        lastRankedWindowID = activeID
    }

    private func loadRanker() -> WindowPredictiveRanker {
        guard let data = UserDefaults.standard.data(forKey: Self.learningKey),
              let ranker = try? JSONDecoder().decode(WindowPredictiveRanker.self, from: data) else {
            return WindowPredictiveRanker()
        }
        return ranker
    }

    private func saveRanker(_ ranker: WindowPredictiveRanker) {
        guard let data = try? JSONEncoder().encode(ranker) else { return }
        UserDefaults.standard.set(data, forKey: Self.learningKey)
    }

    private func record(_ tile: Tile) {
        guard settings.predictiveRankingEnabled else { return }
        var ranker = loadRanker()
        ranker.record(bundleID: tile.bundleID ?? "", title: tile.title,
                      at: ProcessInfo.processInfo.systemUptime)
        saveRanker(ranker)
    }

    // MARK: - Showing

    private func pressed(reverse: Bool, trigger: NSEvent.ModifierFlags = .option, currentAppOnly: Bool = false) {
        if panel != nil {
            selection = WindowSwitcherModel.step(selection: selection, count: tiles.count, reverse: reverse)
            return
        }
        self.trigger = trigger
        open(reverse: reverse, currentAppOnly: currentAppOnly)
    }

    private func pressedForApp(bundleID: String) {
        guard panel == nil else { return }
        trigger = .option
        open(reverse: false, bundleID: bundleID)
    }

    private func open(reverse: Bool, currentAppOnly: Bool = false, bundleID: String? = nil) {
        style = settings.switcherStyle
        guard style != .disabled else { return }
        let snapshot = runtime.snapshot
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var records = snapshot.windows.values.filter(Self.isSwitchable)
        if currentAppOnly { records = records.filter { $0.pid == frontPID } }
        if let bundleID { records = records.filter { $0.bundleIdentifier == bundleID } }
        let context = filterContext(snapshot: snapshot)
        records = settings.switcherFilterPolicy.filter(records, context: context)
        let byID = Dictionary(records.map { ($0.id.rawValue, $0) }, uniquingKeysWith: { a, _ in a })
        let base = WindowSwitcherModel.order(candidates: snapshot.orderedWindowIDs.map(\.rawValue).filter { byID[$0] != nil },
                                             mru: mru)
        let ordered = settings.predictiveRankingEnabled
            ? loadRanker().order(candidates: base, at: ProcessInfo.processInfo.systemUptime)
            : base
        allTiles = ordered.compactMap { id in
            guard let w = byID[id] else { return nil }
            let app = NSRunningApplication(processIdentifier: w.pid)
            return Tile(id: id, title: w.title, appName: app?.localizedName ?? w.bundleIdentifier ?? "",
                        bundleID: w.bundleIdentifier, cgWindowID: w.cgWindowID, isMinimized: w.status == .minimized)
        }
        if bundleID != nil, allTiles.count == 1, let only = allTiles.first {
            record(only)
            runtime.activate(windowID: only.id)
            return
        }
        guard allTiles.count > 1 else { allTiles = []; return }
        query = ""
        styleConfig = settings.switcherStyleConfig
        isSidebar = style == .list
        pinned = styleConfig.keepOpenOnRelease
        tiles = allTiles
        selection = WindowSwitcherModel.initialSelection(count: tiles.count, reverse: reverse)
        thumbnails = [:]
        captureGeneration &+= 1
        showPanel()
        loadThumbnails()
        startModifierWatch()
    }

    /// G2: read display/Space membership only when the user asked for those filters.
    private func filterContext(snapshot: DockSnapshot) -> WindowFilterContext {
        let policy = settings.switcherFilterPolicy
        guard policy.currentDisplayOnly || policy.currentSpaceOnly else { return WindowFilterContext() }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let displayUUID = screen.flatMap { ManagedSpaceLayoutReader.displayUUIDString(for: $0) }
        var currentSpaceIDs: Set<String>?
        if policy.currentSpaceOnly, let displayUUID,
           let layout = ManagedSpaceLayoutReader.layout(forDisplayUUID: displayUUID) {
            var ids: Set<String> = []
            for window in snapshot.windows.values {
                guard let cg = window.cgWindowID,
                      let spaces = WindowSpaceMembershipReader.spaceIDs(forWindowNumber: Int(cg)),
                      spaces.contains(layout.currentSpaceID) else { continue }
                ids.insert(window.id.rawValue)
            }
            currentSpaceIDs = ids
        }
        return WindowFilterContext(currentDisplayUUID: policy.currentDisplayOnly ? displayUUID : nil,
                                   currentSpaceWindowIDs: currentSpaceIDs)
    }

    private func showPanel() {
        let host = NSHostingView(rootView: WindowSwitcherView(controller: self, onPick: { [weak self] i in
            self?.selection = i; self?.commit()
        }))
        let size = host.fittingSize
        // The display under the cursor, not the one holding the menu bar.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens.first
        let area = screen?.visibleFrame ?? .zero
        let frame = isSidebar
            ? NSRect(x: area.minX, y: area.minY, width: Self.sidebarWidth, height: area.height)
            : NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
        let panel = SwitcherPanel(frame: frame)
        panel.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        panel.contentView = host
        panel.orderFrontRegardless()
        panel.makeKey()
        self.panel = panel
    }

    private func loadThumbnails() {
        guard style.usesLiveThumbnails, WindowThumbnailCapture.isAuthorized else { return }
        let generation = captureGeneration
        for tile in tiles {
            guard let cg = tile.cgWindowID, !tile.isMinimized else { continue }
            Task { @MainActor [weak self] in
                let image = await WindowThumbnailCapture.capture(
                    windowID: cg, maxPixelSize: CGSize(width: 520, height: 320))
                guard let self, self.captureGeneration == generation, self.panel != nil,
                      self.thumbnails[tile.id] == nil, let image else { return }
                self.thumbnails[tile.id] = image
            }
        }
    }

    private func startModifierWatch() {
        modifierTimer?.invalidate()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.panel != nil else { return }
                if !self.pinned, !NSEvent.modifierFlags.contains(self.trigger) { self.commit() }
            }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        modifierTimer = timer
    }

    private var columns: Int {
        switch style {
        case .thumbnail: return WindowSwitcherModel.columns(count: tiles.count)
        case .icons: return min(5, max(1, tiles.count))
        case .list, .classicIcons, .carousel, .disabled: return 1
        }
    }

    /// Returns true when the key was used.
    private func handleKey(_ event: NSEvent) -> Bool {
        let code = Int(event.keyCode)
        if event.modifierFlags.contains(.command) {
            switch code {
            case kVK_ANSI_W: act(.close)
            case kVK_ANSI_M: act(.minimize)
            case kVK_ANSI_Q: act(.quit)
            default: return false
            }
            return true
        }
        switch code {
        case kVK_Escape: cancel()
        case kVK_RightArrow: selection = WindowSwitcherModel.step(selection: selection, count: tiles.count, reverse: false)
        case kVK_LeftArrow: selection = WindowSwitcherModel.step(selection: selection, count: tiles.count, reverse: true)
        case kVK_DownArrow, kVK_UpArrow:
            selection = WindowSwitcherModel.rowStep(selection: selection, count: tiles.count,
                                                     columns: columns, down: code == kVK_DownArrow)
        case kVK_Return: commit()
        case kVK_Delete:
            guard !query.isEmpty else {
                act(.close)
                return true
            }
            query.removeLast(); applyQuery()
        default:
            if query.isEmpty, let digit = NumberedWindowSwitcherModel.digit(fromKeyCode: event.keyCode),
               let idx = NumberedWindowSwitcherModel.index(forDigit: digit, count: tiles.count) {
                selection = idx
                commit()
                return true
            }
            guard let text = event.charactersIgnoringModifiers, text.count == 1,
                  let scalar = text.unicodeScalars.first, scalar.value >= 32, scalar.value != 127 else { return false }
            query += text; applyQuery()
        }
        return true
    }

    private func applyQuery() {
        tiles = allTiles.filter { WindowSwitcherModel.matches(query: query, title: $0.title, appName: $0.appName) }
        selection = 0
        resizePanel()
    }

    private func resizePanel() {
        guard !isSidebar, let panel, let host = panel.contentView as? NSHostingView<WindowSwitcherView> else { return }
        let size = host.fittingSize
        let c = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        panel.setFrame(NSRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height),
                       display: true)
    }

    enum Action { case close, minimize, quit }

    func act(_ action: Action, on id: String? = nil) {
        guard let id = id ?? (tiles.indices.contains(selection) ? tiles[selection].id : nil) else { return }
        switch action {
        case .close: runtime.close(windowID: id)
        case .minimize: runtime.minimize(windowID: id)
        case .quit: runtime.quit(windowID: id)
        }
        allTiles.removeAll { $0.id == id }
        if allTiles.isEmpty { cancel() } else { applyQuery() }
    }

    private func commit() {
        let chosen = tiles.indices.contains(selection) ? tiles[selection] : nil
        if let chosen { record(chosen) }
        close()
        if let chosen { runtime.activate(windowID: chosen.id) }
    }

    private func cancel() { close() }

    private func close() {
        modifierTimer?.invalidate(); modifierTimer = nil
        captureGeneration &+= 1
        panel?.orderOut(nil); panel = nil
        tiles = []; allTiles = []; query = ""; thumbnails = [:]
    }

    var accentColor: Color {
        guard let color = styleConfig.accentColor else { return .accentColor }
        return Color(red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}

/// Borderless floating panel that can take key presses (Esc, arrows) without activating KatiKati.
private final class SwitcherPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = PanelCollectionBehavior.standard
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) { _ = onKey?(event) }
    // ⌘W / ⌘M / ⌘Q arrive as key equivalents; claim them so they never reach the app's menu.
    override func performKeyEquivalent(with event: NSEvent) -> Bool { onKey?(event) ?? false }
}

private struct WindowSwitcherView: View {
    @ObservedObject var controller: WindowSwitcherController
    let onPick: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hint: String {
        controller.query.isEmpty
            ? "1–9 Jump · Type to search · ⌘W close · ⌘M minimize"
            : "🔍 \(controller.query)"
    }

    var body: some View {
        Group {
            switch controller.style {
            case .thumbnail: thumbnailGrid
            case .list: list
            case .icons: iconGrid
            case .classicIcons: classicList
            case .carousel: carousel
            case .disabled: EmptyView()
            }
        }
        .opacity(controller.styleConfig.opacity)
    }

    // MARK: Thumbnail

    private var thumbnailGrid: some View {
        let columns = WindowSwitcherModel.columns(count: controller.tiles.count)
        let indexed = Array(controller.tiles.enumerated())
        let rows = stride(from: 0, to: indexed.count, by: columns).map {
            Array(indexed[$0..<min($0 + columns, indexed.count)])
        }
        return VStack(spacing: 10) {
            hintText
            if controller.tiles.isEmpty { emptyText }
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: controller.styleConfig.spacing) {
                    ForEach(rows[r], id: \.element.id) { index, tile in
                        thumbnailCard(tile, index: index, selected: index == controller.selection)
                            .onTapGesture { onPick(index) }
                    }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(20)
    }

    private func thumbnailCard(_ tile: WindowSwitcherController.Tile, index: Int, selected: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.18))
                if let image = controller.thumbnails[tile.id] {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(4)
                } else if let id = tile.bundleID {
                    Image(nsImage: AppIconResolver.icon(for: id)).resizable()
                        .frame(width: controller.styleConfig.iconSize, height: controller.styleConfig.iconSize)
                        .opacity(tile.isMinimized ? 0.5 : 1)
                }
            }
            .frame(height: 104)
            .overlay(alignment: .topLeading) { badge(index) }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Button { controller.act(.close, on: tile.id) } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 16))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain).padding(4)
                    .help(Text("Close window"))
                }
            }
            titleRow(tile)
        }
        .padding(8)
        .frame(width: 196)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(selected ? controller.accentColor.opacity(0.28) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(selected ? controller.accentColor : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
    }

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Windows").font(.system(size: 15, weight: .semibold))
                Spacer()
                Toggle("Keep Open", isOn: $controller.pinned).toggleStyle(.switch).controlSize(.small)
            }
            hintText
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        if controller.tiles.isEmpty { emptyText }
                        ForEach(Array(controller.tiles.enumerated()), id: \.element.id) { index, tile in
                            listRow(tile, index: index, selected: index == controller.selection)
                                .frame(maxWidth: .infinity)
                                .id(tile.id)
                                .onTapGesture { onPick(index) }
                        }
                    }
                }
                .onChange(of: controller.selection) { _ in
                    if controller.tiles.indices.contains(controller.selection) {
                        proxy.scrollTo(controller.tiles[controller.selection].id)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: WindowSwitcherController.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
    }

    private func listRow(_ tile: WindowSwitcherController.Tile, index: Int, selected: Bool) -> some View {
        HStack(spacing: 10) {
            badge(index)
            if let id = tile.bundleID {
                Image(nsImage: AppIconResolver.icon(for: id)).resizable()
                    .frame(width: controller.styleConfig.iconSize, height: controller.styleConfig.iconSize)
                    .opacity(tile.isMinimized ? 0.5 : 1)
            }
            titleRow(tile)
            Spacer(minLength: 0)
            if selected {
                Button { controller.act(.close, on: tile.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }.buttonStyle(.plain).help(Text("Close window"))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(selected ? controller.accentColor.opacity(0.25) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(selected ? controller.accentColor : Color.clear, lineWidth: 1.5))
        .contentShape(Rectangle())
    }

    // MARK: Icons / Classic

    private var iconGrid: some View {
        let columns = Array(repeating: GridItem(.fixed(controller.styleConfig.iconSize + 44), spacing: controller.styleConfig.spacing),
                            count: min(5, max(1, controller.tiles.count)))
        return VStack(spacing: 10) {
            hintText
            if controller.tiles.isEmpty { emptyText }
            LazyVGrid(columns: columns, spacing: controller.styleConfig.spacing) {
                ForEach(Array(controller.tiles.enumerated()), id: \.element.id) { index, tile in
                    iconCard(tile, index: index, selected: index == controller.selection)
                        .onTapGesture { onPick(index) }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(20)
    }

    private func iconCard(_ tile: WindowSwitcherController.Tile, index: Int, selected: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                if let id = tile.bundleID {
                    Image(nsImage: AppIconResolver.icon(for: id)).resizable()
                        .frame(width: controller.styleConfig.iconSize, height: controller.styleConfig.iconSize)
                        .opacity(tile.isMinimized ? 0.5 : 1)
                }
                badge(index)
            }
            Text(verbatim: tile.title.isEmpty ? tile.appName : tile.title)
                .font(.system(size: 11, weight: .medium)).lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(selected ? controller.accentColor.opacity(0.28) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(selected ? controller.accentColor : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
    }

    private var classicList: some View {
        VStack(spacing: 4) {
            hintText
            if controller.tiles.isEmpty { emptyText }
            ForEach(Array(controller.tiles.enumerated()), id: \.element.id) { index, tile in
                HStack(spacing: 10) {
                    badge(index)
                    if let id = tile.bundleID {
                        Image(nsImage: AppIconResolver.icon(for: id)).resizable().frame(width: 28, height: 28)
                    }
                    Text(verbatim: tile.title.isEmpty ? tile.appName : tile.title)
                        .font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(verbatim: tile.appName).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(index == controller.selection ? controller.accentColor.opacity(0.25) : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(index == controller.selection ? controller.accentColor : Color.clear, lineWidth: 1.5))
                .contentShape(Rectangle())
                .onTapGesture { onPick(index) }
            }
        }
        .padding(14)
        .frame(width: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(20)
    }

    // MARK: Carousel

    private var carousel: some View {
        VStack(spacing: 12) {
            hintText
            HStack(spacing: 12) {
                ForEach(Array(controller.tiles.enumerated()), id: \.element.id) { index, tile in
                    let distance = index - controller.selection
                    VStack(spacing: 6) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.2))
                            if let image = controller.thumbnails[tile.id] {
                                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                                    .padding(4)
                            } else if let id = tile.bundleID {
                                Image(nsImage: AppIconResolver.icon(for: id)).resizable()
                                    .frame(width: controller.styleConfig.iconSize, height: controller.styleConfig.iconSize)
                            }
                        }
                        .frame(width: index == controller.selection ? 220 : 160, height: 138)
                        Text(verbatim: tile.title.isEmpty ? tile.appName : tile.title)
                            .font(.system(size: 11, weight: index == controller.selection ? .semibold : .regular))
                            .lineLimit(1).frame(width: index == controller.selection ? 220 : 160)
                    }
                    .scaleEffect(index == controller.selection ? 1 : 0.88)
                    .opacity(index == controller.selection ? 1 : 0.65)
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : Double(distance) * -8),
                                      axis: (x: 0, y: 1, z: 0), perspective: reduceMotion ? 0 : 0.35)
                    .zIndex(index == controller.selection ? 1 : 0)
                    .onTapGesture { onPick(index) }
                }
            }
            HStack(spacing: 8) {
                ForEach(Array(controller.tiles.enumerated()), id: \.element.id) { index, tile in
                    if let id = tile.bundleID {
                        Image(nsImage: AppIconResolver.icon(for: id)).resizable()
                            .frame(width: 22, height: 22)
                            .padding(3)
                            .background(Circle().fill(index == controller.selection
                                ? controller.accentColor.opacity(0.35) : Color.clear))
                            .onTapGesture { onPick(index) }
                    }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(20)
    }

    // MARK: Shared bits

    private var hintText: some View {
        Text(verbatim: hint).font(.system(size: 11)).foregroundStyle(.secondary)
    }

    private var emptyText: some View {
        Text("No matching windows").foregroundStyle(.secondary).padding(30)
    }

    private func titleRow(_ tile: WindowSwitcherController.Tile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: tile.title.isEmpty ? tile.appName : tile.title)
                .font(.system(size: 11, weight: .medium)).lineLimit(1)
            if !tile.title.isEmpty {
                Text(verbatim: tile.appName).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func badge(_ index: Int) -> some View {
        if let badge = NumberedWindowSwitcherModel.digitBadge(for: index) {
            Text(verbatim: badge)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(0.65)))
        }
    }
}
