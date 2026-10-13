import AppKit
import SwiftUI

/// Phase 9-0 — owns the floating chip panel: a single non-activating panel above the strip that shows
/// the hover preview (9c) or the right-click jump list (9b). Hover intent runs on the pure
/// `ChipPanelHoverMachine`; the pointer is read by a timer that only exists while a chip is hovered or
/// the panel is up — **no resident global mouse monitor** (only a mouse-down pair while the jump list
/// is visible, like the title tooltip).
@MainActor
final class ChipPanelController {
    let model = ChipPanelModel()
    private let arrow = StackPopupArrowModel()

    // Injected by `PanelCoordinator`.
    var makePanel: () -> NSPanel = { NSPanel() }
    var contentFor: (String) -> ChipPanelContent? = { _ in nil }
    var screenFrameContaining: (CGPoint) -> CGRect = { _ in NSScreen.main?.frame ?? .zero }
    var previewEnabled: () -> Bool = { true }
    var openDelay: () -> TimeInterval = { 0.35 }
    var thumbnailWidth: () -> CGFloat = { 180 }
    var usesLiquidGlass: () -> Bool = { false }
    var themeStyle: () -> DockThemeStyle = { .auto }
    /// Phase 18d: beside a side rail the panel opens inward and drops its bottom arrow.
    var stripPlacement: () -> StripPlacement = { .bottom }
    var onWillOpen: () -> Void = {}
    var onPanelShown: (NSPanel) -> Void = { _ in }

    private var panel: NSPanel?
    private var hosting: NSHostingView<AnyView>?
    private var machine = ChipPanelHoverMachine()
    private var hoverChip: String?
    private var hoverAnchor: CGRect = .zero
    private var anchor: CGRect = .zero
    private var pollTimer: Timer?
    private var captureTimer: Timer?
    private var mouseDownLocal: Any?
    private var mouseDownGlobal: Any?
    private var lastPanelHover = false

    var isVisible: Bool { panel?.isVisible == true }
    var shownChipID: String? { isVisible ? model.content?.chipID : nil }
    var isMenuOpen: Bool { isVisible && model.mode == .menu }

    init() {
        model.activateWindow = { [weak self] id in self?.perform { $0.runActivate(id) } }
        model.closeWindow = { [weak self] id in self?.closeWindowRow(id) }
    }

    // Actions that need the runtime are provided through these hooks.
    var runActivate: (String) -> Void = { _ in }
    var runCloseWindow: (String) -> Void = { _ in }
    var runOpenRecent: (ChipPanelRecent) -> Void = { _ in }

    private func perform(_ body: (ChipPanelController) -> Void) {
        body(self)
        hide()
    }

    private func closeWindowRow(_ id: String) {
        runCloseWindow(id)
        // Drop the row immediately; the snapshot catches up a moment later.
        if var content = model.content {
            content.ownWindows.removeAll { $0.id == id }
            content.allWindows.removeAll { $0.id == id }
            if content.allWindows.isEmpty { hide() } else { model.content = content; reposition() }
        }
    }

    func wire() {
        model.openRecent = { [weak self] r in self?.runOpenRecent(r); self?.hide() }
        model.runAction = { [weak self] action in
            let option = NSEvent.modifierFlags.contains(.option)
            self?.hide()
            action.handler(option)
        }
        model.requestScreenAccess = { WindowThumbnailCapture.requestAuthorization() }
    }

    // MARK: Hover (preview)

