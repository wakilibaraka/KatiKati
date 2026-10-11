import AppKit
import SwiftUI

/// Single flyout panel (key only when a flyout asks, e.g. a text field) for an edge bar's tiles (status popovers, now playing, …): positioned by
/// `PanelGeometry.edgeBarPopupFrame`, dismissed by an outside click or a re-tap. One per edge bar.
/// (Generalized from the 7A-5 status-only popup controller.) Text-entry flyouts (notes) use their own
/// key-capable panel.
/// Never takes key on its own; `makeKey` is called only for flyouts that need typing.
private final class KeyableFlyoutPanel: NonConstrainingPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class EdgeFlyoutController {
    private var panel: NSPanel?
    private(set) var shownID: String?
    private var clickMonitors: [Any] = []

    var isShown: Bool { shownID != nil }
    var frame: CGRect { panel?.frame ?? .zero }

    /// Toggles: tapping the open flyout's tile again closes it; another tile swaps the content in place.
    func toggle(id: String, anchor: CGRect, side: EdgeSide, visibleFrame: CGRect, size: CGSize, content: AnyView,
                takesKey: Bool = false) {
        if shownID == id { dismiss(); return }
        let frame = PanelGeometry.edgeBarPopupFrame(side: side, anchor: anchor, size: size, visibleFrame: visibleFrame)
        let panel = self.panel ?? makePanel(frame: frame)
        self.panel = panel
        let host = NSHostingView(rootView: content)
        host.frame = CGRect(origin: .zero, size: frame.size)
        panel.contentView = Self.plate(wrapping: host, size: frame.size)
        panel.setFrame(frame, display: true)
        if takesKey { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
        shownID = id
        installMonitors()
    }

    func dismiss() {
        panel?.orderOut(nil)
        shownID = nil
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
        let panel = KeyableFlyoutPanel(
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
