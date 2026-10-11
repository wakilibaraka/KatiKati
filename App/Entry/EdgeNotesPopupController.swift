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

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle(anchor: CGRect, side: EdgeSide, visibleFrame: CGRect, controller: NotesController) {
        if isShown { dismiss(); return }
        self.controller = controller
        controller.reload()
        let frame = PanelGeometry.edgeBarPopupFrame(side: side, anchor: anchor, size: EdgeBarLayout.notesPopupSize, visibleFrame: visibleFrame)
        let panel = self.panel ?? makePanel(frame: frame)
        self.panel = panel
        let host = NSHostingView(rootView: NotesPopupView(controller: controller, onClose: { [weak self] in self?.dismiss() }))
        let plate = NSVisualEffectView(frame: CGRect(origin: .zero, size: frame.size))
        plate.material = .hudWindow
        plate.state = .active
        plate.wantsLayer = true
        plate.layer?.cornerRadius = 14
        plate.layer?.masksToBounds = true
        host.frame = plate.bounds
        host.autoresizingMask = [.width, .height]
        plate.addSubview(host)
        panel.contentView = plate
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        installMonitor()
    }

    func dismiss() {
        controller?.flush()
        panel?.orderOut(nil)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    func tearDown() {
        dismiss()
        panel = nil
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, !panel.frame.contains(NSEvent.mouseLocation) else { return }
                self.dismiss()
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
