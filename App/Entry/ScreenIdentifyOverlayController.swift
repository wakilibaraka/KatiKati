import AppKit
import SwiftUI

/// Flashes a large screen number on every display so the Displays page can name them.
@MainActor
final class ScreenIdentifyOverlayController {
    static let shared = ScreenIdentifyOverlayController()

    private var panels: [NSPanel] = []
    private var dismissWork: DispatchWorkItem?

    private init() {}

    func present(duration: TimeInterval = 1.8) {
        dismiss()
        let screens = NSScreen.screens
        for (index, screen) in screens.enumerated() {
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: ScreenIdentifyBadge(
                number: index + 1,
                title: screen.localizedName
            ))
            panel.setFrame(screen.frame, display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            panel.animator().alphaValue = 1
            panels.append(panel)
        }

        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func dismiss() {
        dismissWork?.cancel()
        dismissWork = nil
        for panel in panels {
            panel.animator().alphaValue = 0
            panel.orderOut(nil)
        }
        panels.removeAll()
    }
}

private struct ScreenIdentifyBadge: View {
    let number: Int
    let title: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
            VStack(spacing: 10) {
                Text(verbatim: "\(number)")
                    .font(.system(size: 180, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 12)
                Text(verbatim: title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(48)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        }
        .ignoresSafeArea()
    }
}
