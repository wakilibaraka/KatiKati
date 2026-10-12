import AppKit
import Combine
import SwiftUI

/// Phase 8b-7 — owns the notch panel. KatiKati's adapter around boring.notch's vendored
/// `BoringNotchWindow` (Vendor/boring.notch): window recipe is upstream's, everything else is ours.
///
/// Lifecycle: built only when the notch island is switched on, torn down when it goes off (so a user
/// who never enables it pays nothing). While shown it holds the shared `LiveActivityFeed` tick and is a
/// `LiveEventSink`, so the event router can send events here. Fullscreen: the panel deliberately drops
/// `.fullScreenAuxiliary`, so it does not appear over a fullscreen app's space.
@MainActor
final class NotchPanelController: LiveEventSink {
    private var panel: BoringNotchWindow?
    private let model = NotchModel()
    private var cancellables = Set<AnyCancellable>()
    private var eventWork: DispatchWorkItem?
    private var metrics = NotchMetrics(closedSize: CGSize(width: NotchGeometry.fallbackNotchWidth, height: NotchGeometry.fallbackHeight), hasHardwareNotch: false)
    private var holdsFeed = false
    // Hover intent: a pure state machine fed from mouse monitors (see `NotchHoverMachine`). The window is
    // never resized by hover itself, so there is no resize → tracking-area → hover feedback loop.
    private var hover = NotchHoverMachine()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var tickWork: DispatchWorkItem?
    private var shrinkWork: DispatchWorkItem?
    var theme: () -> NowPlayingTheme = { .auto }
    var onOpenSettings: () -> Void = {}
    var skin: LiveIslandSkin = .boring {
        didSet { guard skin != oldValue else { return }; model.skin = skin; syncModelSizes(); syncWindow() }
    }

    /// Whether the panel exists and is on screen — the router's "usable" test for the notch.
    var isUsable: Bool { panel?.isVisible ?? false }

    // MARK: lifecycle

    func setEnabled(_ enabled: Bool) {
        enabled ? show() : hide()
    }

