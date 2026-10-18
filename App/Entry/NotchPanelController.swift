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
    private var gesture = NotchGestureSupport()
    /// 60 Hz poll of `NSEvent.mouseLocation`, alive only while the pointer is near the notch or the
    /// notch is open (the `StripPointerTracker` pattern). Resident global mouse monitors are banned by
    /// the project rules (they route every system mouse event through this process).
    private var hoverTimer: Timer?
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
        window.contentView = container(for: NotchIslandView(model: model, metrics: metrics, theme: theme()))
        panel = window
        LiveActivityFeed.shared.retain()
        holdsFeed = true
        window.setFrame(windowFrame(on: screen), display: true)
        window.orderFrontRegardless()

        LiveActivityFeed.shared.$activity.map(\.kind).removeDuplicates().sink { [weak self] _ in self?.activityChanged() }.store(in: &cancellables)
        model.$event.map { $0 != nil }.removeDuplicates().sink { [weak self] _ in self?.syncWindow() }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.screensChanged() }.store(in: &cancellables)
    }

    private func hide() {
        cancellables.removeAll()
        stopHoverPolling()
        tickWork?.cancel(); tickWork = nil
        shrinkWork?.cancel(); shrinkWork = nil
        eventWork?.cancel(); eventWork = nil
        model.event = nil; model.isOpen = false
        LiveActivityFeed.shared.isNotchExpanded = false
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
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchMotionSpec.eventLifetime, execute: work)
    }

    // MARK: hover

    private func startHoverPolling() {
        guard hoverTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluateHover() }
        }
        timer.tolerance = 0.004
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
        evaluateHover()
    }

    private func stopHoverPolling() {
        hoverTimer?.invalidate()
        hoverTimer = nil
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
        // Poll only while it matters: pointer near the notch, open, or a dwell/grace timer pending.
        if !hover.isOpen, !inTrigger, hover.nextDeadline == nil { stopHoverPolling() }
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
        if hover.isOpen && !model.isOpen {
            let nowPlaying = LiveActivityFeed.shared.activity.kind == .music
            model.activePage = NotchPagingPolicy.defaultPage(
                nowPlayingActive: nowPlaying,
                aiTurnActive: false
            )
        }
        model.isOpen = hover.isOpen
        LiveActivityFeed.shared.isNotchExpanded = model.isExpanded
        syncWindow()
    }

    /// Shortcut paging: open the notch if closed, then step one page (the dots' mouse-only gap).
    func stepPage(forward: Bool) {
        guard panel != nil else { return }
        hover.forceOpen()
        applyOpenState()
        model.stepPage(forward: forward)
        startHoverPolling()
    }

    /// Phase 9d shortcut: open the notch on its Tools tab, or close it if it is already showing it.
    func toggleTools() {
        guard panel != nil else { return }
        if model.isOpen, model.tab == .tools { collapse(); return }
        model.tab = .tools
        hover.forceOpen()
        applyOpenState()
        startHoverPolling()
    }

    func collapse() {
        hover.forceClose()
        model.isOpen = false
        LiveActivityFeed.shared.isNotchExpanded = false
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
        panel?.contentView = container(for: NotchIslandView(model: model, metrics: metrics, theme: theme()))
        syncWindow(immediate: true)
    }

    private func activityChanged() {
        syncModelSizes()
        syncWindow()
    }

    /// Shape sizes the view animates between.
    private func syncModelSizes() {
        // Always wide: when nothing is live the two sides carry the dock chips (storage left, battery right).
        let showsActivity = true
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

    private func handleScroll(_ event: NSEvent) -> Bool {
        guard panel != nil, event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
            gesture = NotchGestureSupport()
            return false
        }
        let precise = event.hasPreciseScrollingDeltas
        let inverted = event.isDirectionInvertedFromDevice
        let x = NotchGestureSupport.movement(Double(event.scrollingDeltaX), precise: precise, inverted: inverted)
        let y = NotchGestureSupport.movement(Double(event.scrollingDeltaY), precise: precise, inverted: inverted)

        let horizontalMode: NotchGestureSupport.HorizontalMode = (model.activePage == .audioDeck) ? .trackSkip : .pageNavigation

        guard let action = gesture.handle(
            x: x,
            y: y,
            timestamp: event.timestamp,
            began: event.phase.contains(.began),
            ended: !event.phase.intersection([.ended, .cancelled]).isEmpty,
            momentum: !event.momentumPhase.isEmpty,
            precise: precise,
            hasPhase: !event.phase.isEmpty,
            allowVertical: true,
            allowHorizontal: model.isExpanded,
            expanded: model.isExpanded,
            horizontalMode: horizontalMode
        ) else {
            return false
        }

        switch action {
        case .open:
            hover.forceOpen()
            applyOpenState()
            startHoverPolling()
        case .close:
            collapse()
        case .nextPage:
            withAnimation(.spring(response: NotchMotionSpec.pageStepSpring.response, dampingFraction: NotchMotionSpec.pageStepSpring.dampingRatio)) {
                model.stepPage(forward: true)
            }
        case .previousPage:
            withAnimation(.spring(response: NotchMotionSpec.pageStepSpring.response, dampingFraction: NotchMotionSpec.pageStepSpring.dampingRatio)) {
                model.stepPage(forward: false)
            }
        case .nextTrack:
            LiveActivityFeed.shared.nextTrack()
        case .previousTrack:
            LiveActivityFeed.shared.previousTrack()
        }
        return true
    }

    /// The hosting view lives inside a plain autoresizing container so SwiftUI's intrinsic size can never
    /// drive the panel (that fed back into window sizing during an update-constraints pass and crashed).
    /// The container also owns the tracking area whose *enter* starts the hover poll.
    private func container<V: View>(for view: V) -> NSView {
        let container = NotchTrackingContainer(frame: .zero)
        container.onEnter = { [weak self] in self?.startHoverPolling() }
        container.onScroll = { [weak self] event in
            guard let self else { return false }
            return self.handleScroll(event)
        }
        let host = NSHostingView(rootView: view)
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        return container
    }
}

/// Reports the pointer entering the notch window. Enter/exit is reliable for non-key panels (mouse-moved
/// is not), so it only *starts* the poll; the poll decides everything else.
final class NotchTrackingContainer: NSView {
    var onEnter: () -> Void = {}
    var onScroll: ((NSEvent) -> Bool)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onEnter() }

    override func scrollWheel(with event: NSEvent) {
        if onScroll?(event) == true {
            return
        }
        super.scrollWheel(with: event)
    }
}
