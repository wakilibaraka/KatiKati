import AppKit
import Combine
import SwiftUI

/// Always-visible window strip: a narrow icon column pinned to the left edge of the primary display. Click an
/// icon to bring that window forward. While it is on, auto-tiling keeps its windows clear of the strip.
// shortcut: primary display and left edge only; other edges/displays when someone asks.
@MainActor
final class WindowStripController: ObservableObject {
    static let enabledKey = WindowStripReserve.enabledKey
    static let width = WindowStripReserve.width

    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        let bundleID: String?
        let isActive: Bool
    }

    @Published private(set) var items: [Item] = []

    private let runtime: AppRuntime
    private var panel: NSPanel?
    private var sinks: [AnyCancellable] = []
    private var defaultsObserver: NSObjectProtocol?

    init(runtime: AppRuntime) { self.runtime = runtime }

    func start() {
        sinks.append(runtime.$snapshot.sink { [weak self] in self?.update($0) })
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.apply() }
        }
        apply()
    }

    func activate(_ id: String) { runtime.activate(windowID: id) }

    private func update(_ snapshot: DockSnapshot) {
        let next = snapshot.orderedWindowIDs.compactMap { id -> Item? in
            guard let w = snapshot.windows[id] else { return nil }
            switch w.status {
            case .closedPending, .disappeared: return nil
            default: break
            }
            return Item(id: id.rawValue, title: w.title, bundleID: w.bundleIdentifier, isActive: w.status == .active)
        }
        if next != items { items = next }
    }

    private func apply() {
        let on = UserDefaults.standard.bool(forKey: Self.enabledKey)
        if !on {
            guard panel != nil else { return }
            panel?.orderOut(nil); panel = nil
            TilingEngine.shared.reapplyForWorkAreaChange()
            return
        }
        guard let screen = NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        let frame = NSRect(x: area.minX, y: area.minY, width: Self.width, height: area.height)
        if let panel { panel.setFrame(frame, display: true); return }
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = PanelCollectionBehavior.standard
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: WindowStripView(controller: self))
        panel.orderFrontRegardless()
        self.panel = panel
        TilingEngine.shared.reapplyForWorkAreaChange()
    }
}

private struct WindowStripView: View {
    @ObservedObject var controller: WindowStripController

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(controller.items) { item in
                    Button { controller.activate(item.id) } label: {
                        Group {
                            if let id = item.bundleID {
                                Image(nsImage: AppIconResolver.icon(for: id)).resizable()
                            } else {
                                Image(systemName: "macwindow").resizable().scaledToFit()
                            }
                        }
                        .frame(width: 30, height: 30)
                        .padding(5)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(item.isActive ? Color.accentColor.opacity(0.3) : Color.clear))
                    }
                    .buttonStyle(.plain)
                    .help(Text(verbatim: item.title))
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}
