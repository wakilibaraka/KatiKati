import AppKit
import SwiftUI

/// Phase 24c: the center-screen hold-to-quit panel (the SlowQuitApps technique). Non-activating,
/// ignores the mouse, joins every space including full screen, and only exists while a ⌘Q is being
/// held — release early and it disappears with the quit cancelled.
@MainActor
final class SlowQuitOverlayController {
    private var panel: NSPanel?
    private let model = SlowQuitHoldModel()

    func show(app: NSRunningApplication, progress: Double, style: SlowQuitOverlayStyle = .ring, mode: SlowQuitMode = .hold) {
        model.name = app.localizedName ?? app.bundleIdentifier ?? ""
        model.icon = app.icon
        model.progress = progress
        model.style = style
        model.mode = mode
        let panel = self.panel ?? makePanel()
        if let fitting = panel.contentView?.fittingSize, fitting.width > 0, fitting.height > 0 {
            panel.setContentSize(fitting)
        }
        position(panel)
        panel.orderFrontRegardless()
    }

    func update(progress: Double) { model.progress = progress }

    func hide() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 148),
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
    @Published var style: SlowQuitOverlayStyle = .ring
    @Published var mode: SlowQuitMode = .hold
}

private struct SlowQuitHoldView: View {
    @ObservedObject var model: SlowQuitHoldModel

    var body: some View {
        Group {
            switch model.style {
            case .ring:
                ringBody
            case .bar:
                barBody
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.quaternary))
    }

    private var ringBody: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.14), lineWidth: 4.5)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(model.progress, 0), 1)))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.05), value: model.progress)
                if let icon = model.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                }
            }
            .frame(width: 68, height: 68)

            VStack(spacing: 2) {
                Text(model.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(hintText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 220)
    }

    private var barBody: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if let icon = model.icon {
                    Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit).frame(width: 28, height: 28)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.name).font(.headline).lineLimit(1).truncationMode(.tail)
                    Text(hintText).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
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
    }

    private var hintText: String {
        switch model.mode {
        case .hold:
            return String(localized: "Hold ⌘Q to quit · Esc to cancel")
        case .doubleTap:
            return String(localized: "Press ⌘Q again to quit")
        }
    }
}
