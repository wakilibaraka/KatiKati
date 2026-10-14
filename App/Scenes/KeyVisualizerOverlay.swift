import AppKit
import SwiftUI

/// Phase 24d: the key visualizer overlay (the KeyCastr technique). A small floating strip that shows the
/// keys the owner is pressing, so a screen recording or a support call can follow along. Off by default,
/// needs Input Monitoring, and it never logs or persists a key — the strip only ever holds the last few
/// keycaps in memory and clears itself the moment typing stops.
@MainActor
final class KeyVisualizerController {
    private var panel: NSPanel?
    private let model = KeyVisualizerModel()

    /// Ordered oldest → newest, matching `KeyVisualizerBuffer.items`. Empty hides the strip.
    func show(_ symbols: [String]) {
        model.symbols = symbols
        guard !symbols.isEmpty else {
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        position(panel)
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 56),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        let host = NSHostingView(rootView: KeyVisualizerView(model: model))
        host.frame = NSRect(origin: .zero, size: panel.contentRect(forFrameRect: panel.frame).size)
        panel.contentView = host
        self.panel = panel
        return panel
    }

    /// Bottom-center of the screen under the pointer, clear of the dock.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2,
                                     y: screen.frame.minY + 120))
    }
}

@MainActor
private final class KeyVisualizerModel: ObservableObject {
    @Published var symbols: [String] = []
}

private struct KeyVisualizerView: View {
    @ObservedObject var model: KeyVisualizerModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.symbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().strokeBorder(.quaternary))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.12), value: model.symbols)
    }
}
