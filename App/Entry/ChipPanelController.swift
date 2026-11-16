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
    /// Phase 12: the Appearance page's plate knobs, injected beside the style (identity default).
    var themeTuning: () -> ThemeTuning = { .identity }
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
    /// Windows whose capture has not returned yet (see `ChipPanelCapturePolicy.dueWindowIDs`).
    private var inFlight: Set<String> = []
    /// Bumped whenever results from the current capture epoch become stale (hide, pause, revoke).
    private var captureGeneration: UInt64 = 0
    /// Cached TCC verdict. Refreshed off-main at a bounded cadence, never in a hover tick.
    private var screenAccessAuthorized = false
    private var lastAuthorizationCheck: TimeInterval = -.infinity
    private var authorizationCheckInFlight = false
    private var authorizationCheckGeneration: UInt64 = 0
    private var authorizationRefreshPending = false
    /// TCC preflight is expensive and can block; the 0.5 s tick only *requests* a check, which
    /// runs off-main and at most this often.
    private let authorizationCheckInterval: TimeInterval = 2
    /// Block-based observer tokens, removed by `removeScreenAvailabilityObservers()`.
    private var workspaceObservers: [NSObjectProtocol] = []
    /// Track these independently because display wake can precede system wake, or vice versa.
    private var displayAsleep = false
    private var systemAsleep = false
    /// Session locked, switched away or logged out (`NSWorkspace.sessionDidResignActiveNotification`).
    private var sessionInactive = false
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

    deinit {
        // `deinit` is nonisolated; remove the tokens directly rather than through a
        // MainActor-isolated helper. `tearDown()` covers the coordinator-retained case.
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    /// Stop timers, monitors and workspace observers. Idempotent; also reached from
    /// `PanelCoordinator.tearDown()` because the coordinator otherwise retains this object for
    /// the process lifetime and `deinit` would never run.
    func tearDown() {
        hide()
        stopPolling()
        captureTimer?.invalidate()
        captureTimer = nil
        pollTimer?.invalidate()
        pollTimer = nil
        removeScreenAvailabilityObservers()
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
        observeScreenAvailability()
        refreshScreenAccess(immediate: true)
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
        // Watchdog: the strip's tracking area drops fast exits, which would leave `hoverChip` set and
        // keep the preview open. The real pointer is the authority.
        if hoverChip != nil, !ChipPanelHoverMachine.pointerOnChip(mouse, anchor: hoverAnchor) { hoverChip = nil }

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
            .environment(\.themeTuning, themeTuning())
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
        invalidateCaptureResults()
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
        guard model.mode == .preview else { return }
        captureVisibleWindows()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.captureVisibleWindows() }
        }
        captureTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func captureVisibleWindows() {
        guard let panel else { return }
        guard !ChipPanelCapturePolicy.isPaused(displayAsleep: displayAsleep,
                                              systemAsleep: systemAsleep,
                                              sessionInactive: sessionInactive) else { return }
        // This tick decides only from the cached verdict. The request below refreshes it
        // off-main and self-throttles, so a slow TCC call cannot stall the hover path and a
        // revoke while authorized is still noticed.
        refreshScreenAccess()
        guard screenAccessAuthorized else {
            if !model.thumbnails.isEmpty { model.thumbnails = [:] }
            return
        }
        switch ChipPanelCapturePolicy.verdict(isOpen: isVisible,
                                              isPreview: model.mode == .preview,
                                              isAuthorized: screenAccessAuthorized) {
        case .idle:
            return
        case .revoked:
            // The grant went away (or was never given) under an open panel: the frames we
            // already took are no longer trustworthy, so drop them.
            if !model.thumbnails.isEmpty { model.thumbnails = [:] }
            return
        case .run:
            break
        }
        let scale = panel.backingScaleFactor
        let px = CGSize(width: model.thumbSize.width * scale, height: model.thumbSize.height * scale)
        var pixelsByID: [String: CGWindowID] = [:]
        var orderedIDs: [String] = []
        for window in model.previewWindows where window.marker != .minimized {
            guard let cg = window.cgWindowID else { continue }
            if pixelsByID[window.id] == nil { orderedIDs.append(window.id) }
            pixelsByID[window.id] = cg
        }
        // On-screen order, so the first card is the first to paint.
        let due = ChipPanelCapturePolicy.dueWindowIDs(orderedIDs, inFlight: inFlight)
        for id in due {
            guard let cg = pixelsByID[id] else { continue }
            inFlight.insert(id)
            let generation = captureGeneration
            Task { @MainActor [weak self] in
                let image = await WindowThumbnailCapture.captureAuthorized(windowID: cg, maxPixelSize: px)
                guard let self else { return }
                // Released only when this window's own capture returns, so a capture that
                // hangs keeps that window out of the queue instead of stacking behind it.
                self.inFlight.remove(id)
                guard ChipPanelCapturePolicy.mayApplyCapture(
                    isOpen: self.isVisible,
                    isAuthorized: self.screenAccessAuthorized,
                    startedGeneration: generation,
                    currentGeneration: self.captureGeneration
                ), let image else { return }
                self.model.thumbnails[id] = image
            }
        }
    }

    // MARK: Screen availability (sleep, lock)

    /// Pause captures while the display is asleep or the session is locked, and refill the
    /// grid as soon as it is available again. Retained block-observer tokens are removed by
    /// `tearDown()` (permission loss) or `deinit`.
    private func observeScreenAvailability() {
        // `wire()` may be called again after a rebuild; never stack duplicate registrations.
        removeScreenAvailabilityObservers()
        let center = NSWorkspace.shared.notificationCenter
        let names: [(Notification.Name, Bool?, Bool?, Bool?)] = [
            (NSWorkspace.screensDidSleepNotification, true, nil, nil),
            (NSWorkspace.willSleepNotification, nil, true, nil),
            (NSWorkspace.screensDidWakeNotification, false, nil, nil),
            (NSWorkspace.didWakeNotification, nil, false, nil),
            (NSWorkspace.sessionDidResignActiveNotification, nil, nil, true),
            (NSWorkspace.sessionDidBecomeActiveNotification, nil, nil, false),
        ]
        for (name, display, system, inactive) in names {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.availabilityChanged(displayAsleep: display, systemAsleep: system,
                                              sessionInactive: inactive)
                }
            }
            workspaceObservers.append(observer)
        }
    }

    /// Removes the retained workspace registrations and clears the tokens, so calling this
    /// twice is harmless. `NotificationCenter` requires the exact token returned at registration.
    private func removeScreenAvailabilityObservers() {
        guard !workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers { center.removeObserver(observer) }
        workspaceObservers.removeAll()
    }

    /// Throttle TCC's synchronous preflight off-main; concurrent ticks reuse the last verdict.
    /// Completion is applied on MainActor; one check is allowed at a time.
    private func refreshScreenAccess(immediate: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        guard ChipPanelCapturePolicy.shouldCheckAuthorization(
            now: now, lastCheck: lastAuthorizationCheck,
            interval: authorizationCheckInterval,
            isInFlight: authorizationCheckInFlight,
            force: immediate
        ) else {
            if immediate, authorizationCheckInFlight { authorizationRefreshPending = true }
            return
        }
        authorizationCheckInFlight = true
        let checkGeneration = authorizationCheckGeneration
        Task.detached(priority: .utility) { [weak self] in
            let authorized = WindowThumbnailCapture.isAuthorized
            await MainActor.run {
                guard let self else { return }
                self.authorizationCheckInFlight = false
                self.lastAuthorizationCheck = ProcessInfo.processInfo.systemUptime
                guard ChipPanelCapturePolicy.mayApplyAuthorizationResult(
                    startedGeneration: checkGeneration,
                    currentGeneration: self.authorizationCheckGeneration
                ) else {
                    if self.authorizationRefreshPending {
                        self.authorizationRefreshPending = false
                        self.refreshScreenAccess(immediate: true)
                    }
                    return
                }
                self.applyScreenAccess(authorized)
            }
        }
    }

    private func applyScreenAccess(_ authorized: Bool) {
        let wasAuthorized = screenAccessAuthorized
        screenAccessAuthorized = authorized
        if !authorized {
            if wasAuthorized || !model.thumbnails.isEmpty {
                invalidateCaptureResults()
                model.thumbnails = [:]
            }
        } else if !wasAuthorized, isVisible, model.mode == .preview,
                  !ChipPanelCapturePolicy.isPaused(displayAsleep: displayAsleep,
                                                   systemAsleep: systemAsleep,
                                                   sessionInactive: sessionInactive) {
            captureVisibleWindows()
        }
    }

    private func invalidateCaptureResults() {
        captureGeneration &+= 1
    }

    private func availabilityChanged(displayAsleep display: Bool? = nil, systemAsleep system: Bool? = nil,
                                     sessionInactive inactive: Bool? = nil) {
        let wasPaused = ChipPanelCapturePolicy.isPaused(displayAsleep: displayAsleep,
                                                       systemAsleep: systemAsleep,
                                                       sessionInactive: sessionInactive)
        if let display { displayAsleep = display }
        if let system { systemAsleep = system }
        if let inactive { sessionInactive = inactive }
        let paused = ChipPanelCapturePolicy.isPaused(displayAsleep: displayAsleep,
                                                    systemAsleep: systemAsleep,
                                                    sessionInactive: sessionInactive)
        if paused {
            guard !wasPaused else { return }
            invalidateCaptureResults()
            // Do not trust authorization across sleep or a lock. A check already running
            // started before the transition, so invalidate its result and let the wake path
            // start a fresh check without overlapping TCC calls.
            authorizationCheckGeneration &+= 1
            authorizationRefreshPending = false
            screenAccessAuthorized = false
            lastAuthorizationCheck = -.infinity
            if !model.thumbnails.isEmpty { model.thumbnails = [:] }
            return
        }
        guard wasPaused, isVisible else { return }
        refreshScreenAccess(immediate: true)
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
