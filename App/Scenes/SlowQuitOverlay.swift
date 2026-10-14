import AppKit
import SwiftUI

/// Phase 24c: the center-screen hold-to-quit panel (the SlowQuitApps technique). Non-activating,
/// ignores the mouse, joins every space including full screen, and only exists while a ⌘Q is being
/// held — release early and it disappears with the quit cancelled.
@MainActor
final class SlowQuitOverlayController {
    private var panel: NSPanel?
    private let model = SlowQuitHoldModel()

    func show(app: NSRunningApplication, progress: Double) {
        model.name = app.localizedName ?? app.bundleIdentifier ?? ""
        model.icon = app.icon
        model.progress = progress
        let panel = self.panel ?? makePanel()
        position(panel)
        panel.orderFrontRegardless()
    }

    func update(progress: Double) { model.progress = progress }

    func hide() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 96),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        let host = NSHostingView(rootView: SlowQuitHoldView(model: model))
        host.frame = NSRect(origin: .zero, size: panel.contentRect(forFrameRect: panel.frame).size)
        panel.contentView = host
        self.panel = panel
        return panel
    }

    /// Center of the screen under the pointer — the guard fires wherever the owner is working.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2,
                                     y: screen.frame.midY - size.height / 2))
    }
}

@MainActor
private final class SlowQuitHoldModel: ObservableObject {
    @Published var name = ""
    @Published var icon: NSImage?
    @Published var progress = 0.0
}

private struct SlowQuitHoldView: View {
    @ObservedObject var model: SlowQuitHoldModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                if let icon = model.icon {
                    Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit).frame(width: 28, height: 28)
                }
                Text(model.name).font(.headline).lineLimit(1).truncationMode(.tail)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.18))
                    Capsule().fill(Color.accentColor)
                        .frame(width: max(0, geo.size.width * model.progress))
                }
            }
            .frame(height: 5)
            .animation(.linear(duration: 0.05), value: model.progress)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 280)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.quaternary))
    }
}
