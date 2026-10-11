import AppKit
import SwiftUI

/// A small centred confirmation ("Keep Awake On") for actions fired from a shortcut, which otherwise give no sign
/// they ran. Click-through, non-activating, gone after about a second.
@MainActor
final class ShortcutToastPresenter {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ message: String, symbol: String) {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        let host = NSHostingView(rootView: ToastView(message: message, symbol: symbol))
        let size = host.fittingSize
        let panel = self.panel ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            p.level = .statusBar
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.isReleasedWhenClosed = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            return p
        }()
        self.panel = panel
        panel.contentView = host
        let f = screen.visibleFrame
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.minY + f.height * 0.18, width: size.width, height: size.height), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak panel] in
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel?.animator().alphaValue = 0 }, completionHandler: { panel?.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }
}

private struct ToastView: View {
    let message: String
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
            Text(verbatim: message).font(.system(size: 14, weight: .semibold))
        }
        .padding(.horizontal, 18).padding(.vertical, 11)
        .foregroundColor(.white)
        .background(Capsule().fill(Color.black.opacity(0.78)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        .padding(12)
    }
}
