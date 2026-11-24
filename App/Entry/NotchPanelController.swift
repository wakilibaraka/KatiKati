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
    /// 51g: one controller per display; the coordinator owns the set.
    let displayID: CGDirectDisplayID
    let design: NotchDesign
    private let model = NotchModel()
    private var cancellables = Set<AnyCancellable>()
    private var eventWork: DispatchWorkItem?
    private var hudExpireWork: DispatchWorkItem?
    private lazy var statusService = SystemStatusService()
    private var metrics = NotchMetrics(closedSize: CGSize(width: NotchGeometry.fallbackNotchWidth, height: NotchGeometry.fallbackHeight), hasHardwareNotch: false)
    private var holdsFeed = false
    private var holdsStatus = false
    // Hover intent: a pure state machine fed from mouse monitors (see `NotchHoverMachine`). The window is
    // never resized by hover itself, so there is no resize → tracking-area → hover feedback loop.
    private var hover = NotchHoverMachine()
    private var gesture = NotchGestureSupport()
    /// 60 Hz poll of `NSEvent.mouseLocation`, alive only while the pointer is near the notch or the
    /// notch is open (the `StripPointerTracker` pattern). Resident global mouse monitors are banned by
    /// the project rules (they route every system mouse event through this process).
    private var hoverTimer: Timer?
    private var tickWork: DispatchWorkItem?
    private var scheduledTickDeadline: Date?
    private var defaultsCoalesceWork: DispatchWorkItem?
    private var lastScreenFrame: CGRect?
    private var shrinkWork: DispatchWorkItem?
    private weak var shelfStore: ShelfStore?
    var theme: () -> NowPlayingTheme = { .auto }
    var onOpenSettings: () -> Void = {}
    private let islandBridge = IslandLiveBridge()
    private var islandStateSubscription: AnyCancellable?
    private var islandOutsideClickMonitor: Any?
    var touchModeSetting: IslandTouchModeSetting = .automatic {
        didSet { guard touchModeSetting != oldValue else { return }; syncDynamicIslandConfiguration() }
    }
    var nonNotchBehavior: IslandNonNotchIdleBehavior = .compactPill {
        didSet { guard nonNotchBehavior != oldValue else { return }; syncDynamicIslandConfiguration() }
    }
    var keylineEnabled: Bool = true {
        didSet { guard keylineEnabled != oldValue else { return }; syncDynamicIslandConfiguration() }
    }
    var skin: LiveIslandSkin = .boring {
        didSet { guard skin != oldValue else { return }; model.skin = skin; syncDynamicIslandConfiguration(); syncModelSizes(); syncWindow(immediate: skin == .dynamicIsland) }
    }

    func bindShelfStore(_ store: ShelfStore) {
        shelfStore = store
        model.shelfStore = store
        islandBridge.bindShelfStore(store)
    }

    init(displayID: CGDirectDisplayID, design: NotchDesign) { self.displayID = displayID; self.design = design }

    private var isWide: Bool { design == .wideBar }

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
        model.islandBridge = islandBridge
        model.shelfStore = shelfStore ?? AppDelegate.shared?.shelfStore
        syncDynamicIslandConfiguration()
        model.collapse = { [weak self] in self?.collapse() }
        model.openSettings = { [weak self] in self?.onOpenSettings() }
        model.requestOpen = { [weak self] in self?.openByClick() }
        syncModelSizes()
        let window = BoringNotchWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        window.acceptsMouseMovedEvents = true
        window.contentView = container(for: NotchIslandView(model: model, metrics: metrics, theme: theme(), wideBar: isWide))
        panel = window
        LiveActivityFeed.shared.retain()
        holdsFeed = true
        statusService.acquire()
        holdsStatus = true
        window.setFrame(windowFrame(on: screen), display: true)
        lastScreenFrame = screen.frame
        window.orderFrontRegardless()
        startBatteryBuddy()

        LiveActivityFeed.shared.$activity.map(\.kind).removeDuplicates().sink { [weak self] _ in self?.activityChanged() }.store(in: &cancellables)
        LiquidAgentHub.shared.$sessions.map(\.isEmpty).removeDuplicates().sink { [weak self] _ in self?.syncWindow() }.store(in: &cancellables)
        statusService.$status.map(\.volume).removeDuplicates().dropFirst()
            .sink { [weak self] volume in
                let icon = volume.isMuted ? "speaker.slash.fill" : (volume.level > 0.66 ? "speaker.wave.3.fill" : (volume.level > 0.33 ? "speaker.wave.2.fill" : "speaker.wave.1.fill"))
                self?.showHardwareHUD(id: "hud.volume", icon: icon, title: volume.isMuted ? "Muted" : "Volume", level: volume.isMuted ? 0 : Double(volume.level))
            }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: Notification.Name("com.katikati.displayBrightnessChanged"))
            .compactMap { $0.object as? Double }
            .sink { [weak self] level in
                self?.showHardwareHUD(id: "hud.brightness", icon: "sun.max.fill", title: "Brightness", level: level)
            }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: Notification.Name("com.katikati.keyboardBrightnessChanged"))
            .compactMap { $0.object as? Double }
            .sink { [weak self] level in
                self?.showHardwareHUD(id: "hud.keyboard", icon: "light.max", title: "Keyboard", level: level)
            }.store(in: &cancellables)
        model.$event.map { $0 != nil }.removeDuplicates().sink { [weak self] _ in self?.syncWindow() }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.screensChanged() }.store(in: &cancellables)
        // The display choice applies live; re-fit only when it actually points at another screen.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                self?.scheduleDefaultsReaction()
            }.store(in: &cancellables)
    }

    private func scheduleDefaultsReaction() {
        defaultsCoalesceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.defaultsCoalesceWork = nil
            let scale = NotchSizePreset.current()
            if scale != self.lastSizeScale {
                self.lastSizeScale = scale
                self.syncModelSizes()
                self.syncWindow(immediate: true)
            }
            guard let screen = self.targetScreen(),
                  NotchDefaultsReaction.shouldRebuildPanelForScreenChange(
                      hasPanel: self.panel != nil,
                      targetScreenFrame: screen.frame,
                      lastKnownScreenFrame: self.lastScreenFrame
                  ) else { return }
            self.lastScreenFrame = screen.frame
            self.panel?.setFrame(self.windowFrame(on: screen), display: true)
            self.screensChanged()
        }
        defaultsCoalesceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private let trackPill = NotchTrackPillController()
    private let batteryPill = NotchTrackPillController()
    private var batteryTimer: Timer?
    private var batteryLow = Set<String>()

    /// 51d: every five minutes, pill any connected Bluetooth device that has just gone low.
    private func startBatteryBuddy() {
        guard batteryTimer == nil else { return }
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in self?.checkBatteries() }
        RunLoop.main.add(timer, forMode: .common)
        batteryTimer = timer
        checkBatteries()
    }

    private func checkBatteries() {
        guard UserDefaults.standard.object(forKey: "com.katikati.notch.batteryBuddy") as? Bool ?? true else { return }
        Task { @MainActor [weak self] in
            let devices = await BluetoothDeviceReader.read()
            guard let self, self.panel != nil else { return }
            let result = BatteryBuddyPolicy.update(alreadyLow: self.batteryLow, devices: devices)
            self.batteryLow = result.low
            if let device = result.alerts.first, !self.model.isExpanded {
                self.batteryPill.show(below: self.model.closedSize.height) { AnyView(NotchBatteryPillView(model: $0, device: device)) }
            }
        }
    }

    private func hide() {
        removeIslandOutsideClickMonitor()
        islandStateSubscription?.cancel()
        islandStateSubscription = nil
        islandBridge.stop()
        trackPill.hide(animated: false)
        batteryPill.hide(animated: false)
        batteryTimer?.invalidate(); batteryTimer = nil
        cancellables.removeAll()
        stopHoverPolling()
        tickWork?.cancel(); tickWork = nil; scheduledTickDeadline = nil
        defaultsCoalesceWork?.cancel(); defaultsCoalesceWork = nil
        lastScreenFrame = nil
        shrinkWork?.cancel(); shrinkWork = nil
        eventWork?.cancel(); eventWork = nil
        hudExpireWork?.cancel(); hudExpireWork = nil
        model.event = nil; model.isOpen = false
        LiveActivityFeed.shared.isNotchExpanded = false
        hover.forceClose()
        panel?.ignoresMouseEvents = true
        panel?.orderOut(nil)
        panel = nil
        if holdsFeed { LiveActivityFeed.shared.release(); holdsFeed = false }
        if holdsStatus { statusService.release(); holdsStatus = false }
    }

    // MARK: LiveEventSink

    func show(_ event: LiveEvent) {
        guard panel != nil else { return }
        if skin == .dynamicIsland {
            islandBridge.show(event)
            return
        }
        // 50d/50e: a new song brightens the ear glow and drops a small pill instead of opening the notch.
        if case .trackChanged = event {
            model.glowBoost = 1
            withAnimation(.easeOut(duration: 1.4)) { model.glowBoost = 0 }
            if !model.isExpanded, UserDefaults.standard.object(forKey: "com.katikati.notch.trackToast") as? Bool ?? true { trackPill.show(below: model.closedSize.height) { AnyView(NotchTrackPillView(model: $0)) } }
            return
        }
        let presentation = LiveEventPresentation(event)
        let now = Date()
        model.activityQueue.enqueue(
            NotchActivityItem(
                id: "event.\(presentation.symbol)",
                priority: .notification,
                title: presentation.headline,
                subtitle: presentation.detail,
                icon: presentation.symbol,
                timeout: NotchMotionSpec.eventLifetime,
                createdAt: now
            ),
            now: now
        )
        scheduleHUDExpiration()
        if !model.isExpanded {
            trackPill.show(below: model.closedSize.height) { AnyView(NotchEventPillView(model: $0, event: presentation)) }
        }
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
        let closedSize = skin == .liquid
            ? CGSize(width: max(model.closedSize.width, metrics.closedSize.width + 132), height: metrics.closedSize.height)
            : model.closedSize
        let closed = NotchGeometry.panelFrame(size: closedSize, in: screen.frame)
        let open = skin == .liquid
            ? NotchGeometry.panelFrame(
                size: CGSize(width: max(model.openSize.width, 480), height: metrics.closedSize.height + 16 + max(model.openSize.height, 220)),
                in: screen.frame
              )
            : NotchGeometry.panelFrame(size: model.openSize, in: screen.frame)
        let inTrigger = NotchHoverZones.trigger(closedFrame: closed).contains(cursor)
        hover.openDelay = NotchBehavior.hoverDelay()
        hover.closeDelay = NotchBehavior.closeDelay()
        // Click mode: hovering never opens it (a click does, via `openByClick`); an open panel still closes on leave.
        let opensOnHover = NotchOpenMode.current() == .hover
        let inKeepOpen = NotchHoverZones.keepOpen(openFrame: open).contains(cursor)
        // A drag that began inside the open panel (volume slider) keeps it open even if the cursor leaves.
        let dragging = hover.isOpen && NSEvent.pressedMouseButtons & 1 != 0
        let wasOpen = hover.isOpen
        hover.update(inTrigger: inTrigger && opensOnHover, inKeepOpen: inKeepOpen, pinned: dragging || model.event != nil || model.isDropTargeted, now: now)
        if hover.isOpen != wasOpen { applyOpenState() }
        // Poll only while it matters: pointer near the notch, open, or a dwell/grace timer pending.
        if !hover.isOpen, !inTrigger, hover.nextDeadline == nil { stopHoverPolling() }
        scheduleTick()
    }

    /// Wake the machine at its next deadline even if the cursor stops moving (dwell to open / grace to close).
    private func scheduleTick() {
        guard let deadline = hover.nextDeadline else {
            tickWork?.cancel(); tickWork = nil; scheduledTickDeadline = nil
            return
        }
        if tickWork != nil,
           NotchDefaultsReaction.shouldKeepScheduledTick(scheduled: scheduledTickDeadline, wanted: deadline) {
            return
        }
        tickWork?.cancel(); tickWork = nil
        let work = DispatchWorkItem { [weak self] in
            self?.tickWork = nil
            self?.scheduledTickDeadline = nil
            self?.evaluateHover()
        }
        tickWork = work
        scheduledTickDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, deadline.timeIntervalSinceNow + 0.005), execute: work)
    }

    private func applyOpenState() {
        if hover.isOpen && !model.isOpen {
            if NotchBehavior.haptic() { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
            let nowPlaying = LiveActivityFeed.shared.activity.kind == .music
            let d = UserDefaults.standard
            let wanted = NotchPagingPolicy.defaultPage(
                nowPlayingActive: nowPlaying,
                aiTurnActive: AgentUsageService.shared.snapshot.activeTurn != nil,
                userPinnedPage: NotchPagingPolicy.storedPinnedPage(d)
            )
            // 51c: a hidden default page falls back to the first shown one.
            let shown = NotchPage.visible(teleprompter: NotchPage.isEnabled(TeleprompterModel.enabledKey, in: d),
                                          mirror: NotchPage.isEnabled(CameraMirrorService.enabledKey, in: d))
            model.activePage = shown.contains(wanted) ? wanted : (shown.first ?? .audioDeck)
        }
        // Grow the NSPanel synchronously *before* flipping `model.isOpen = true`, so SwiftUI's open
        // spring never runs inside the 32 pt closed window (which caused top-half vertical clipping).
        if hover.isOpen, let panel, let screen = targetScreen() {
            shrinkWork?.cancel(); shrinkWork = nil
            panel.setFrame(windowFrame(on: screen, expanded: true), display: true)
        }
        model.isOpen = hover.isOpen
        LiveActivityFeed.shared.isNotchExpanded = model.isExpanded
        if !hover.isOpen { syncWindow() }
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

    private func openByClick() {
        guard panel != nil else { return }
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
        NSScreen.screens.first { $0.displayID == displayID }
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
        lastScreenFrame = screen.frame
        metrics = Self.metrics(for: screen)
        syncModelSizes()
        panel?.contentView = container(for: NotchIslandView(model: model, metrics: metrics, theme: theme(), wideBar: isWide))
        syncWindow(immediate: true)
    }

    private func activityChanged() {
        syncModelSizes()
        syncWindow()
    }

    /// Shape sizes the view animates between.
    private var lastSizeScale = NotchSizePreset.current()

    private func syncModelSizes() {
        // Always wide: when nothing is live the two sides carry the dock chips (storage left, battery right).
        let showsActivity = true
        let screenWidth = targetScreen()?.frame.width ?? 1440
        let base = NotchGeometry.openSize(for: skin)
        let scaled = CGSize(width: base.width * NotchSizePreset.current(), height: base.height * NotchSizePreset.current())
        model.openSize = NotchLayoutSpec.fit(scaled, screenWidth: screenWidth, closedWidth: metrics.closedSize.width)
        // The wide bar is as wide as the open panel (so the user's size preset sets both and opening only
        // grows downward); the notch capsule keeps its own width.
        model.closedSize = isWide
            ? CGSize(width: model.openSize.width, height: metrics.closedSize.height)
            : NotchGeometry.closedCapsuleSize(metrics, showsActivity: showsActivity)
    }

    private func showHardwareHUD(id: String, icon: String, title: String, level: Double) {
        guard panel != nil else { return }
        let now = Date()
        let item = NotchActivityItem(
            id: id,
            priority: .systemInfo,
            title: title,
            icon: icon,
            timeout: 1.5,
            level: level,
            createdAt: now
        )
        model.activityQueue.enqueue(item, now: now)
        syncWindow()
        scheduleHUDExpiration()
    }

    private func scheduleHUDExpiration() {
        hudExpireWork?.cancel(); hudExpireWork = nil
        let now = Date()
        guard let next = model.activityQueue.nextExpirationDate(after: now) else { return }
        let delay = max(0.05, next.timeIntervalSince(now) + 0.02)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.model.activityQueue.pruneExpired(at: Date())
            self.syncWindow()
            self.scheduleHUDExpiration()
        }
        hudExpireWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private var hasCompactLiquidActivity: Bool {
        let nowPlaying = LiveActivityFeed.shared.nowPlayingState
        let hasMusic = !(nowPlaying.title ?? "").isEmpty || LiveActivityFeed.shared.activity.kind == .music
        return hasMusic
            || LiveActivityFeed.shared.activity.kind != .clock
            || model.activeHUDItem != nil
            || model.event != nil
            || !LiquidAgentHub.shared.sessions.isEmpty
    }

    /// The window is as large as the larger of the shapes involved: it grows at once (so the shape never
    /// clips while it animates open) and shrinks only after the close spring has finished.
    private func windowFrame(on screen: NSScreen, expanded: Bool? = nil) -> CGRect {
        let islandExpanded = skin == .dynamicIsland && islandBridge.driver.scene.presentation == .expanded
        let isExpanded = (expanded ?? model.isExpanded) || islandExpanded
        return NotchGeometry.stageFrame(
            for: skin,
            isExpanded: isExpanded,
            isWide: isWide,
            metrics: metrics,
            closedSize: model.closedSize,
            openSize: model.openSize,
            screenBounds: screen.frame,
            topInset: screen.safeAreaInsets.top,
            menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY,
            hasCompactActivity: hasCompactLiquidActivity
        )
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
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if panel != nil, mods == [.option], !SurfaceTimeTravelCoordinator.shared.buffer.entries.isEmpty {
            if event.phase == .ended || event.phase == .cancelled {
                SurfaceTimeTravelCoordinator.shared.resetScrollAccumulator()
            } else if let preview = SurfaceTimeTravelCoordinator.shared.scrub(
                deltaY: event.scrollingDeltaY,
                hasPreciseDeltas: event.hasPreciseScrollingDeltas
            ) {
                let entry = preview.entry
                let label = "\(entry.title) (\(preview.index)/\(preview.total))"
                let level = Double(preview.index) / Double(max(1, preview.total))
                showHardwareHUD(id: "notch.timeTravel", icon: entry.icon, title: label, level: level)
            }
            return true
        }
        SurfaceTimeTravelCoordinator.shared.resetScrollAccumulator()
        guard panel != nil, mods.isEmpty else {
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

    private func syncDynamicIslandConfiguration() {
        guard skin == .dynamicIsland else {
            islandBridge.stop()
            islandStateSubscription?.cancel()
            islandStateSubscription = nil
            removeIslandOutsideClickMonitor()
            panel?.ignoresMouseEvents = false
            return
        }
        if panel != nil {
            islandBridge.start()
        }
        guard let screen = targetScreen() else { return }
        let topology = ScreenTouchCapabilities.resolveTopology(for: screen)
        let touchEnabled = ScreenTouchCapabilities.isTouchModeActive(for: screen, setting: touchModeSetting)
        let driver = islandBridge.driver
        driver.keylineSetting = topology.keylineSetting(userEnabled: keylineEnabled)
        driver.stageWidth = max(560, Double(model.openSize.width + 64))
        driver.updateDisplayTopology(topology, touchEnabled: touchEnabled, nonNotchBehavior: nonNotchBehavior)
        syncDynamicIslandPanelInteraction()

        if islandStateSubscription == nil {
            islandStateSubscription = driver.$scene
                .combineLatest(driver.$snapshot)
                .receive(on: RunLoop.main)
                .sink { [weak self] scene, _ in
                    guard let self else { return }
                    self.syncDynamicIslandPanelInteraction()
                    self.syncWindow(immediate: scene.presentation == .expanded)
                    if scene.presentation == .expanded {
                        self.installIslandOutsideClickMonitor()
                    } else {
                        self.removeIslandOutsideClickMonitor()
                    }
                }
        }
    }

    private func syncDynamicIslandPanelInteraction() {
        guard skin == .dynamicIsland else {
            panel?.ignoresMouseEvents = false
            return
        }
        let driver = islandBridge.driver
        let hidesAtRest = driver.topology.hidesAtRest(
            activeCount: driver.snapshot.activities.count,
            nonNotchBehavior: driver.nonNotchIdleBehavior
        ) && driver.scene.presentation == .idle
        if panel?.ignoresMouseEvents != hidesAtRest {
            panel?.ignoresMouseEvents = hidesAtRest
        }
    }

    private func installIslandOutsideClickMonitor() {
        guard islandOutsideClickMonitor == nil else { return }
        islandOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.skin == .dynamicIsland, self.islandBridge.driver.scene.presentation == .expanded else { return }
                let loc = NSEvent.mouseLocation
                guard let panelFrame = self.panel?.frame else {
                    self.islandBridge.driver.store.collapse()
                    return
                }
                if !panelFrame.contains(loc) {
                    self.islandBridge.driver.store.collapse()
                }
            }
        }
    }

    private func removeIslandOutsideClickMonitor() {
        if let monitor = islandOutsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            islandOutsideClickMonitor = nil
        }
    }

    /// The hosting view lives inside a plain autoresizing container so SwiftUI's intrinsic size can never
    /// drive the panel (that fed back into window sizing during an update-constraints pass and crashed).
    /// The container also owns the tracking area whose *enter* starts the hover poll.
    private func container<V: View>(for view: V) -> NSView {
        let container = NotchTrackingContainer(frame: .zero)
        container.onEnter = { [weak self] in
            guard let self, self.skin != .dynamicIsland else { return }
            self.startHoverPolling()
        }
        container.onScroll = { [weak self] event in
            guard let self, self.skin != .dynamicIsland else { return false }
            return self.handleScroll(event)
        }
        container.shouldAcceptHit = { [weak self, weak container] point in
            guard let self, let container else { return true }
            if self.skin == .liquid {
                let topDownY = container.bounds.height - point.y
                let centerX = container.bounds.width / 2
                if self.model.isExpanded {
                    return topDownY <= self.metrics.closedSize.height + 20 + max(self.model.openSize.height, 220) + 12
                        && abs(point.x - centerX) <= max(self.model.openSize.width, 480) / 2 + 16
                }
                return topDownY <= self.metrics.closedSize.height + 18
                    && abs(point.x - centerX) <= (self.metrics.closedSize.width / 2 + 96)
            }
            guard self.skin == .dynamicIsland else { return true }
            let driver = self.islandBridge.driver
            let frame = driver.frame
            let topDownY = container.bounds.height - point.y
            let p = CGPoint(x: point.x, y: topDownY)
            if driver.scene.presentation == .expanded {
                let expandedRect = frame.drawn.rect.insetBy(dx: -8, dy: -8)
                return expandedRect.contains(p)
            }
            if driver.topology.hidesAtRest(activeCount: driver.snapshot.activities.count, nonNotchBehavior: driver.nonNotchIdleBehavior),
               driver.scene.presentation == .idle {
                return false
            }
            let pillHit = IslandTouchHitPolicy.interactiveHitRect(for: frame.pill.rect, touchEnabled: driver.touchMode)
            if pillHit.contains(p) { return true }
            if frame.bubble.width > 0 {
                let bubbleHit = IslandTouchHitPolicy.interactiveHitRect(for: frame.bubble.rect, touchEnabled: driver.touchMode)
                if bubbleHit.contains(p) { return true }
            }
            return false
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
    var shouldAcceptHit: ((CGPoint) -> Bool)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let shouldAcceptHit, !shouldAcceptHit(point) {
            return nil
        }
        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onEnter() }
    override func mouseMoved(with event: NSEvent) { onEnter() }

    override func scrollWheel(with event: NSEvent) {
        if onScroll?(event) == true {
            return
        }
        super.scrollWheel(with: event)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// 51g: keeps one `NotchPanelController` per display whose `NotchDesign` is not `.off`, rebuilt when
/// displays or the per-display choice change. Events fan out to every panel; shortcuts act on the
/// panel under the pointer.
@MainActor
final class NotchPanelCoordinator: LiveEventSink {
    private var controllers: [CGDirectDisplayID: NotchPanelController] = [:]
    private var designs: [CGDirectDisplayID: NotchDesign] = [:]
    private var enabled = false
    private var observers = Set<AnyCancellable>()
    var theme: () -> NowPlayingTheme = { .auto } { didSet { controllers.values.forEach { $0.theme = theme } } }
    var onOpenSettings: () -> Void = {} { didSet { controllers.values.forEach { $0.onOpenSettings = onOpenSettings } } }
    var skin: LiveIslandSkin = .liquid { didSet { reconcile() } }
    var touchModeSetting: IslandTouchModeSetting = .automatic { didSet { controllers.values.forEach { $0.touchModeSetting = touchModeSetting } } }
    var nonNotchBehavior: IslandNonNotchIdleBehavior = .compactPill { didSet { controllers.values.forEach { $0.nonNotchBehavior = nonNotchBehavior } } }
    var keylineEnabled: Bool = true { didSet { controllers.values.forEach { $0.keylineEnabled = keylineEnabled } } }
    private weak var shelfStore: ShelfStore?

    func bindShelfStore(_ store: ShelfStore) {
        shelfStore = store
        controllers.values.forEach { $0.bindShelfStore(store) }
    }

    var isUsable: Bool { controllers.values.contains { $0.isUsable } }

    func setEnabled(_ on: Bool) {
        enabled = on
        observers.removeAll()
        if on {
            let names: [Notification.Name] = [NSApplication.didChangeScreenParametersNotification, UserDefaults.didChangeNotification]
            names.forEach { name in NotificationCenter.default.publisher(for: name).sink { [weak self] _ in self?.reconcile() }.store(in: &observers) }
        }
        reconcile()
    }

    /// shortcut: `reconcile` runs on every UserDefaults change (cheap dictionary diff), fine until a hot key writes defaults per frame.
    private func reconcile() {
        var wanted: [CGDirectDisplayID: NotchDesign] = [:]
        if enabled {
            let stored = NotchDesign.stored()
            for screen in NSScreen.screens {
                guard let id = screen.displayID else { continue }
                let design = NotchDesign.resolve(
                    display: String(id),
                    displayUUID: DisplayIdentity.uuidString(for: screen),
                    hasHardwareNotch: screen.safeAreaInsets.top > 0,
                    stored: stored
                )
                if design != .off { wanted[id] = design }
            }
        }
        for (id, c) in controllers where wanted[id] != designs[id] { c.setEnabled(false); controllers[id] = nil }
        designs = wanted
        let storedSkins = NotchDisplaySkin.stored()
        for (id, design) in wanted {
            let screen = NSScreen.screens.first { $0.displayID == id }
            let displaySkin = NotchDisplaySkin.resolve(
                display: String(id),
                displayUUID: screen.flatMap { DisplayIdentity.uuidString(for: $0) },
                fallback: skin,
                stored: storedSkins
            )
            if let existing = controllers[id] {
                if existing.skin != displaySkin { existing.skin = displaySkin }
                continue
            }
            let c = NotchPanelController(displayID: id, design: design)
            c.theme = theme; c.onOpenSettings = onOpenSettings; c.skin = displaySkin
            c.touchModeSetting = touchModeSetting
            c.nonNotchBehavior = nonNotchBehavior
            c.keylineEnabled = keylineEnabled
            if let shelfStore { c.bindShelfStore(shelfStore) }
            controllers[id] = c
            c.setEnabled(true)
        }
    }

    func show(_ event: LiveEvent) { controllers.values.forEach { $0.show(event) } }

    private var underPointer: NotchPanelController? {
        let p = NSEvent.mouseLocation
        let id = NSScreen.screens.first { $0.frame.contains(p) }?.displayID
        return id.flatMap { controllers[$0] } ?? controllers.values.first
    }

    func toggleTools() { underPointer?.toggleTools() }
    func stepPage(forward: Bool) { underPointer?.stepPage(forward: forward) }
}
