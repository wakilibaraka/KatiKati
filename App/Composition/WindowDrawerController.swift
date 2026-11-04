import AppKit
import Carbon.HIToolbox
import Combine
import OSLog
import SwiftUI

/// Edge drawer: a left icon rail (Windows, Layouts, Clipboard, plus shortcuts to the existing Search and Apps
/// panels) over a content pane. Windows tab = searchable thumbnail grid. Opened with ⌃⌥W on the display under
/// the cursor; Esc or a click outside closes it.
// shortcut: hotkey only; edge-hover opening comes later if wanted.
@MainActor
final class WindowDrawerController: ObservableObject {
    enum Tab: String { case windows, layouts, clipboard }

    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        let appName: String
        let bundleID: String?
        let cgWindowID: CGWindowID?
        let isMinimized: Bool
    }

    @Published var tab: Tab = .windows
    @Published var query = ""
    @Published private(set) var items: [Item] = []
    @Published private(set) var thumbnails: [String: NSImage] = [:]

    private let runtime: AppRuntime
    private let onSearch: () -> Void
    private let onApps: () -> Void
    private var hotKey: GlobalHotKeyMonitor?
    private var panel: DrawerPanel?
    private var clickMonitor: Any?
    private let log = Logger(subsystem: "com.caye.macosdockcc.v2", category: "drawer")

    init(runtime: AppRuntime, onSearch: @escaping () -> Void, onApps: @escaping () -> Void) {
        self.runtime = runtime; self.onSearch = onSearch; self.onApps = onApps
    }

    func start() {
        let shortcut = GlobalHotKeyShortcut(keyCode: UInt32(kVK_ANSI_W), carbonModifiers: UInt32(controlKey | optionKey),
                                            displayGlyphs: "⌃⌥W", signature: 0x5467_4567, id: 22)
        let monitor = GlobalHotKeyMonitor(shortcut: shortcut) { [weak self] in self?.toggle() }
        let status = monitor.start()
        if status == .registered { hotKey = monitor } else {
            log.warning("Drawer ⌃⌥W not registered: \(String(describing: status), privacy: .public)")
        }
    }

    func toggle() { panel == nil ? open() : close() }

    func select(_ tab: Tab) { self.tab = tab }

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
                guard let self, let panel = self.panel, !panel.frame.contains(NSEvent.mouseLocation) else { return }
                self.close()
            }
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
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider()
            Group {
                switch controller.tab {
                case .windows: windows
                case .layouts:
                    VStack(spacing: 8) {
                        WindowsFlyoutView()
                        Text("Drag a window onto a layout slot").font(.system(size: 11)).foregroundStyle(.secondary)
                        dragRow
                        Spacer(minLength: 0)
                    }
                case .clipboard: ClipboardFlyoutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var rail: some View {
        VStack(spacing: 6) {
            railButton("magnifyingglass", "Search", selected: false) { controller.runSearch() }
            railButton("macwindow.on.rectangle", "Windows", selected: controller.tab == .windows) { controller.select(.windows) }
            railButton("square.grid.2x2", "Apps", selected: false) { controller.runApps() }
            railButton("rectangle.split.3x1", "Layouts", selected: controller.tab == .layouts) { controller.select(.layouts) }
            railButton("doc.on.clipboard", "Clipboard", selected: controller.tab == .clipboard) { controller.select(.clipboard) }
            Spacer()
        }
        .padding(8)
        .frame(width: 52)
    }

    private func railButton(_ symbol: String, _ title: LocalizedStringKey, selected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16))
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.28) : Color.clear))
        }
        .buttonStyle(.plain).help(title)
    }

    private var windows: some View {
        VStack(spacing: 10) {
            TextField("Search windows", text: $controller.query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onAppear { searchFocused = true }
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(controller.filtered) { item in card(item) }
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

    private func card(_ item: WindowDrawerController.Item) -> some View {
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
        .contentShape(Rectangle())
        .onTapGesture { controller.activate(item.id) }
    }
}
