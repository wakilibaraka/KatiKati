import AppKit
import SwiftUI

private final class DesktopSearchPanel: NonConstrainingPanel {
    override var canBecomeKey: Bool { true }
}

/// Hosts the unified desktop search results (Phase 66A–B) and opens from the Search pill.
@MainActor
final class DesktopSearchPanelController {
    static let shared = DesktopSearchPanelController()

    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var outsideMonitor: Any?

    private init() {}

    var isShown: Bool { panel?.isVisible ?? false }

    func present(query: String = "") {
        DesktopSearchService.shared.start()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main
        let size = NSSize(width: 760, height: 500)
        if let visible = screen?.visibleFrame {
            panel.setFrame(
                NSRect(
                    x: visible.midX - size.width / 2,
                    y: visible.maxY - size.height - visible.height * 0.10,
                    width: size.width,
                    height: size.height
                ),
                display: true
            )
        }
        panel.makeKeyAndOrderFront(nil)
        DesktopSearchService.shared.setQuery(query, immediate: true)
        if !query.isEmpty { DesktopSearchService.shared.submit() }
        installKeyMonitor()
        installOutsideMonitor()
    }

    func dismiss() {
        panel?.orderOut(nil)
        DesktopSearchService.shared.clearSelection()
        removeMonitors()
    }

    private func makePanel() -> NSPanel {
        let panel = DesktopSearchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: DesktopSearchPanelView(
            service: DesktopSearchService.shared,
            onDismiss: { [weak self] in self?.dismiss() }
        ))
        return panel
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isShown else { return event }
            if event.keyCode == 53 {
                self.dismiss()
                return nil
            }
            return event
        }
    }

    private func installOutsideMonitor() {
        guard outsideMonitor == nil else { return }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        keyMonitor = nil
        outsideMonitor = nil
    }
}
