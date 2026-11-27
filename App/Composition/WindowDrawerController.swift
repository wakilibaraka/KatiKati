import AppKit
import Carbon.HIToolbox
import Combine
import OSLog
import SwiftUI

/// Edge drawer: a left icon rail (Windows, Layouts, Clipboard, plus shortcuts to the existing Search and Apps
/// panels) over a content pane. Windows tab = searchable thumbnail grid. Opened with ⌃⌥W on the display under
/// the cursor; Esc or a click outside closes it.
// shortcut: edge hover polls the pointer at ~7 Hz and only watches the left edge of each display.
@MainActor
final class WindowDrawerController: ObservableObject {
    /// SD-1/SD-2: the rail's tabs are the pure `SideDeckTab` in `Core/Support/EdgeBarPrefs.swift`, so the
    /// notch removal, the badges and the search placeholders are unit-tested without a window.
    typealias Tab = SideDeckTab
    static let edgeHoverKey = "com.katikati.drawer.edgeHover"

    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        let appName: String
        let bundleID: String?
        let cgWindowID: CGWindowID?
        let isMinimized: Bool
    }

    @Published var tab: Tab = .windows
    @Published var query = "" { didSet { selectionChanged() } }
    @Published private(set) var items: [Item] = []
    @Published private(set) var thumbnails: [String: NSImage] = [:]
    /// SD-2: the bell tab's All/Unread pill, plus one keyboard selection per navigable list.
    @Published var notificationsUnreadOnly = false
    @Published private(set) var windowSelection = SideDeckSelection()
    @Published private(set) var notificationSelection = SideDeckSelection()
    @Published private(set) var genericSelection = SideDeckSelection()

    private let runtime: AppRuntime
    private let onSearch: () -> Void
    private let onApps: () -> Void
    private var panel: DrawerPanel?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    /// SD-1: the resting handle owns the edge now — its tracking area replaces the old location poll.
    private var handle: SideDeckHandleWindow?
    private var peekWork: DispatchWorkItem?
    private var defaultsObserver: NSObjectProtocol?
    private let log = Logger(subsystem: "com.katikati.app", category: "drawer")

    init(runtime: AppRuntime, onSearch: @escaping () -> Void, onApps: @escaping () -> Void) {
        self.runtime = runtime; self.onSearch = onSearch; self.onApps = onApps
    }

    func start() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.applyEdgeHover() }
        }
        applyEdgeHover()
        TendederoClotheslineController.shared.onNewScreenshot = { [weak self] in
            // NP-1: the screenshot still hangs itself; only the deck peek needs the owner's opt-in.
            guard TendederoPolicy.showSidebarOnNewItem() else { return }
            self?.peekTendedero()
        }
        if TendederoPolicy.shouldStartMonitoringAtLaunch() {
            TendederoClotheslineController.shared.start()
        }
    }

    func peekTendedero() {
        tab = .tendedero
        if panel == nil { open() }
        schedulePeekClose()
    }

    private func schedulePeekClose() {
        peekWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, let panel = self.panel, self.tab == .tendedero, !self.isPinnedOpen else { return }
                if panel.frame.contains(NSEvent.mouseLocation) {
                    self.schedulePeekClose()
                } else {
                    self.close()
                }
            }
        }
        peekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    /// SD-1: the 7 Hz `NSEvent.mouseLocation` poll is retired. The resting handle is a window with its own
    /// tracking area, so the deck learns about the pointer from the system instead of asking for it.
    private func applyEdgeHover() {
        let config = SideDeckConfig.migrating(from: .standard)
        guard config.edgeActivation else {
            handle?.hide()
            handle = nil
            return
        }
        if handle == nil {
            handle = SideDeckHandleWindow(onOpen: { [weak self] in
                guard let self, self.panel == nil else { return }
                self.open()
            })
        }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let screen {
            handle?.show(on: screen, side: config.side, mergedWeatherHandle: config.mergedWeatherHandle)
        }
    }

    func toggle() { panel == nil ? open() : close() }

    /// Gesture entry point: reveals the Windows section, opening the drawer when it is closed.
    func showWindows() { show(.windows) }

    func show(_ tab: Tab) {
        if panel == nil { open() }
        select(tab)
    }

    func select(_ tab: Tab) {
        self.tab = tab
        query = ""
        windowSelection = SideDeckSelection()
        notificationSelection = SideDeckSelection()
    }

    func runSearch() { close(); onSearch() }
    func runApps() { close(); onApps() }

    func activate(_ id: String) { close(); runtime.activate(windowID: id) }

    func closeWindow(_ id: String) {
        runtime.close(windowID: id)
        items.removeAll { $0.id == id }
    }

    var filtered: [Item] {
        items.filter { WindowSwitcherModel.matches(query: query, title: $0.title, appName: $0.appName) }
    }

    /// SD-2: the inbox the bell tab draws — the same visible rows the rail's badge counts.
    var visibleNotifications: [NotificationHistoryEntry] {
        let mirror = NotificationMirrorService.shared
        return mirror.historyStore.visibleEntries(
            query: query,
            unreadOnly: notificationsUnreadOnly,
            sensitiveBundleIDs: mirror.activeSensitiveBundleIDs(),
            placeholder: String(localized: "Notification content hidden")
        )
    }

    var unreadNotificationCount: Int {
        SideDeckBadges.unreadNotificationCount(NotificationMirrorService.shared.historyStore.entries)
    }

    var stagedShelfCount: Int {
        SideDeckBadges.stagedShelfCount(TendederoClotheslineController.shared.store.items)
    }

    var selectedWindow: Item? {
        filtered.indices.contains(windowSelection.index) ? filtered[windowSelection.index] : nil
    }

    var selectedNotification: NotificationHistoryEntry? {
        let rows = visibleNotifications
        return rows.indices.contains(notificationSelection.index) ? rows[notificationSelection.index] : nil
    }

    /// The list under a selection changed (a query, a dismissed row): keep the highlight on a real row.
    private func selectionChanged() {
        windowSelection.clamp(count: filtered.count)
        notificationSelection.clamp(count: visibleNotifications.count)
        genericSelection.clamp(count: actionItemCount(for: tab))
    }

    private func actionItemCount(for tab: Tab) -> Int {
        switch tab {
        case .downloads: return DownloadManagerService.shared.items.count
        case .clipboard: return ProductivityServices.shared.clipboard.history.entries.count
        case .tendedero: return TendederoClotheslineController.shared.store.items.count
        case .quickAccess: return 2
        case .layouts: return 4
        case .dashboard: return 4
        default: return 0
        }
    }

    var isPinnedOpen: Bool { UserDefaults.standard.bool(forKey: SideDeckPrefs.pinKey) }

    // MARK: - Keyboard (SD-2)

    func moveSelection(_ delta: Int) {
        switch tab {
        case .windows: windowSelection.move(by: delta, count: filtered.count)
        case .notifications: notificationSelection.move(by: delta, count: visibleNotifications.count)
        case .quickAccess:
            if UserDefaults.standard.string(forKey: "com.katikati.sideDeck.quickAccessMode") != "launcher" {
                AppDelegate.shared?.commandBarPanel.moveEmbeddedSelection(delta)
            } else {
                genericSelection.move(by: delta, count: actionItemCount(for: tab))
            }
        default: genericSelection.move(by: delta, count: actionItemCount(for: tab))
        }
    }

    func activateSelection() {
        switch tab {
        case .windows: if let item = selectedWindow { activate(item.id) }
        case .notifications: if let entry = selectedNotification { openNotification(entry) }
        case .quickAccess:
            if genericSelection.index == 0 { runApps() } else { runSearch() }
        case .clipboard:
            let entries = ProductivityServices.shared.clipboard.history.entries
            if entries.indices.contains(genericSelection.index) {
                ProductivityServices.shared.clipboard.pastePlain(entries[genericSelection.index])
            }
        case .dashboard:
            let targets: [Tab] = [.windows, .notifications, .downloads, .weather]
            if targets.indices.contains(genericSelection.index) { select(targets[genericSelection.index]) }
        default: break
        }
    }

    func dismissSelection() {
        switch tab {
        case .windows: if let id = selectedWindow?.id { closeWindow(id) }
        case .notifications: if let entry = selectedNotification { dismissNotification(entry) }
        default: close()
        }
    }

    /// Opens the notification's app and marks the row read, exactly like a click on its card.
    func openNotification(_ entry: NotificationHistoryEntry) {
        NotificationMirrorService.shared.markRead(id: entry.id)
        guard let bundleIdentifier = entry.appBundleId,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func dismissNotification(_ entry: NotificationHistoryEntry) {
        NotificationMirrorService.shared.dismiss(id: entry.id)
        notificationSelection.clamp(count: visibleNotifications.count)
    }

    /// ⌫ and ⏎ stay out of the way while the search field is being edited; ↑/↓ always move the selection.
    func handleKey(_ event: NSEvent) -> Bool {
        let editing = panel?.firstResponder is NSTextView
        switch event.keyCode {
        case 126: moveSelection(-1); return true
        case 125: moveSelection(1); return true
        case 36, 76: guard !editing else { return false }; activateSelection(); return true
        case 51: guard !editing else { return false }; dismissSelection(); return true
        case 53:
            // SD-1: Escape dismisses the deck through `close()` — the same path the foot chevron and
            // the click-away monitor use. The panel is key while this app owns the keyboard, but this
            // local monitor sees the event before the responder chain, so `cancelOperation` never
            // runs; the key map simply had no Escape case and let it fall through. Like the deck's
            // arrow keys, Escape reaches here only while the app is frontmost.
            close(); return true
        default: return false
        }
    }

    // MARK: - Showing

    private func open() {
        let snapshot = runtime.snapshot
        items = snapshot.orderedWindowIDs.compactMap { id -> Item? in
            guard let w = snapshot.windows[id] else { return nil }
            switch w.status {
            case .closedPending, .disappeared: return nil
            default: break
            }
            let app = NSRunningApplication(processIdentifier: w.pid)
            return Item(id: id.rawValue, title: w.title, appName: app?.localizedName ?? w.bundleIdentifier ?? "",
                        bundleID: w.bundleIdentifier, cgWindowID: w.cgWindowID, isMinimized: w.status == .minimized)
        }
        query = ""; tab = .windows; thumbnails = [:]
        windowSelection = SideDeckSelection(); notificationSelection = SideDeckSelection()

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame
        // SD-1: the shell's geometry is `SideDeckConfig`'s, not a literal — full height, inset below the menu
        // bar and above the Dock, on whichever edge the owner chose.
        let frame = SideDeckConfig.migrating(from: .standard).panelFrame(in: area)
        let panel = DrawerPanel(frame: frame)
        panel.onEscape = { [weak self] in self?.close() }
        panel.contentView = NSHostingView(rootView: WindowDrawerView(controller: self))
        panel.orderFrontRegardless()
        panel.makeKey()
        self.panel = panel
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel, !panel.frame.contains(NSEvent.mouseLocation),
                      !self.isPinnedOpen else { return }
                self.close()
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            var handled = false
            MainActor.assumeIsolated { handled = self?.handleKey(event) ?? false }
            return handled ? nil : event
        }
        loadThumbnails()
    }

    private func loadThumbnails() {
        guard WindowThumbnailCapture.isAuthorized else { return }
        for item in items {
            guard let cg = item.cgWindowID, !item.isMinimized else { continue }
            Task { @MainActor [weak self] in
                let image = await WindowThumbnailCapture.capture(windowID: cg, maxPixelSize: CGSize(width: 420, height: 260))
                guard let self, self.panel != nil, let image else { return }
                self.thumbnails[item.id] = image
            }
        }
    }

    func close() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.orderOut(nil); panel = nil
        items = []; thumbnails = [:]
    }
}

