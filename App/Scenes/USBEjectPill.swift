import AppKit
import SwiftUI

// Phase 36c — the "eject" pill: a small clickable panel under the top edge when an external drive mounts.
// It is its own panel (not a toast) because toasts are click-through. Dismisses itself after 8 s.

@MainActor
final class USBEjectPillController {
    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?

    func show(volumeURL: URL, name: String) {
        hide()
        let model = USBEjectPillModel(name: name, url: volumeURL) { [weak self] in self?.hide() }
        let host = NSHostingView(rootView: USBEjectPillView(model: model))
        host.setFrameSize(host.fittingSize)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        if let screen = NSScreen.main {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 8))
        }
        panel.orderFrontRegardless()
        self.panel = panel
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    func hide() {
        dismissWork?.cancel(); dismissWork = nil
        panel?.orderOut(nil); panel = nil
    }
}

@MainActor
final class USBEjectPillModel: ObservableObject {
    enum State { case ready, ejected, failed }
    @Published var state = State.ready
    let name: String
    private let url: URL
    private let close: () -> Void

    init(name: String, url: URL, close: @escaping () -> Void) { self.name = name; self.url = url; self.close = close }

    func eject() {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: url)
            state = .ejected
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [close] in close() }
        } catch {
            state = .failed
        }
    }

    func dismiss() { close() }
}

struct USBEjectPillView: View {
    @ObservedObject var model: USBEjectPillModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.fill").foregroundColor(.white.opacity(0.9))
            Text(verbatim: model.name).font(.system(size: 12, weight: .semibold)).foregroundColor(.white).lineLimit(1).frame(maxWidth: 160, alignment: .leading)
            switch model.state {
            case .ready:
                Button("Eject") { model.eject() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.9)))
                    .foregroundColor(.black)
            case .ejected:
                Text("Ejected").font(.system(size: 12, weight: .semibold)).foregroundColor(.green)
            case .failed:
                Text("Couldn't Eject").font(.system(size: 12, weight: .semibold)).foregroundColor(.orange)
            }
            Button { model.dismiss() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(.plain).foregroundColor(.white.opacity(0.6))
                .accessibilityLabel(Text("Close"))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(0.92)))
        .padding(4)
    }
}
