import AppKit
import AVFoundation
import Carbon.HIToolbox
import SwiftUI

/// Phase 23d / Slice 2.2: shows the selection action pill and define/translate card for current selection.
@MainActor
final class TranslatePanelController {
    private final class TranslatePanel: NonConstrainingPanel {
        override var canBecomeKey: Bool { false }
        override func cancelOperation(_ sender: Any?) { orderOut(nil) }
    }

    private var panel: NSPanel?
    private var outsideMonitor: Any?
    private let speechSynthesizer = AVSpeechSynthesizer()

    var isShown: Bool { panel?.isVisible ?? false }

    /// Reads the frontmost app's selection and shows the pill; gates by DropClipPolicy.
    func toggleSelection() {
        guard DropClipPolicy.isEnabled(),
              let text = SelectedTextReader.selectedText() else { dismiss(); return }
        let originID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard DropClipPolicy.shouldPresent(
            text: text,
            originBundleID: originID,
            isSecureInput: IsSecureEventInputEnabled(),
            isEnabled: DropClipPolicy.isEnabled()
        ) else {
            dismiss()
            return
        }
        show(request: TranslateRequest.detect(text))
    }

    func show(request: TranslateRequest) {
        guard !request.text.isEmpty else { return }
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        let dictionary = DictionaryCardModel.parse(headword: request.text, payload: DictionaryService.define(request.text))
        let actions = DropClipPolicy.actions(for: request.text)
        let host = NSHostingView(rootView: SelectionPillContainerView(
            request: request,
            dictionary: dictionary,
            actions: actions,
            onAction: { [weak self] action in self?.performAction(action, text: request.text) }
        ))
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

    private func performAction(_ action: SelectionAction, text: String) {
        switch action {
        case .copy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            dismiss()
        case .cut, .paste:
            dismiss()
        case .search:
            dismiss()
            if let url = URL(string: "https://duckduckgo.com/?q=" + (text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) {
                NSWorkspace.shared.open(url)
            }
        case .translate:
            break
        case .speak:
            dismiss()
            if speechSynthesizer.isSpeaking {
                speechSynthesizer.stopSpeaking(at: .immediate)
            }
            let utterance = AVSpeechUtterance(string: text)
            speechSynthesizer.speak(utterance)
        case .quickFix:
            let fixed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(fixed, forType: .string)
            dismiss()
        case .ai:
            dismiss()
            AppDelegate.shared?.toggleCommandBar()
        }
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