    private func show() {
        guard panel == nil, let screen = targetScreen() else { return }
        metrics = Self.metrics(for: screen)
        model.skin = skin
        model.collapse = { [weak self] in self?.collapse() }
        model.openSettings = { [weak self] in self?.onOpenSettings() }
        syncModelSizes()
        let window = BoringNotchWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        window.acceptsMouseMovedEvents = true
        window.ignoresMouseEvents = true   // closed: never swallow clicks meant for the menu bar
        window.contentView = Self.container(for: NotchIslandView(model: model, metrics: metrics, theme: theme()))
        panel = window
        LiveActivityFeed.shared.retain()
        holdsFeed = true
        window.setFrame(windowFrame(on: screen), display: true)
        window.orderFrontRegardless()

        LiveActivityFeed.shared.$activity.map(\.kind).removeDuplicates().sink { [weak self] _ in self?.activityChanged() }.store(in: &cancellables)
        model.$event.map { $0 != nil }.removeDuplicates().sink { [weak self] _ in self?.syncWindow() }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.screensChanged() }.store(in: &cancellables)
        startMouseMonitors()
    }

    private func hide() {
        cancellables.removeAll()
        stopMouseMonitors()
        tickWork?.cancel(); tickWork = nil
        shrinkWork?.cancel(); shrinkWork = nil
        eventWork?.cancel(); eventWork = nil
        model.event = nil; model.isOpen = false
        hover.forceClose()
        panel?.orderOut(nil)
        panel = nil
        if holdsFeed { LiveActivityFeed.shared.release(); holdsFeed = false }
    }

    // MARK: LiveEventSink

    func show(_ event: LiveEvent) {
        guard panel != nil else { return }
        model.event = LiveEventPresentation(event)
        eventWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.model.event = nil
            self?.evaluateHover()
        }
        eventWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    // MARK: hover

    private func startMouseMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluateHover() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.evaluateHover() }
            return event
        }
    }

    private func stopMouseMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil
    }

    private func evaluateHover(now: Date = Date()) {
        guard panel != nil, let screen = targetScreen() else { return }
        let cursor = NSEvent.mouseLocation
        let closed = NotchGeometry.panelFrame(size: model.closedSize, in: screen.frame)
        let open = NotchGeometry.panelFrame(size: model.openSize, in: screen.frame)
        let inTrigger = NotchHoverZones.trigger(closedFrame: closed).contains(cursor)
        let inKeepOpen = NotchHoverZones.keepOpen(openFrame: open).contains(cursor)
        // A drag that began inside the open panel (volume slider) keeps it open even if the cursor leaves.
        let dragging = hover.isOpen && NSEvent.pressedMouseButtons & 1 != 0
        let wasOpen = hover.isOpen
        hover.update(inTrigger: inTrigger, inKeepOpen: inKeepOpen, pinned: dragging || model.event != nil, now: now)
        if hover.isOpen != wasOpen { applyOpenState() }
        scheduleTick()
    }

    /// Wake the machine at its next deadline even if the cursor stops moving (dwell to open / grace to close).
    private func scheduleTick() {
        tickWork?.cancel(); tickWork = nil
        guard let deadline = hover.nextDeadline else { return }
        let work = DispatchWorkItem { [weak self] in self?.evaluateHover() }
        tickWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, deadline.timeIntervalSinceNow + 0.005), execute: work)
    }

    private func applyOpenState() {
        model.isOpen = hover.isOpen
        syncWindow()
    }

    func collapse() {
        hover.forceClose()
        model.isOpen = false
        syncWindow()
    }

    // MARK: geometry

    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    private static func metrics(for screen: NSScreen) -> NotchMetrics {
        NotchGeometry.metrics(
            screenWidth: screen.frame.width,
            safeAreaTop: screen.safeAreaInsets.top,
            auxLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxRightWidth: screen.auxiliaryTopRightArea?.width,
            menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY)
    }

    private func screensChanged() {
        guard panel != nil, let screen = targetScreen() else { return }
        metrics = Self.metrics(for: screen)
        syncModelSizes()
        panel?.contentView = Self.container(for: NotchIslandView(model: model, metrics: metrics, theme: theme()))
        syncWindow(immediate: true)
    }

    private func activityChanged() {
        syncModelSizes()
        syncWindow()
    }

    /// Shape sizes the view animates between.
    private func syncModelSizes() {
        let showsActivity = LiveActivityFeed.shared.activity.kind != .clock
        let screenWidth = targetScreen()?.frame.width ?? 1440
        model.closedSize = NotchGeometry.closedCapsuleSize(metrics, showsActivity: showsActivity)
        model.openSize = NotchLayoutSpec.fit(NotchGeometry.openSize(for: skin), screenWidth: screenWidth, closedWidth: metrics.closedSize.width)
    }

    /// The window is as large as the larger of the shapes involved: it grows at once (so the shape never
    /// clips while it animates open) and shrinks only after the close spring has finished.
    private func windowFrame(on screen: NSScreen) -> CGRect {
        let size = model.isExpanded ? model.openSize : model.closedSize
        return NotchGeometry.panelFrame(size: size, in: screen.frame)
    }

    private func syncWindow(immediate: Bool = false) {
        // The triggers (hover, event, activity change) can fire from inside SwiftUI's update pass; resizing
        // the window re-entrantly from there is what AppKit objects to, so defer one turn.
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, let screen = self.targetScreen() else { return }
            let target = self.windowFrame(on: screen)
            panel.ignoresMouseEvents = !self.model.isExpanded
            self.shrinkWork?.cancel(); self.shrinkWork = nil
            let grows = target.width >= panel.frame.width && target.height >= panel.frame.height
            if grows || immediate {
                panel.setFrame(target, display: true)
            } else {
                let work = DispatchWorkItem { [weak self] in
                    guard let self, let panel = self.panel, let screen = self.targetScreen() else { return }
                    panel.setFrame(self.windowFrame(on: screen), display: true)
                }
                self.shrinkWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: work)
            }
        }
    }

    /// The hosting view lives inside a plain autoresizing container so SwiftUI's intrinsic size can never
    /// drive the panel (that fed back into window sizing during an update-constraints pass and crashed).
    private static func container<V: View>(for view: V) -> NSView {
        let container = NSView(frame: .zero)
        let host = NSHostingView(rootView: view)
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        return container
    }
}
