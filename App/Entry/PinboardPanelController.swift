import AppKit
import SwiftUI

private final class PinboardPanel: NonConstrainingPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// The Pinboard (Phase 7B): a full-screen widget wall by default (iPad-style, owner 2026-10-12 —
/// the blurred-desktop backdrop reused from the launcher with the coloured card grid centered on it),
/// or the floating draggable glass panel (Phase 7B-V1) when `style` returns `.floating`.
/// Created on first use; its content is torn down on close so no widget timer runs while hidden.
@MainActor
final class PinboardPanelController {
    private var panel: PinboardPanel?
    private var host: NSHostingView<AnyView>?
    private var outsideMonitor: Any?
    private let toggles = QuickToggleEngine.shared
    private let defaults = UserDefaults.standard
    private let originKey = "com.katikati.pinboard.origin"

    var weather: () -> WeatherService? = { nil }
    var widgets: () -> [PinboardWidget] = { PinboardWidget.defaultOrder }
    var toggleOrder: () -> [QuickToggleID] = { QuickToggleID.defaultOrder }
    var keepOnTop: () -> Bool = { false }
    /// `.fullScreen` (default) shows the widget wall over the whole screen; `.floating` keeps the
    /// Phase 7B-V1 draggable panel. Read at each summon so a Settings change applies immediately.
    var style: () -> PinboardStyle = { .default }
    /// Backdrop look for the full-screen wall (launcher Theme/Tint settings).
    var look: () -> (theme: LauncherTheme, tint: LauncherTint) = { (.system, .none) }
    /// Height the KatiKati bottom bar occupies (it floats above `visibleFrame`), so the panel never sits under it.
    var bottomReserve: () -> Double = { 0 }
    private var backdrop: LauncherBackdrop?
    /// Which frame the live panel was built for; a style change rebuilds it (backdrop vs glass,
    /// popUpMenu vs floating level, drag tracking) instead of mixing the two.
    private var liveMode: PinboardStyle?

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle(only: [PinboardWidget]? = nil) { isShown ? dismiss() : show(only: only) }

    /// Returns the new state so the caller can confirm it on screen.
    var isKeepAwakeOn: Bool { toggles.keepAwakeOn }

    @discardableResult
    func toggleKeepAwake() -> Bool { toggles.setKeepAwake(!toggles.keepAwakeOn); return toggles.keepAwakeOn }

    func show(only: [PinboardWidget]? = nil) {
        guard !isShown, let weather = weather() else { return }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        switch style() {
        case .fullScreen: showFullScreen(only: only, weather: weather, screen: screen)
        case .floating: showFloating(only: only, weather: weather, screen: screen)
        }
    }

    /// The widget wall: full-screen launcher backdrop, coloured card grid centered, Esc / click
    /// outside the grid dismisses. Reuses `LauncherBackdrop` so the wall matches the launcher look.
    private func showFullScreen(only: [PinboardWidget]?, weather: WeatherService, screen: NSScreen) {
        if liveMode != .fullScreen { tearDown() }
        liveMode = .fullScreen
        let panel = self.panel ?? makeFullScreenPanel()
        self.panel = panel
        let view = PinboardFullScreenView(widgets: only ?? widgets(),
                                          context: PinboardContext(weather: weather, toggles: toggles, toggleOrder: toggleOrder()),
                                          onClose: { [weak self] in self?.dismiss() })
        let host = self.host ?? NSHostingView(rootView: AnyView(EmptyView()))
        host.rootView = AnyView(view)
        self.host = host
        let blur = (panel.contentView as? LauncherBackdrop) ?? makeBackdrop(host: host)
        if panel.contentView !== blur { panel.contentView = blur }
        let look = self.look()
        panel.appearance = backdrop?.apply(theme: look.theme, tint: look.tint, screen: screen)
        panel.setFrame(screen.frame, display: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func makeFullScreenPanel() -> PinboardPanel {
        let p = PinboardPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.onEscape = { [weak self] in self?.dismiss() }
        return p
    }

    private func makeBackdrop(host: NSView) -> LauncherBackdrop {
        let blur = LauncherBackdrop()
        backdrop = blur
        host.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: blur.leadingAnchor), host.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            host.topAnchor.constraint(equalTo: blur.topAnchor), host.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        return blur
    }

    private func showFloating(only: [PinboardWidget]?, weather: WeatherService, screen: NSScreen) {
        if liveMode != .floating { tearDown() }
        liveMode = .floating
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let view = PinboardView(widgets: only ?? widgets(), context: PinboardContext(weather: weather, toggles: toggles, toggleOrder: toggleOrder()))
        let host = self.host ?? NSHostingView(rootView: AnyView(EmptyView()))
        host.rootView = AnyView(view)
        self.host = host
        panel.contentView = Self.glass(around: host)
        var visible = screen.visibleFrame
        let reserve = CGFloat(bottomReserve())
        visible.origin.y += reserve
        visible.size.height -= reserve
        let height = min(host.fittingSize.height, visible.height - 24)
        let size = NSSize(width: PinboardTheme.panelWidth + PinboardTheme.gap * 2, height: max(160, height))
        panel.setContentSize(size)
        panel.setFrameOrigin(restoredOrigin(size: size, visible: visible))
        panel.makeKeyAndOrderFront(nil)
        installOutsideMonitor()
    }

    func dismiss() {
        guard let panel else { return }
        saveOrigin(panel.frame.origin)
        panel.orderOut(nil)
        host?.rootView = AnyView(EmptyView())
        removeOutsideMonitor()
    }

    func resetPosition() { defaults.removeObject(forKey: originKey) }

    func tearDown() { dismiss(); panel = nil; host = nil; liveMode = nil }

    private func makePanel() -> PinboardPanel {
        let p = PinboardPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.onEscape = { [weak self] in self?.dismiss() }
        return p
    }

    private static func glass(around host: NSView) -> NSView {
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = PinboardTheme.corner + PinboardTheme.gap
        blur.layer?.masksToBounds = true
        host.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: blur.leadingAnchor), host.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            host.topAnchor.constraint(equalTo: blur.topAnchor), host.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        return blur
    }

    private func restoredOrigin(size: NSSize, visible: NSRect) -> NSPoint {
        let saved = defaults.array(forKey: originKey) as? [Double]
        let want = saved.flatMap { $0.count == 2 ? (x: $0[0], y: $0[1]) : nil }
            ?? (x: Double(visible.maxX - size.width - 16), y: Double(visible.maxY - size.height - 12))
        let r = PinboardPlacement.clamp(origin: want, size: (Double(size.width), Double(size.height)),
                                        visible: (Double(visible.minX), Double(visible.minY), Double(visible.width), Double(visible.height)))
        return NSPoint(x: r.x, y: r.y)
    }

    private func saveOrigin(_ p: NSPoint) { defaults.set([Double(p.x), Double(p.y)], forKey: originKey) }

    private func installOutsideMonitor() {
        removeOutsideMonitor()
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.keepOnTop() else { return }
                self.dismiss()
            }
        }
    }

    private func removeOutsideMonitor() {
        if let m = outsideMonitor { NSEvent.removeMonitor(m); outsideMonitor = nil }
    }
}
