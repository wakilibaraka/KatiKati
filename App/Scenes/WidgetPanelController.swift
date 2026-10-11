import AppKit
import SwiftUI

/// Panel subclass that can take key focus without activating the app, so Esc (`cancelOperation`)
/// dismisses it.
final class WidgetFloatingPanel: NonConstrainingPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

/// Visibility of one widget stack, published so animated content (weather effects) can pause while
/// the window is ordered out.
@MainActor
final class WidgetPanelState: ObservableObject {
    @Published var isVisible = false
    /// Drives the staggered "spring pop" entrance (false → tiles hidden, true → tiles shown).
    @Published var entered = false
    @Published var animation: WidgetAnimationPreset = .instant
}

/// Owns one floating widget-tile window (calendar on the right, weather on the left). The window is
/// transparent and **content-sized**: the tiles report their height and the pure
/// `PanelGeometry.widgetPanelFrame` places it. Dismissal = toggle again, Esc, or a click outside the
/// app. By default opening one stack closes the other ("Keep both open" lifts that).
@MainActor
final class WidgetPanelController {
    typealias Content = (_ layout: CalendarPanelLayout, _ width: CGFloat, _ maxHeight: CGFloat,
                         _ state: WidgetPanelState, _ onHeight: @escaping (CGFloat) -> Void) -> AnyView

    static let keepBothOpenKey = "com.katikati.widgets.keepBothOpen"

    static let calendar = WidgetPanelController(side: .right) { layout, width, maxHeight, state, onHeight in
        AnyView(CalendarPanelView(layout: layout, width: width, maxHeight: maxHeight, onHeight: onHeight).environmentObject(state))
    }
    static let weather = WidgetPanelController(side: .left) { layout, width, maxHeight, state, onHeight in
        AnyView(WeatherPanelView(layout: layout, width: width, maxHeight: maxHeight, onHeight: onHeight).environmentObject(state))
    }

    let side: WidgetPanelSide
    let state = WidgetPanelState()
    private let makeContent: Content
    private var panel: WidgetFloatingPanel?
    private var outsideClickMonitor: Any?
    private var layoutShown: CalendarPanelLayout?
    private var geometry: PanelScreenGeometry?
    private var isClosing = false
    private var isOpening = false
    private var pendingHeight: CGFloat?

    private init(side: WidgetPanelSide, content: @escaping Content) {
        self.side = side
        self.makeContent = content
    }

    private var other: WidgetPanelController { self === Self.calendar ? Self.weather : Self.calendar }
    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        guard !isClosing else { return }
        isVisible ? close() : show()
    }

    static func currentAnimation(defaults: UserDefaults = .standard) -> WidgetAnimationPreset {
        WidgetAnimationPreset.resolve(defaults: defaults, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func close() {
        guard let panel, panel.isVisible, !isClosing else { return }
        isClosing = true
        if let monitor = outsideClickMonitor { NSEvent.removeMonitor(monitor) }
        outsideClickMonitor = nil
        state.isVisible = false
        state.entered = false
        let preset = state.animation
        let finish = { [weak self] in
            panel.orderOut(nil)
            panel.alphaValue = 1
            self?.isClosing = false
        }
        switch preset {
        case .instant:
            finish()
        case .slide, .springPop:
            var away = panel.frame
            if preset == .slide, let g = geometry {
                away.origin.x = WidgetAnimationTiming.slideStartX(target: Double(away.minX), width: Double(away.width), side: side,
                                                                    screenMinX: Double(g.frame.minX), screenMaxX: Double(g.frame.maxX))
            }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = WidgetAnimationTiming.closeDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
                if preset == .slide { panel.animator().setFrame(away, display: true) }
            }, completionHandler: finish)
        }
    }

    static func currentLayout(defaults: UserDefaults = .standard) -> CalendarPanelLayout { .resolve(defaults: defaults) }

    private func show() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let layout = Self.currentLayout()
        let geometry = PanelScreenGeometry(
            frame: screen.frame, visibleFrame: screen.visibleFrame, safeAreaTop: screen.safeAreaInsets.top
        )
        self.geometry = geometry
        closeOtherIfNeeded(layout: layout, geometry: geometry)
        if layoutShown != layout { self.panel?.orderOut(nil); self.panel = nil }
        layoutShown = layout

        let panel = self.panel ?? makePanel(layout: layout, geometry: geometry)
        // Start at the tallest allowed frame so the tiles never clip while they measure themselves;
        // the first height report shrinks the window to fit.
        let target = PanelGeometry.widgetPanelFrame(on: geometry, layout: layout, side: side, contentHeight: .greatestFiniteMagnitude)
        let preset = Self.currentAnimation()
        state.animation = preset
        state.entered = false
        state.isVisible = true
        pendingHeight = nil
        if preset == .slide {
            var start = target
            start.origin.x = WidgetAnimationTiming.slideStartX(target: Double(target.minX), width: Double(target.width), side: side,
                                                                 screenMinX: Double(geometry.frame.minX), screenMaxX: Double(geometry.frame.maxX))
            panel.alphaValue = 0
            panel.setFrame(start, display: false)
            panel.makeKeyAndOrderFront(nil)
            isOpening = true
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = WidgetAnimationTiming.slideDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(target, display: true)
            }, completionHandler: { [weak self] in
                guard let self else { return }
                self.isOpening = false
                if let h = self.pendingHeight { self.resize(toContentHeight: h, layout: layout) }
            })
        } else {
            panel.alphaValue = 1
            panel.setFrame(target, display: true)
            panel.makeKeyAndOrderFront(nil)
        }
        DispatchQueue.main.async { [weak self] in self?.state.entered = true }
        installOutsideClickMonitor()
    }

    /// One at a time unless "Keep both open" is on and both stacks fit side by side.
    private func closeOtherIfNeeded(layout: CalendarPanelLayout, geometry: PanelScreenGeometry) {
        guard other.isVisible else { return }
        let keep = UserDefaults.standard.bool(forKey: Self.keepBothOpenKey)
        let widths = layout.width(forScreenWidth: geometry.frame.width) * 2 + 3 * PanelLayoutMetrics.tungstenEdge.outerMargin
        if !keep || widths > geometry.visibleFrame.width { other.close() }
    }

    private func resize(toContentHeight height: CGFloat, layout: CalendarPanelLayout) {
        guard let panel, let geometry, height > 0 else { return }
        if isOpening { pendingHeight = height; return }
        let frame = PanelGeometry.widgetPanelFrame(on: geometry, layout: layout, side: side, contentHeight: height)
        if frame != panel.frame { panel.setFrame(frame, display: true) }
    }

    private func makePanel(layout: CalendarPanelLayout, geometry: PanelScreenGeometry) -> WidgetFloatingPanel {
        let panel = WidgetFloatingPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = PanelCollectionBehavior.standard
        panel.isFloatingPanel = true
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        let width = layout.width(forScreenWidth: geometry.frame.width)
        let view = makeContent(layout, width, PanelGeometry.widgetPanelMaxHeight(on: geometry), state) { [weak self] h in
            DispatchQueue.main.async { self?.resize(toContentHeight: h, layout: layout) }
        }
        let hosting = NSHostingView(rootView: view)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting
        self.panel = panel
        return panel
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        // Global monitors only see events destined for *other* apps, so a tap on the bar (the pill or
        // clock toggling itself) never races this dismissal.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }
}
