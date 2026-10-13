import AppKit
import SwiftUI

/// Single flyout panel (key only when a flyout asks, e.g. a text field) for an edge bar's tiles (status popovers, now playing, …): positioned by
/// `PanelGeometry.edgeBarPopupFrame`, dismissed by an outside click or a re-tap. One per edge bar.
/// (Generalized from the 7A-5 status-only popup controller.) Text-entry flyouts (notes) use their own
/// key-capable panel.
/// Never takes key on its own; `makeKey` is called only for flyouts that need typing.
private final class KeyableFlyoutPanel: NonConstrainingPanel {
    override var canBecomeKey: Bool { true }
    /// Set by panels that want Esc to dismiss (the Control Center); nil leaves Esc inert.
    var onEscape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

@MainActor
final class EdgeFlyoutController {
    private var panel: NSPanel?
    private(set) var shownID: String?
    private var clickMonitors: [Any] = []
    /// 13l: the plate behind the flyout (read each time a flyout opens).
    var style: EdgeFlyoutStyle = .modern

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
        panel.contentView = Self.plate(wrapping: host, size: frame.size, style: style)
        panel.setFrame(frame, display: true)
        if takesKey { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
        shownID = id
        installMonitors()
    }

    func dismiss() {
        panel?.orderOut(nil)
        // Drop the content so its views disappear (samplers such as the System monitor stop with them).
        panel?.contentView = nil
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

    static func plate(wrapping content: NSView, size: CGSize, style: EdgeFlyoutStyle) -> NSView {
        let plate = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        plate.state = .active
        plate.wantsLayer = true
        switch style {
        case .glass:
            plate.material = .hudWindow
            plate.layer?.cornerRadius = 14
        case .modern:
            // Adaptive, near-opaque surface with a crisp hairline and a larger radius (the system adds the soft shadow).
            plate.material = .popover
            plate.blendingMode = .withinWindow
            plate.layer?.cornerRadius = 20
            plate.layer?.borderWidth = 1
            plate.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        }
        plate.layer?.masksToBounds = true
        content.autoresizingMask = [.width, .height]
        plate.addSubview(content)
        return plate
    }
}

/// Phase 16g: the Control Center — a side panel that hugs the screen edge where the dock/deck is. Never
/// full-screen: width ~360, height capped and scrollable. Which edge is a setting
/// (`com.katikati.controlcenter.side`, default right). Dismissed by re-toggle, Esc, or an outside click.
/// The iPad-style content lands in 16h; this slice ships the shell (the existing switch grid).
@MainActor
final class ControlCenterPanelController {
    static let sideKey = "com.katikati.controlcenter.side"
    static let width: CGFloat = 360

    private var panel: KeyableFlyoutPanel?
    private var outsideMonitor: Any?

    /// Which edge the panel hugs; read each time it opens so a Settings change applies immediately.
    var side: () -> EdgeSide = {
        let raw = UserDefaults.standard.string(forKey: ControlCenterPanelController.sideKey) ?? ""
        return EdgeSide(rawValue: raw) ?? .right
    }
    var toggleOrder: () -> [QuickToggleID] = { QuickToggleID.defaultOrder }
    /// Phase 16m: user widgets hosted in the panel (the six ported tiles, all on).
    var widgets: () -> [TileKind] = { [.calculator, .screenTime, .network, .battery, .topApps, .batteries] }
    /// Bottom-row actions (wired by `AppDelegate`).
    var onSettings: () -> Void = {}
    var onLauncher: () -> Void = {}
    var onCapture: () -> Void = {}
    var onDrawer: () -> Void = {}
    var onQuit: () -> Void = {}

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle() { isShown ? hide() : show() }

    func show() {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
                ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let size = panelSize(on: screen)
        let frame = panelFrame(on: screen, size: size)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let hosting = NSHostingView(rootView: AnyView(ControlCenterView(
            engine: .shared, order: toggleOrder(),
            widgetTiles: widgets(),
            onSettings: onSettings, onLauncher: onLauncher, onCapture: onCapture,
            onDrawer: onDrawer, onQuit: onQuit)))
        hosting.frame = CGRect(origin: .zero, size: size)
        panel.contentView = EdgeFlyoutController.plate(wrapping: hosting, size: size, style: .modern)
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        installOutsideMonitor()
    }

    func hide() {
        panel?.orderOut(nil)
        // Drop the content so hidden samplers (system monitor, etc.) stop with the view tree.
        panel?.contentView = nil
        removeOutsideMonitor()
    }

    func tearDown() { hide(); panel = nil }

    // MARK: Geometry

    private func panelSize(on screen: NSScreen) -> CGSize {
        let height = min(660, screen.visibleFrame.height - 24)
        return CGSize(width: Self.width, height: max(240, height))
    }

    /// Flush to the dock's side, top-aligned under the menu bar, stepped inward past a rail on that edge.
    private func panelFrame(on screen: NSScreen, size: CGSize) -> CGRect {
        PanelGeometry.controlCenterFrame(side: side(), visibleFrame: screen.visibleFrame, size: size, railInset: railInset())
    }

    /// Room to leave for a KatiKati side rail when the strip sits on the Control Center's edge.
    private func railInset() -> CGFloat {
        let defaults = UserDefaults.standard
        let map = StripPlacementMap.decode(defaults.data(forKey: StripPlacementMap.defaultsKey)) ?? StripPlacementMap()
        guard map.global != .bottom, map.global.rawValue == side().rawValue else { return 0 }
        let stored = defaults.object(forKey: "com.katikati.dockPanelHeight") as? NSNumber
        let thickness = stored.map { DockPanelHeight(clamping: CGFloat($0.doubleValue)) }?.points ?? DockPanelHeight.native.points
        return thickness + 8
    }

    // MARK: Panel + dismissal

    private func makePanel() -> KeyableFlyoutPanel {
        let p = KeyableFlyoutPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.collectionBehavior = PanelCollectionBehavior.standard
        p.isFloatingPanel = true
        p.isMovable = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.onEscape = { [weak self] in self?.hide() }
        return p
    }

    private func installOutsideMonitor() {
        guard outsideMonitor == nil else { return }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, !panel.frame.contains(NSEvent.mouseLocation) else { return }
                self.hide()
            }
        }
    }

    private func removeOutsideMonitor() {
        if let m = outsideMonitor { NSEvent.removeMonitor(m); outsideMonitor = nil }
    }
}
