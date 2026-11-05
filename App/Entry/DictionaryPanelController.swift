import AppKit
import SwiftUI

/// The Dictionary panel: a floating glass card above the dock. Key-capable (it has a text field), closes on
/// Esc, on losing key, or from the chevron. Opened by the dock chip / widget, or with a word via `show(word:)`.
@MainActor
final class DictionaryPanelController {
    private final class DictionaryPanel: NonConstrainingPanel {
        override var canBecomeKey: Bool { true }
        override func cancelOperation(_ sender: Any?) { orderOut(nil) }
    }

    private var panel: NSPanel?
    private let model = DictionaryPanelModel()
    private var resignObserver: NSObjectProtocol?

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle() { isShown ? dismiss() : show(word: nil) }

    func show(word: String?) {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let word { model.lookup(word) }
        let size = panel.contentView?.fittingSize ?? NSSize(width: 460, height: 520)
        let f = screen.visibleFrame
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.minY + 80, width: size.width, height: size.height), display: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let panel = DictionaryPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: DictionaryPanelView(model: model) { [weak self] in self?.dismiss() })
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
        return panel
    }
}
