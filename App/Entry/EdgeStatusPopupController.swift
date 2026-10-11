import AppKit
import SwiftUI

/// Single popover panel for the status trio (Phase 7A-5): positioned by
/// `PanelGeometry.edgeBarPopupFrame`, dismissed by an outside click. One per edge bar.
@MainActor
final class EdgeStatusPopupController {
    private var panel: NSPanel?
    private(set) var shownKind: StatusKind?
    private var clickMonitors: [Any] = []

    var isShown: Bool { shownKind != nil }
    var frame: CGRect { panel?.frame ?? .zero }

    /// Toggles: tapping the open kind again closes it.
    func toggle(_ kind: StatusKind, anchor: CGRect, side: EdgeSide, visibleFrame: CGRect, service: SystemStatusService) {
        if shownKind == kind { dismiss(); return }
        let frame = PanelGeometry.edgeBarPopupFrame(side: side, anchor: anchor, size: kind.popupSize, visibleFrame: visibleFrame)
        let panel = self.panel ?? makePanel(frame: frame)
        self.panel = panel
        let host = NSHostingView(rootView: StatusPopupView(kind: kind, service: service))
        host.frame = CGRect(origin: .zero, size: frame.size)
        panel.contentView = Self.plate(wrapping: host, size: frame.size)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        shownKind = kind
        installMonitors()
    }

    func dismiss() {
        panel?.orderOut(nil)
        shownKind = nil
        removeMonitors()
    }

    func tearDown() {
        dismiss()
        panel = nil
    }

    private func installMonitors() {
        guard clickMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissIfOutside() }
        }) { clickMonitors.append(global) }
    }

    private func removeMonitors() {
        clickMonitors.forEach { NSEvent.removeMonitor($0) }
        clickMonitors = []
    }

    /// Global monitors only see clicks outside this app's windows; clicks on the bar's own
    /// panel are handled by its buttons (toggle) so we only need to close for outside clicks.
    private func dismissIfOutside() {
        guard let panel, !panel.frame.contains(NSEvent.mouseLocation) else { return }
        dismiss()
    }

    private func makePanel(frame: CGRect) -> NSPanel {
        let panel = NonConstrainingPanel(
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

    private static func plate(wrapping content: NSView, size: CGSize) -> NSView {
        let plate = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        plate.material = .hudWindow
        plate.state = .active
        plate.wantsLayer = true
        plate.layer?.cornerRadius = 14
        plate.layer?.masksToBounds = true
        content.autoresizingMask = [.width, .height]
        plate.addSubview(content)
        return plate
    }
}
