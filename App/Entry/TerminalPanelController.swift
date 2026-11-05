import AppKit
import SwiftUI

/// The Terminal panel: a key-capable floating card above the dock. Hiding it keeps the shells running
/// (hide ≠ kill); it does not close on outside clicks or focus loss, only from the chip/widget, the chevron,
/// or ⌘W. Quitting the app ends the shells.
@MainActor
final class TerminalPanelController {
    private final class TerminalPanel: NonConstrainingPanel {
        override var canBecomeKey: Bool { true }
    }

    private var panel: NSPanel?
    private lazy var model = TerminalPanelModel()

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle() { isShown ? dismiss() : show() }

    func show() {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if !panel.isVisible {
            let f = screen.visibleFrame
            panel.setFrame(NSRect(x: f.midX - 340, y: f.minY + 80, width: 680, height: 420), display: true)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let panel = TerminalPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: true)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: TerminalPanelView(model: model) { [weak self] in self?.dismiss() })
        return panel
    }
}
