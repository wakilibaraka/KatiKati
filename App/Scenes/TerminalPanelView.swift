import AppKit
import SwiftTerm
import SwiftUI

/// Tabs (the pure `TerminalTabs` model) plus the live sessions behind them.
@MainActor
final class TerminalPanelModel: ObservableObject {
    @Published private(set) var tabs: TerminalTabs
    private var sessions: [UUID: TerminalSession] = [:]

    init() {
        let first = TerminalTabs.Tab(id: UUID(), title: "", directory: NSHomeDirectory())
        tabs = TerminalTabs(first: first)
        attach(first.id, directory: first.directory)
    }

    var selectedSession: TerminalSession? { sessions[tabs.selectedID] }

    func newTab() {
        guard let tab = tabs.add() else { return }
        attach(tab.id, directory: tab.directory)
    }

    func close(_ id: UUID) {
        if tabs.close(id) {
            sessions.removeValue(forKey: id)?.terminate()
        } else if tabs.tabs.count == 1, tabs.tabs[0].id == id {
            // The last shell ended: start a fresh one instead of showing a dead view.
            sessions.removeValue(forKey: id)?.terminate()
            attach(id, directory: NSHomeDirectory())
        }
    }

    func select(_ id: UUID) { tabs.select(id) }

    private func attach(_ id: UUID, directory: String?) {
        let session = TerminalSession(id: id, directory: directory)
        session.onTitle = { [weak self] id, title in self?.tabs.setTitle(title, for: id) }
        session.onDirectory = { [weak self] id, dir in self?.tabs.setDirectory(dir, for: id) }
        session.onExit = { [weak self] id in self?.close(id) }
        sessions[id] = session
    }
}

/// Hosts the selected session's SwiftTerm view; switching tabs swaps the subview.
private struct TerminalHost: NSViewRepresentable {
    let session: TerminalSession?

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ container: NSView, context: Context) {
        guard let view = session?.view else { container.subviews.forEach { $0.removeFromSuperview() }; return }
        if view.superview !== container {
            container.subviews.forEach { $0.removeFromSuperview() }
            view.frame = container.bounds
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
        }
        DispatchQueue.main.async { container.window?.makeFirstResponder(view) }
    }
}

struct TerminalPanelView: View {
    @ObservedObject var model: TerminalPanelModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Divider().opacity(0.4)
            TerminalHost(session: model.selectedSession).frame(minHeight: 300)
        }
        .frame(width: 680, height: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
    }

    private var tabStrip: some View {
        HStack(spacing: 6) {
            ForEach(model.tabs.tabs) { tab in
                HStack(spacing: 4) {
                    Text(verbatim: tab.displayTitle).lineLimit(1).font(.system(size: 12))
                    if model.tabs.tabs.count > 1 {
                        Button { model.close(tab.id) } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(tab.id == model.tabs.selectedID ? 0.18 : 0.06)))
                .onTapGesture { model.select(tab.id) }
            }
            if model.tabs.canAdd {
                Button { model.newTab() } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("New Tab"))
            }
            Spacer()
            Button(action: onClose) { Image(systemName: "chevron.down") }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Hide Terminal"))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }
}
