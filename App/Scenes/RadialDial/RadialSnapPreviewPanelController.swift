import AppKit
import SwiftUI
import QuartzCore

/// Manages a non-activating, translucent screen overlay that previews window snap zones (Phase 31c).
@MainActor
final class RadialSnapPreviewPanelController {
    static let shared = RadialSnapPreviewPanelController()

    private var panel: NSPanel?
    private var currentPosition: SnapPosition?

    private struct PreviewView: View {
        let theme: RadialDialTheme

        var body: some View {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(fillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(strokeColor, lineWidth: 2)
                )
                .padding(6)
        }

        private var fillColor: Color {
            switch theme {
            case .lilacGlass:
                return Color(red: 0.55, green: 0.45, blue: 0.95).opacity(0.24)
            case .darkObsidian:
                return Color.white.opacity(0.18)
            case .systemFrosted:
                return Color.accentColor.opacity(0.22)
            case .neonCyber:
                return Color(red: 0.0, green: 0.85, blue: 0.95).opacity(0.22)
            }
        }

        private var strokeColor: Color {
            switch theme {
            case .lilacGlass:
                return Color(red: 0.65, green: 0.55, blue: 0.95).opacity(0.75)
            case .darkObsidian:
                return Color.white.opacity(0.5)
            case .systemFrosted:
                return Color.accentColor.opacity(0.8)
            case .neonCyber:
                return Color(red: 0.0, green: 0.95, blue: 0.95).opacity(0.9)
            }
        }
    }

    /// Displays or updates the snap zone preview on screen.
    func showPreview(for position: SnapPosition, on screen: NSScreen, theme: RadialDialTheme) {
        let targetFrame = position.frame(in: screen.visibleFrame)
        let panel = self.panel ?? makePanel(theme: theme)
        self.panel = panel

        if currentPosition == position && panel.isVisible {
            return
        }
        currentPosition = position

        let host = NSHostingView(rootView: PreviewView(theme: theme))
        panel.contentView = host

        if !panel.isVisible {
            panel.setFrame(targetFrame, display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1.0
            }
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        }
    }

    /// Hides and orders out the preview overlay.
    func hidePreview() {
        guard let panel, panel.isVisible else { return }
        currentPosition = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        })
    }

    private func makePanel(theme: RadialDialTheme) -> NSPanel {
        let panel = NonConstrainingPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }
}