    /// The strip reports which window chip the pointer is on (nil = none).
    func hoverChanged(chipID: String?, anchor: CGRect) {
        hoverChip = chipID
        if chipID != nil { hoverAnchor = anchor }
        if chipID != nil || isVisible { startPolling() }
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func tick() {
        model.optionHeld = NSEvent.modifierFlags.contains(.option)
        let mouse = NSEvent.mouseLocation
        let overPanel = isVisible && panel.map { ChipPanelLayout.plateFrame(panelFrame: $0.frame).contains(mouse) } == true
        if model.mode == .menu {
            // The jump list stays until a click outside or an action; nothing to arbitrate.
            if !isVisible { stopPolling() }
            return
        }
        if overPanel, !lastPanelHover { model.expanded = true; reposition() }
        lastPanelHover = overPanel

        let blocked = !previewEnabled() || (!isVisible && NSEvent.pressedMouseButtons != 0)
        machine.openDelay = openDelay()
        let output = machine.update(overChip: hoverChip, overPanel: overPanel, blocked: blocked,
                                    now: ProcessInfo.processInfo.systemUptime)
        switch output {
        case .none: break
        case let .open(chip): presentPreview(chipID: chip)
        case let .switchTo(chip): presentPreview(chipID: chip)
        case .close: hide()
        }
        if machine.isIdle, hoverChip == nil, !isVisible { stopPolling() }
    }

    private func presentPreview(chipID: String) {
        guard let content = contentFor(chipID), !content.ownWindows.isEmpty else {
            machine.forceClose()
            return
        }
        anchor = hoverAnchor
        model.content = content
        model.mode = .preview
        model.expanded = false
        lastPanelHover = false
        show()
    }

    // MARK: Jump list (menu)

    func openMenu(chipID: String, anchor: CGRect) {
        machine.forceClose()
        guard let content = contentFor(chipID) else { return }
        self.anchor = anchor
        model.content = content
        model.mode = .menu
        model.expanded = true
        show()
        installMouseDownMonitors()
        startPolling()
    }

    /// Any chip's `NSMenu`, shown as the floating panel above `anchor`.
    func openMenu(_ menu: NSMenu, anchor: CGRect) {
        machine.forceClose()
        self.anchor = anchor
        model.content = ChipPanelMenuBridge.content(from: menu)
        model.mode = .menu
        model.expanded = true
        show()
        installMouseDownMonitors()
        startPolling()
    }

    // MARK: Presentation

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let created = makePanel()
        let view = ChipPanelView(model: model, arrow: arrow, usesLiquidGlass: usesLiquidGlass(),
                                 onPanelSizeChange: { [weak self] _ in self?.reposition() })
            .environment(\.dockThemeStyle, themeStyle())
        let host = NSHostingView(rootView: AnyView(view))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        let container = NSView(frame: .zero)
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        created.contentView = container
        panel = created
        hosting = host
        return created
    }

    private func show() {
        onWillOpen()
        model.thumbWidth = thumbnailWidth()
        model.screenAccess = WindowThumbnailCapture.isAuthorized
        let panel = ensurePanel()
        reposition()
        let wasVisible = panel.isVisible
        if !wasVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            onPanelShown(panel)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
        startCaptures()
    }

    private func reposition() {
        guard let panel, model.content != nil else { return }
        let plate = model.plateSize
        guard plate.width > 0 else { return }
        let screen = screenFrameContaining(CGPoint(x: anchor.midX, y: anchor.midY))
        let edge = stripPlacement()
        let placement = ChipPanelLayout.placement(anchor: anchor, plate: plate, screen: screen, stripPlacement: edge)
        arrow.offsetFromCenter = placement.arrowOffsetFromCenter
        if arrow.isHidden != edge.isVertical { arrow.isHidden = edge.isVertical }
        if panel.frame != placement.panelFrame { panel.setFrame(placement.panelFrame, display: true) }
    }

    func hide() {
        machine.forceClose()
        lastPanelHover = false
        removeMouseDownMonitors()
        captureTimer?.invalidate()
        captureTimer = nil
        if let panel, panel.isVisible { panel.orderOut(nil) }
        model.thumbnails = [:]
        model.content = nil
        model.mode = .preview
        model.expanded = false
        if hoverChip == nil { stopPolling() }
    }

    // MARK: Thumbnails (only while the panel is up)

    private func startCaptures() {
        captureTimer?.invalidate()
        captureTimer = nil
        guard model.mode == .preview, WindowThumbnailCapture.isAuthorized else { return }
        captureVisibleWindows()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.captureVisibleWindows() }
        }
        captureTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func captureVisibleWindows() {
        guard isVisible, model.mode == .preview else { return }
        let scale = panel?.backingScaleFactor ?? 2
        let px = CGSize(width: model.thumbSize.width * scale, height: model.thumbSize.height * scale)
        for window in model.previewWindows where window.marker != .minimized {
            guard let cg = window.cgWindowID else { continue }
            let id = window.id
            WindowThumbnailCapture.capture(windowID: cg, maxPixelSize: px) { [weak self] image in
                MainActor.assumeIsolated {
                    guard let self, self.isVisible, let image else { return }
                    self.model.thumbnails[id] = image
                }
            }
        }
    }

    // MARK: Dismiss on outside click (jump list only)

    private func installMouseDownMonitors() {
        removeMouseDownMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        mouseDownLocal = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.dismissIfOutside()
            return event
        }
        mouseDownGlobal = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.dismissIfOutside()
        }
    }

    private func removeMouseDownMonitors() {
        if let m = mouseDownLocal { NSEvent.removeMonitor(m) }
        if let m = mouseDownGlobal { NSEvent.removeMonitor(m) }
        mouseDownLocal = nil
        mouseDownGlobal = nil
    }

    private func dismissIfOutside() {
        guard let panel, panel.isVisible else { return }
        let plate = ChipPanelLayout.plateFrame(panelFrame: panel.frame)
        if !plate.contains(NSEvent.mouseLocation) { hide() }
    }
}
