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

    private let runtime: AppRuntime
    private let onSearch: () -> Void
    private let onApps: () -> Void
    private var panel: DrawerPanel?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var edgeTimer: Timer?
    private var edgeSince: Date?
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

    private func applyEdgeHover() {
        let on = UserDefaults.standard.bool(forKey: Self.edgeHoverKey)
        if on, edgeTimer == nil {
            edgeTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.pollEdge() }
            }
        } else if !on {
            edgeTimer?.invalidate(); edgeTimer = nil; edgeSince = nil
        }
    }

    /// Opens after the pointer has rested on a display's left edge for 0.4 s.
    private func pollEdge() {
        let mouse = NSEvent.mouseLocation
        let atEdge = panel == nil && NSScreen.screens.contains { $0.frame.contains(mouse) && mouse.x <= $0.frame.minX + 2 }
        guard atEdge else { edgeSince = nil; return }
        if let since = edgeSince {
            if Date().timeIntervalSince(since) >= 0.4 { edgeSince = nil; open() }
        } else {
            edgeSince = Date()
        }
    }

    func toggle() { panel == nil ? open() : close() }

    /// Gesture entry point: reveals the Windows section, opening the drawer when it is closed.
    func showWindows() {
        select(.windows)
        if panel == nil { open() }
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
    }

    var isPinnedOpen: Bool { UserDefaults.standard.bool(forKey: SideDeckPrefs.pinKey) }

    // MARK: - Keyboard (SD-2)

    func moveSelection(_ delta: Int) {
        switch tab {
        case .windows: windowSelection.move(by: delta, count: filtered.count)
        case .notifications: notificationSelection.move(by: delta, count: visibleNotifications.count)
        case .downloads, .storage, .weather, .quickAccess, .aiMissionControl, .layouts, .emoji, .clipboard, .tendedero, .scratchpad, .markets: break
        }
    }

    func activateSelection() {
        switch tab {
        case .windows: if let item = selectedWindow { activate(item.id) }
        case .notifications: if let entry = selectedNotification { openNotification(entry) }
        case .downloads, .storage, .weather, .quickAccess, .aiMissionControl, .layouts, .emoji, .clipboard, .tendedero, .scratchpad, .markets: break
        }
    }

    func dismissSelection() {
        switch tab {
        case .windows: if let id = selectedWindow?.id { closeWindow(id) }
        case .notifications: if let entry = selectedNotification { dismissNotification(entry) }
        case .downloads, .storage, .weather, .quickAccess, .aiMissionControl, .layouts, .emoji, .clipboard, .tendedero, .scratchpad, .markets: break
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
        let frame = NSRect(x: area.minX + 8, y: area.minY + 8, width: 400, height: area.height - 16)
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
    @FocusState private var searchFocused: Bool

    private var density: WidgetHUDDensityMode { WidgetHUDDensityMode.parse(densityRaw) }
    private var textScale: WidgetTextScale { WidgetTextScale.parse(textScaleRaw) }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if density.isCompact {
                compactStrip
            } else {
                HStack(spacing: 0) {
                    rail
                    Divider()
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear {
            searchFocused = true
            syncMonitorHold()
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
        case .storage: SideDeckStorageView()
        case .weather: SideDeckWeatherView()
        case .aiMissionControl: SideDeckAIMissionControlView()
        case .quickAccess:
            SideDeckQuickAccessView(onLauncher: controller.runApps, onCommandBar: controller.runSearch)
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

    private var rail: some View {
        VStack(spacing: 6) {
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
        }
        .padding(8)
        .frame(width: 52)
    }

    private var windows: some View {
        VStack(spacing: 10) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
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