private final class DrawerPanel: NSPanel {
    var onEscape: (() -> Void)?

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
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

private struct WindowDrawerView: View {
    @ObservedObject var controller: WindowDrawerController
    @ObservedObject private var mirror = NotificationMirrorService.shared
    @ObservedObject private var shelf = TendederoClotheslineController.shared
    @ObservedObject private var monitor = ProductivityServices.shared.systemMonitor
    @AppStorage(SideDeckPrefs.pinKey) private var pinned = false
    // OW-1: the HUD's two densities and the label scale live in `WidgetHUDDensityMode` / `WidgetTextScale`.
    @AppStorage(WidgetHUDDensityMode.defaultsKey) private var densityRaw = WidgetHUDDensityMode.expanded.rawValue
    @AppStorage(WidgetTextScale.defaultsKey) private var textScaleRaw = WidgetTextScale.regular.rawValue
    @State private var holdsMonitor = false
    /// SD-1: the shell's entry animation (0.98 → 1 with a fade) and the optional identity strip.
    @State private var appeared = false
    @State private var identityStripEnabled = SideDeckConfig.stored().identityStrip
    /// SD-1: which edge the deck is docked to, so the foot chevron can point away from it.
    @State private var deckSide = SideDeckConfig.stored().side
    @AppStorage("com.katikati.theme.followDockTheme") private var followDockTheme = true
    @AppStorage("com.katikati.theme.material") private var dockThemeToken = DockThemeStyle.auto.token
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool

    private var density: WidgetHUDDensityMode { WidgetHUDDensityMode.parse(densityRaw) }
    private var textScale: WidgetTextScale { WidgetTextScale.parse(textScaleRaw) }
    private var activeDockTheme: DockThemeStyle { followDockTheme ? (DockThemeStyle(token: dockThemeToken) ?? .auto) : .auto }
    private var themeTokens: DockThemeTokens { .resolved(for: colorScheme, style: activeDockTheme) }

    var body: some View {
        VStack(spacing: 0) {
            headerCapsule
                .padding(.horizontal, 4)
                .padding(.top, 4)
            if density.isCompact {
                compactStrip
            } else {
                // SD-1: the rail is a detached capsule, so nothing divides it from the panel and the gap is
                // the plan's 12 pt rather than a rule.
                HStack(spacing: 12) {
                    rail
                    if identityStripEnabled { identityStrip }
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // SD-1/SD-2: 20 ms behind the shell, the same deck spring.
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.34, dampingFraction: 0.84).delay(0.02), value: appeared)
                }
                .padding(16)
                pageDock
                    .padding(.bottom, 10)
            }
        }
        // SD-1: one radius for the whole shell, the sanctioned deck glass radius (26).
        .background {
            let shape = RoundedRectangle(cornerRadius: EdgeStyleTokens.glassRadius, style: .continuous)
            ZStack {
                shape.fill(.regularMaterial)
                if followDockTheme, activeDockTheme.tintsPlate {
                    shape.fill(themeTokens.styleTokens.baseTint.color.opacity(colorScheme == .dark ? 0.34 : 0.24))
                    shape.strokeBorder(themeTokens.styleTokens.rim.color.opacity(0.28), lineWidth: 0.75)
                }
            }
        }
        .environment(\.dockThemeStyle, activeDockTheme)
        // SD-1: entry motion — the deck spring, a 0.98 → 1 scale and a fade. Reduce Motion keeps the fade.
        .scaleEffect(appeared ? 1 : SideDeckConfig.entryScale(reduceMotion: reduceMotion))
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: appeared)
        .onAppear {
            searchFocused = true
            syncMonitorHold()
            appeared = true
        }
        .onChange(of: densityRaw) { _ in syncMonitorHold() }
        .onDisappear { releaseMonitorHold() }
    }

    /// Compact needs readings, and readings cost a 1 s timer: hold it only while the strip is on screen.
    private func syncMonitorHold() {
        if density.isCompact, !holdsMonitor {
            monitor.acquire()
            holdsMonitor = true
        } else if !density.isCompact {
            releaseMonitorHold()
        }
    }

    private func releaseMonitorHold() {
        guard holdsMonitor else { return }
        monitor.release()
        holdsMonitor = false
    }

    /// OW-1: the whole stack as one line — the same live readings the pane shows, at the owner's text step.
    /// A missing reading is left out rather than drawn as a zero.
    private var compactStrip: some View {
        let s = monitor.snapshot
        let size = textScale.scaled(11)
        let unread = SideDeckBadges.unreadNotificationCount(mirror.historyStore.entries)
        let staged = SideDeckBadges.stagedShelfCount(shelf.store.items)
        return HStack(spacing: 12) {
            reading("cpu", SystemMonitorFormat.percent(s.cpu), size: size)
            reading("memorychip", SystemMonitorFormat.percent(s.memory.fraction), size: size)
            reading("arrow.down", SystemMonitorFormat.bytes(s.down) + "/s", size: size)
            if unread > 0 { reading("bell.fill", "\(unread)", size: size) }
            if staged > 0 { reading("tray.full", "\(staged)", size: size) }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func reading(_ symbol: String, _ value: String, size: CGFloat) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: max(9, textScale.scaled(10))))
            Text(verbatim: value)
        }
        .font(.system(size: size, weight: .medium, design: .rounded).monospacedDigit())
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    /// SD-2 (render 2): the header capsule — 54 pt tall on a full radius, spanning the panel: avatar and the
    /// owner's name, the translucent search pill with its 24 pt leading glyph, then the density pill and the
    /// bell with its unread dot.
    private var headerCapsule: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.accentColor.opacity(0.18))
                .frame(width: 34, height: 34)
                .overlay(Text(verbatim: initials).font(.system(size: 13, weight: .semibold)))
            Text(verbatim: NSFullUserName())
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
            searchPill
            Button { densityRaw = density.toggled.rawValue } label: {
                Image(systemName: density.toggleSymbol).font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help(density.isCompact ? Text("Expand") : Text("Compact"))
            Button { controller.select(.notifications) } label: {
                Image(systemName: SideDeckTab.notifications.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
                    .overlay(alignment: .topTrailing) {
                        if controller.unreadNotificationCount > 0 {
                            Circle().fill(Color.accentColor).frame(width: 7, height: 7).offset(x: 2, y: -2)
                        }
                    }
            }
            .buttonStyle(.plain)
            .help(Text("Notifications"))
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    /// The avatar's letters: the owner's initials, which need no localized string.
    private var initials: String {
        let letters = NSFullUserName().split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "K" : String(letters).uppercased()
    }

    /// The translucent search pill: one field for every tab, its placeholder the pure tab helper.
    private var searchPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            TextField(controller.tab.searchPlaceholder, text: $controller.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !controller.query.isEmpty {
                Button { controller.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(Text("Clear"))
            }
            Menu {
                ForEach(WidgetTextScale.allCases, id: \.self) { scale in
                    Button { textScaleRaw = scale.rawValue } label: { textScaleTitle(scale) }
                }
            } label: {
                Image(systemName: "textformat.size").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(Text("Text Size"))
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    /// SD-2 (render 2): the floating page dock — a 44 pt capsule with a white selected pill and a trailing
    /// "+". SD-8 owns page visibility, so the plus is wired to page selection here and nothing more.
    private var pageDock: some View {
        HStack(spacing: 4) {
            ForEach([SideDeckTab.windows, .notifications, .downloads, .storage, .weather], id: \.self) { tab in
                let selected = controller.tab == tab
                Button { controller.select(tab) } label: {
                    Text(verbatim: tab.title)
                        .font(.system(size: 11, weight: selected ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(selected ? Color.white.opacity(0.92) : .clear))
                        .foregroundStyle(selected ? Color.black.opacity(0.78) : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Menu {
                ForEach(SideDeckTab.allCases, id: \.self) { tab in
                    Button { controller.select(tab) } label: { Text(verbatim: tab.title) }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.primary.opacity(0.10)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(Text("Open"))
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.07)))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75))
        .accessibilityElement(children: .contain)
    }

    /// SD-2: the bento column count, from the plan's breakpoints over the panel's content width. This is the
    /// one place it is computed, so every grid in the deck agrees on it.
    private var panelColumns: Int {
        let contentWidth = SideDeckConfig.stored().width - 60 - 12 - 32
        return SideDeckConfig.columns(forContentWidth: contentWidth)
    }

    /// SD-2: one field for every tab. Its placeholder is the pure tab helper, so it always names what
    /// the list under it actually filters.
    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField(controller.tab.searchPlaceholder, text: $controller.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !controller.query.isEmpty {
                Button { controller.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(Text("Clear"))
            }
            // OW-1: fold the stack into one line, and pick the label step the strip draws at.
            Button { densityRaw = density.toggled.rawValue } label: {
                Image(systemName: density.toggleSymbol).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(density.isCompact ? Text("Expand") : Text("Compact"))
            Menu {
                ForEach(WidgetTextScale.allCases, id: \.self) { scale in
                    Button { textScaleRaw = scale.rawValue } label: { textScaleTitle(scale) }
                }
            } label: {
                Image(systemName: "textformat.size").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(Text("Text Size"))
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private func textScaleTitle(_ scale: WidgetTextScale) -> Text {
        switch scale {
        case .small: return Text("Small")
        case .regular: return Text("Medium")
        case .large: return Text("Large")
        }
    }

    @ViewBuilder private var content: some View {
        switch controller.tab {
        case .windows: windows
        case .notifications: SideDeckNotificationsView(controller: controller)
        case .downloads: SideDeckDownloadsPane(feed: LiveActivityFeed.shared)
        case .dictionary: SideDeckDictionaryPane(query: $controller.query)
        case .dashboard: SideDeckDashboardView { controller.select($0) }
        case .storage: SideDeckStorageView()
        case .weather: SideDeckWeatherView()
        case .aiMissionControl: SideDeckAIMissionControlView()
        case .quickAccess:
            SideDeckQuickAccessView(
                onLauncher: controller.runApps,
                onCommandBar: controller.runSearch,
                onCloseDeck: { [weak controller] in controller?.close() }
            )
        case .layouts:
            VStack(spacing: 8) {
                WindowsFlyoutView()
                Text("Drag a window onto a layout slot").font(.system(size: 11)).foregroundStyle(.secondary)
                dragRow
                Spacer(minLength: 0)
            }
        case .clipboard: ClipboardFlyoutView(query: controller.query)
        case .emoji: EmojiDrawerPane(query: $controller.query)
        case .tendedero: LeftSidebarClotheslineView(query: controller.query)
        case .scratchpad: ScratchpadPane()
        case .markets: TickerPane()
        }
    }

    /// SD-1 (render 3): the optional identity strip — a 90° caption, a hairline and a Settings capsule at its
    /// foot. Off by default; the caption is the brand, so it is shown verbatim rather than as a new key.
    private var identityStrip: some View {
        VStack(spacing: 10) {
            Text(verbatim: "KATIKATI")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(-90))
                .fixedSize()
                .frame(maxHeight: .infinity)
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 24)
            Button {
                // The app has no `showSettingsWindow:` responder action (SwiftUI Settings scenes are opened
                // through `AppDelegate`, like every other surface); sending it did nothing.
                AppDelegate.shared?.openSettings(selecting: .sideDeck)
            } label: {
                Image(systemName: "gearshape").font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.primary.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .help(Text("Settings"))
            .accessibilityLabel(Text("Settings"))
        }
        .padding(.vertical, 8)
        .frame(width: 26)
    }

    private var rail: some View {
        VStack(spacing: 10) {
            SideDeckRailButton(symbol: "magnifyingglass", title: Text("Search"), selected: false) { controller.runSearch() }
            SideDeckRailButton(symbol: SideDeckTab.windows.symbol, title: Text("Windows"),
                               selected: controller.tab == .windows) { controller.select(.windows) }
            SideDeckRailButton(symbol: "square.grid.2x2", title: Text("Apps"), selected: false) { controller.runApps() }
            SideDeckRailButton(symbol: SideDeckTab.aiMissionControl.symbol, title: Text("AI Mission Control"),
                               selected: controller.tab == .aiMissionControl) { controller.select(.aiMissionControl) }
            // SD-1/SD-2: the bell, with the live unread badge the notch inbox used to carry.
            SideDeckRailButton(symbol: SideDeckTab.notifications.symbol, title: Text("Notifications"),
                               selected: controller.tab == .notifications,
                               badge: controller.unreadNotificationCount) { controller.select(.notifications) }
            SideDeckRailButton(symbol: SideDeckTab.downloads.symbol, title: Text("Downloads"),
                               selected: controller.tab == .downloads) { controller.select(.downloads) }
            SideDeckRailButton(symbol: SideDeckTab.dictionary.symbol, title: Text("Dictionary"),
                               selected: controller.tab == .dictionary) { controller.select(.dictionary) }
            SideDeckRailButton(symbol: SideDeckTab.dashboard.symbol, title: Text(verbatim: "Dashboard"),
                               selected: controller.tab == .dashboard) { controller.select(.dashboard) }
            SideDeckRailButton(symbol: SideDeckTab.storage.symbol, title: Text("Storage"),
                               selected: controller.tab == .storage) { controller.select(.storage) }
            SideDeckRailButton(symbol: SideDeckTab.weather.symbol, title: Text("Weather"),
                               selected: controller.tab == .weather) { controller.select(.weather) }
            SideDeckRailButton(symbol: SideDeckTab.quickAccess.symbol, title: Text("Quick Access"),
                               selected: controller.tab == .quickAccess) { controller.select(.quickAccess) }
            SideDeckRailButton(symbol: SideDeckTab.layouts.symbol, title: Text("Layouts"),
                               selected: controller.tab == .layouts) { controller.select(.layouts) }
            SideDeckRailButton(symbol: SideDeckTab.emoji.symbol, title: Text("Emoji"),
                               selected: controller.tab == .emoji) { controller.select(.emoji) }
            SideDeckRailButton(symbol: SideDeckTab.clipboard.symbol, title: Text("Clipboard"),
                               selected: controller.tab == .clipboard) { controller.select(.clipboard) }
            SideDeckRailButton(symbol: SideDeckTab.tendedero.symbol, title: Text("Clothesline"),
                               selected: controller.tab == .tendedero,
                               badge: controller.stagedShelfCount) { controller.select(.tendedero) }
            // OW-3: the scratch note, one rail button away.
            SideDeckRailButton(symbol: SideDeckTab.scratchpad.symbol, title: Text("Scratchpad"),
                               selected: controller.tab == .scratchpad) { controller.select(.scratchpad) }
            Spacer(minLength: 6)
            Toggle(isOn: $pinned) {
                Image(systemName: pinned ? "pin.fill" : "pin").font(.system(size: 15))
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .frame(width: 36, height: 36)
            .help(Text("Pin Strip Open"))
            .accessibilityLabel(Text("Pin Strip Open"))
            // SD-1 (render 2): the bottom chevron folds the deck away. It goes through the same
            // `close()` the panel's click-away monitor uses — one close path, not a second one — and
            // points away from the docked edge. The gear stays at the identity strip's foot, and the
            // Pin toggle keeps its place above the chevron: pinning holds the deck open, collapsing
            // dismisses it, so the two do not compete.
            SideDeckRailButton(symbol: deckSide == .left ? "chevron.left" : "chevron.right",
                               title: Text("Collapse"), selected: false) { controller.close() }
        }
        .padding(8)
        // SD-1 (renders 2–3): the rail is its own capsule — 60 pt wide, 26 pt radius, an 8 pt inset and a soft
        // shadow that lifts it off the panel behind it.
        .frame(width: 60)
        .background(EdgeGlassSurface(shape: RoundedRectangle(cornerRadius: 26, style: .continuous)))
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
    }

    private var windows: some View {
        VStack(spacing: 10) {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: panelColumns),
                          spacing: 10) {
                    ForEach(Array(controller.filtered.enumerated()), id: \.element.id) { index, item in
                        card(item, selected: controller.windowSelection.index == index)
                    }
                }
            }
            if controller.filtered.isEmpty { Text("No matching windows").foregroundStyle(.secondary) }
        }
        .padding(12)
    }

    /// Window icons to drag onto a slot in the Layouts picker above.
    private var dragRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(controller.items) { item in
                    Group {
                        if let id = item.bundleID {
                            Image(nsImage: AppIconResolver.icon(for: id)).resizable()
                        } else {
                            Image(systemName: "macwindow").resizable().scaledToFit()
                        }
                    }
                    .frame(width: 32, height: 32)
                    .onDrag { NSItemProvider(object: item.id as NSString) }
                    .help(Text(verbatim: item.title))
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 40)
    }

    private func card(_ item: WindowDrawerController.Item, selected: Bool = false) -> some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.18))
                if let image = controller.thumbnails[item.id] {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding(3)
                } else if let id = item.bundleID {
                    Image(nsImage: AppIconResolver.icon(for: id)).resizable().frame(width: 40, height: 40)
                        .opacity(item.isMinimized ? 0.5 : 1)
                }
            }
            .frame(height: 78)
            .overlay(alignment: .topTrailing) {
                Button { controller.closeWindow(item.id) } label: {
                    Image(systemName: "xmark.circle.fill").symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain).padding(3).help("Close window")
            }
            Text(verbatim: item.title.isEmpty ? item.appName : item.title)
                .font(.system(size: 11, weight: .medium)).lineLimit(1)
        }
        .padding(2)
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { controller.activate(item.id) }
    }
}

/// Emoji tab: search by name, click to copy.
private struct EmojiDrawerPane: View {
    /// SD-2: the deck's one search field filters emoji by name too.
    @Binding var query: String
    @State private var copied: String?

    var body: some View {
        VStack(spacing: 10) {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(Array(EmojiCatalog.matching(query).prefix(300)), id: \.char) { entry in
                        Text(verbatim: entry.char).font(.system(size: 24))
                            .frame(width: 40, height: 40)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(copied == entry.char ? Color.accentColor.opacity(0.3) : Color.clear))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(entry.char, forType: .string)
                                copied = entry.char
                            }
                            .help(Text(verbatim: entry.name))
                    }
                }
            }
            Text(copied == nil ? "Click an emoji to copy it" : "Copied").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(12)
    }
}
