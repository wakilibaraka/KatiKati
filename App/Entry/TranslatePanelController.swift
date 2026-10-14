import AppKit
import SwiftUI

/// Phase 23d: shows the define/translate card for the current selection, near the pointer. Non-activating;
/// Esc or a click outside closes it. Reads the selection once, at summon.
@MainActor
final class TranslatePanelController {
    private final class TranslatePanel: NonConstrainingPanel {
        override var canBecomeKey: Bool { false }
        override func cancelOperation(_ sender: Any?) { orderOut(nil) }
    }

    private var panel: NSPanel?
    private var outsideMonitor: Any?

    var isShown: Bool { panel?.isVisible ?? false }

    /// Reads the frontmost app's selection and shows the card; hides it when nothing is selected.
    func toggleSelection() {
        guard let text = SelectedTextReader.selectedText() else { dismiss(); return }
        show(request: TranslateRequest.detect(text))
    }

    func show(request: TranslateRequest) {
        guard !request.text.isEmpty else { return }
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        let dictionary = DictionaryCardModel.parse(headword: request.text, payload: DictionaryService.define(request.text))
        let host = NSHostingView(rootView: TranslateCardView(request: request, dictionary: dictionary))
        let size = host.fittingSize
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = host
        let mouse = NSEvent.mouseLocation
        let f = screen.visibleFrame
        let x = min(max(mouse.x - size.width / 2, f.minX + 8), f.maxX - size.width - 8)
        let y = max(mouse.y - size.height - 12, f.minY + 8)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        installOutsideMonitor()
    }

    func dismiss() {
        panel?.orderOut(nil)
        removeOutsideMonitor()
    }

    private func makePanel() -> NSPanel {
        let panel = TranslatePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }

    private func installOutsideMonitor() {
        guard outsideMonitor == nil else { return }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func removeOutsideMonitor() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        outsideMonitor = nil
    }
}
