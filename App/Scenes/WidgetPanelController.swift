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

    private init(side: WidgetPanelSide, content: @escaping Content) {
        self.side = side
        self.makeContent = content
    }

    private var other: WidgetPanelController { self === Self.calendar ? Self.weather : Self.calendar }
    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? close() : show() }

    func close() {
        panel?.orderOut(nil)
        state.isVisible = false
        if let monitor = outsideClickMonitor { NSEvent.removeMonitor(monitor) }
        outsideClickMonitor = nil
    }

    /// Reads the shared layout, carrying the pre-rework size preset over once (`compact420`→mac, `halfScreen`→ipad).
    static func currentLayout(defaults: UserDefaults = .standard) -> CalendarPanelLayout {
        if let raw = defaults.string(forKey: CalendarPanelLayout.storageKey), let layout = CalendarPanelLayout(rawValue: raw) {
            return layout
        }
        let migrated = CalendarPanelSettingsMigration.layout(fromLegacy: defaults.string(forKey: "com.katikati.calendar.panelPreset")) ?? .mac
        defaults.set(migrated.rawValue, forKey: CalendarPanelLayout.storageKey)
        return migrated
    }

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
        panel.setFrame(PanelGeometry.widgetPanelFrame(on: geometry, layout: layout, side: side, contentHeight: .greatestFiniteMagnitude), display: true)
        state.isVisible = true
        panel.makeKeyAndOrderFront(nil)
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
