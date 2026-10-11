import AppKit
import SwiftUI

/// Key-capable (but non-activating) panel so the editor can take typing without stealing app focus.
private final class NotesFlyoutPanel: NonConstrainingPanel {
    override var canBecomeKey: Bool { true }
}

/// The notes flyout panel (Phase 7A-7b): placed by `PanelGeometry.edgeBarPopupFrame` next to the notes
/// tile, closed by Esc or an outside click. Closing flushes pending autosave.
@MainActor
final class EdgeNotesPopupController {
    private var panel: NSPanel?
    private var monitor: Any?
    private weak var controller: NotesController?
    private(set) var shownSelection: String?
    /// Called after the flyout closes; `outsideClick` distinguishes a click away from Esc / the close button.
    var onDismiss: ((_ outsideClick: Bool) -> Void)?

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle(anchor: CGRect, side: EdgeSide, visibleFrame: CGRect, controller: NotesController, select: String? = nil, tabFont: String = "") {
        if isShown, shownSelection == select { dismiss(); return }
        if isShown { dismiss(notify: false) }
        shownSelection = select
        self.controller = controller
        controller.reload()
        let frame = PanelGeometry.edgeBarPopupFrame(side: side, anchor: anchor, size: NoteSheetView.size, visibleFrame: visibleFrame)
        let panel = self.panel ?? makePanel(frame: frame)
        self.panel = panel
        guard let noteID = select else { return }
        let host = NSHostingView(rootView: NoteSheetView(
            controller: controller, noteID: noteID, onRight: side == .right, tabFont: tabFont,
            onClose: { [weak self] in self?.dismiss() }))
        host.frame = CGRect(origin: .zero, size: frame.size)
        panel.contentView = host
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        installMonitor()
    }

    func dismiss(notify: Bool = true, outsideClick: Bool = false) {
        let wasShown = isShown
        controller?.flush()
        panel?.orderOut(nil)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        shownSelection = nil
        if wasShown, notify { onDismiss?(outsideClick) }
    }

    func tearDown() {
        dismiss(notify: false)
        panel = nil
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, !panel.frame.contains(NSEvent.mouseLocation) else { return }
                self.dismiss(outsideClick: true)
            }
        }
    }

    private func makePanel(frame: CGRect) -> NSPanel {
        let panel = NotesFlyoutPanel(
            contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = PanelCollectionBehavior.standard
        panel.isFloatingPanel = true
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        return panel
    }
}
