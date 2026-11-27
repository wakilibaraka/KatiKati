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
    /// MD-3: both are re-targetable so a clamshell handover can move this controller to another
    /// display (open state and page intact) instead of tearing it down.
    private(set) var displayID: CGDirectDisplayID
    private(set) var design: NotchDesign
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
    private var pendingShrink: (frame: CGRect, work: DispatchWorkItem)?
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
        didSet { guard skin != oldValue else { return }; model.skin = skin; syncModelSizes(); syncDynamicIslandConfiguration(); syncWindow(immediate: true) }
    }

    func bindShelfStore(_ store: ShelfStore) {
        shelfStore = store
        model.shelfStore = store
        islandBridge.bindShelfStore(store)
    }

    init(displayID: CGDirectDisplayID, design: NotchDesign) { self.displayID = displayID; self.design = design }

    /// MD-3: move this island to another display without rebuilding it. `screensChanged()` re-reads
    /// the new screen's metrics and re-frames the panel, so an open island survives the lid closing.
    func retarget(displayID: CGDirectDisplayID, design: NotchDesign) {
        guard displayID != self.displayID || design != self.design else { return }
        trackPill.hide(animated: false)
        batteryPill.hide(animated: false)
        self.displayID = displayID
        self.design = design
        screensChanged()
    }

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
        islandBridge.onOpenAudioDeck = { [weak self] in self?.openPage(.audioDeck) }
        model.collapse = { [weak self] in self?.collapse() }
        model.openSettings = { [weak self] in self?.onOpenSettings() }
        model.requestOpen = { [weak self] in self?.openByClick() }
        model.requestShelf = { [weak self] in self?.openPage(.shelf) }
        model.stageDraggedItems = { [weak self] in self?.stageDrop(NSPasteboard(name: .drag)) ?? false }
        syncModelSizes()
        syncDynamicIslandConfiguration()
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
                guard let self, Date().timeIntervalSince(self.lastTapVolumeAt) > 0.25 else { return }
                let icon = volume.isMuted ? "speaker.slash.fill" : (volume.level > 0.66 ? "speaker.wave.3.fill" : (volume.level > 0.33 ? "speaker.wave.2.fill" : "speaker.wave.1.fill"))
                self.showHardwareHUD(id: "hud.volume", icon: icon, title: volume.isMuted ? "Muted" : "Volume", level: volume.isMuted ? 0 : Double(volume.level))
            }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: HardwareHUDTakeoverService.volumeKeyHUDNotification)
            .sink { [weak self] note in
                guard let self, let level = note.userInfo?["level"] as? Double else { return }
                let muted = note.userInfo?["muted"] as? Bool ?? false
                self.lastTapVolumeAt = Date()
                let icon = muted ? "speaker.slash.fill" : (level > 0.66 ? "speaker.wave.3.fill" : (level > 0.33 ? "speaker.wave.2.fill" : "speaker.wave.1.fill"))
                self.showHardwareHUD(id: "hud.volume", icon: icon, title: muted ? "Muted" : "Volume", level: muted ? 0 : level)
            }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: Notification.Name("com.katikati.displayBrightnessChanged"))
            .sink { [weak self] note in
                guard let self, let level = note.object as? Double,
                      note.userInfo?["displayID"] as? CGDirectDisplayID == self.displayID else { return }
                self.showHardwareHUD(id: "hud.brightness", icon: "sun.max.fill", title: "Brightness", level: level)
            }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: Notification.Name("com.katikati.keyboardBrightnessChanged"))
            .compactMap { $0.object as? Double }
            .sink { [weak self] level in
                self?.showHardwareHUD(id: "hud.keyboard", icon: "light.max", title: "Keyboard", level: level)
            }.store(in: &cancellables)
        AgentUsageService.shared.$snapshot
            .map(\.limits)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] limits in
                self?.handleAIUsageLimits(limits)
            }.store(in: &cancellables)
        model.$event.map { $0 != nil }.removeDuplicates().sink { [weak self] _ in self?.syncWindow() }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.screensChanged() }.store(in: &cancellables)
        // AT-4: entering native fullscreen creates a Space, and switching apps can reveal a
        // fullscreen video. Both are events the island already knows how to answer; no polling.
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncDynamicIslandPanelInteraction() }.store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncDynamicIslandPanelInteraction() }.store(in: &cancellables)
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
                self.syncDynamicIslandConfiguration()
                self.syncWindow(immediate: true)
            }
            let driver = self.islandBridge.driver
            let nextGlass = IslandSurfaceGlassPolicy.isLiquidGlassEnabled()
            let nextMorph = IslandSurfaceGlassPolicy.isMetalMorphOptIn()
            if driver.glassEnabled != nextGlass { driver.glassEnabled = nextGlass }
            if driver.metalMorphOptIn != nextMorph { driver.metalMorphOptIn = nextMorph }
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
    private var holdsDevicesFeed = false
    private var lastTapVolumeAt: Date = .distantPast
    private var usageThresholdPolicy = UsageThresholdPolicy()

    /// 51d + F1: subscribe to the shared peripheral feed instead of spawning a second 300 s poll.
    private func startBatteryBuddy() {
        guard !holdsDevicesFeed else { return }
        DockDevicesFeed.shared.retain()
        holdsDevicesFeed = true
        DockDevicesFeed.shared.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handlePeripheralEvent(event)
            }
            .store(in: &cancellables)
    }

    private func handlePeripheralEvent(_ event: PeripheralEvent) {
        guard panel != nil else { return }
        switch event {
        case let .low(device):
            guard UserDefaults.standard.object(forKey: "com.katikati.notch.batteryBuddy") as? Bool ?? true else { return }
            if skin.usesIslandSurfaceEngine {
                if islandBridge.driver.scene.presentation != .expanded {
                    islandBridge.showBluetoothAccessoryHUD(device: device, isLowBattery: true)
                }
            } else if !model.isExpanded, let frame = panel?.frame {
                batteryPill.show(below: frame) { AnyView(NotchBatteryPillView(model: $0, device: device)) }
            }
        case .connected, .disconnected:
            guard UserDefaults.standard.object(forKey: "com.katikati.notch.peripheralConnect") as? Bool ?? true else { return }
            if skin.usesIslandSurfaceEngine {
                if islandBridge.driver.scene.presentation != .expanded {
                    islandBridge.showPeripheralEvent(event)
                }
            } else if !model.isExpanded, let frame = panel?.frame {
                batteryPill.show(below: frame) { AnyView(NotchPeripheralPillView(model: $0, event: event)) }
            }
        }
    }

    private func handleAIUsageLimits(_ limits: [AgentProvider: AgentLimits]) {
        guard panel != nil,
              UserDefaults.standard.object(forKey: "com.katikati.notch.aiUsageAlerts") as? Bool ?? true else {
            return
        }
        let alerts = usageThresholdPolicy.evaluate(limits: limits)
        guard let top = alerts.max(by: { $0.usedPercent < $1.usedPercent }) else { return }
        if skin.usesIslandSurfaceEngine {
            if islandBridge.driver.scene.presentation != .expanded {
                islandBridge.showAIUsageAlert(top) { [weak self] in
                    self?.openPage(.aiTracker)
                }
            }
        } else {
            let now = Date()
            let item = NotchActivityItem(
                id: "ai.usage.\(top.provider.rawValue)",
                priority: top.severity == .critical ? .critical : .notification,
                title: "\(top.provider.displayName) \(top.usedPercent)%",
                subtitle: top.severity == .critical ? String(localized: "Quota Critical") : String(localized: "Session Quota"),
                icon: top.provider.symbol,
                timeout: 4.5,
                level: Double(top.usedPercent) / 100.0,
                createdAt: now
            )
            model.activityQueue.enqueue(item, now: now)
        }
    }

    private func hide() {
        removeIslandOutsideClickMonitor()
        islandStateSubscription?.cancel()
        islandStateSubscription = nil
        islandBridge.stop()
        trackPill.hide(animated: false)
        batteryPill.hide(animated: false)
        if holdsDevicesFeed {
            DockDevicesFeed.shared.release()
            holdsDevicesFeed = false
        }
        cancellables.removeAll()
        stopHoverPolling()
        tickWork?.cancel(); tickWork = nil; scheduledTickDeadline = nil
        defaultsCoalesceWork?.cancel(); defaultsCoalesceWork = nil
        lastScreenFrame = nil
        pendingShrink?.work.cancel(); pendingShrink = nil
        eventWork?.cancel(); eventWork = nil
        hudExpireWork?.cancel(); hudExpireWork = nil
        model.isDropTargeted = false
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
        guard let panel else { return }
        if case .trackChanged = event {
            model.glowBoost = 1
            withAnimation(.easeOut(duration: 1.4)) { model.glowBoost = 0 }
        }
        if skin.usesIslandSurfaceEngine {
            islandBridge.show(event) { [weak self] in self?.openDetails(for: event) }
            return
        }
        // 50d/50e: a new song brightens the ear glow and drops a small pill instead of opening the notch.
        if case .trackChanged = event {
            if !model.isExpanded, UserDefaults.standard.object(forKey: "com.katikati.notch.trackToast") as? Bool ?? true {
                trackPill.show(below: panel.frame) { AnyView(NotchTrackPillView(model: $0)) }
            }
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
        let anchor = targetScreen().map { windowFrame(on: $0, expanded: false) } ?? panel.frame
        trackPill.show(below: model.isExpanded ? panel.frame : anchor) { pill in
            AnyView(NotchEventPillView(model: pill, event: presentation) { [weak self] in
                self?.openDetails(for: event)
            })
        }
    }

    private func openDetails(for event: LiveEvent) {
        switch event {
        case .trackChanged: openPage(.audioDeck)
        case .focusPhaseChanged, .focusCycleCompleted, .timerFinished, .stopwatchStopped:
            openPage(.studioHub)
        case .countdownReachedToday, .alarmDue: openPage(.calendar)
        case .clipboardCopied, .clipboardPasted: AppDelegate.shared?.showSideDeck(.clipboard)
        case .downloadFinished: AppDelegate.shared?.showSideDeck(.downloads)
        case .severeWeather: AppDelegate.shared?.showSideDeck(.weather)
        case .notice(.batteryHigh, _), .notice(.batteryFull, _): openPage(.peripherals)
        case .notice: AppDelegate.shared?.showSideDeck(.notifications)
        }
    }

    private func openPage(_ page: NotchPage) {
        if skin.usesIslandSurfaceEngine {
            model.goToPage(page)
            hover.forceOpen()
            model.isOpen = true
            islandBridge.openPages()
            startHoverPolling()
        } else {
            openByClick()
            model.goToPage(page)
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
        let closed: CGRect
        let open: CGRect
        if skin.usesIslandSurfaceEngine {
            let closedStage = windowFrame(on: screen, expanded: false)
            let pill = islandBridge.driver.frame.pill
            closed = pill.width > 1
                ? CGRect(
                    x: closedStage.minX + pill.x,
                    y: closedStage.maxY - pill.y - pill.height,
                    width: max(pill.width, model.closedSize.width),
                    height: max(pill.height, metrics.closedSize.height)
                )
                : closedStage
            open = windowFrame(on: screen, expanded: true)
        } else if skin == .liquid {
            let closedSize = CGSize(width: max(model.closedSize.width, metrics.closedSize.width + 132), height: metrics.closedSize.height)
            closed = NotchGeometry.panelFrame(size: closedSize, in: screen.frame)
            open = NotchGeometry.panelFrame(
                size: CGSize(width: max(model.openSize.width, 480), height: metrics.closedSize.height + 16 + max(model.openSize.height, 220)),
                in: screen.frame
            )
        } else {
            closed = windowFrame(on: screen, expanded: false)
            open = windowFrame(on: screen, expanded: true)
        }
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
            let d = UserDefaults.standard
            let wanted = NotchPagingPolicy.defaultPage(
                aiTurnActive: AgentUsageService.shared.snapshot.activeTurn != nil,
                userPinnedPage: NotchPagingPolicy.storedPinnedPage(d),
                usesBoringHome: skin.opensDirectlyToBentoSuite
            )
            let shown = NotchPage.visible(teleprompter: NotchPage.isEnabled(TeleprompterModel.enabledKey, in: d),
                                          mirror: NotchPage.isEnabled(CameraMirrorService.enabledKey, in: d))
            model.activePage = shown.contains(wanted.navigationPage) ? wanted : (shown.first ?? .home)
        }
        // Grow the NSPanel synchronously *before* flipping `model.isOpen = true`, so SwiftUI's open
        // spring never runs inside the 32 pt closed window (which caused top-half vertical clipping).
        if hover.isOpen, let panel, let screen = targetScreen() {
            trackPill.hide(animated: true)
            batteryPill.hide(animated: true)
            pendingShrink?.work.cancel(); pendingShrink = nil
            panel.setFrame(windowFrame(on: screen, expanded: true), display: false)
        }
        model.isOpen = hover.isOpen
        if skin.usesIslandSurfaceEngine {
            if hover.isOpen {
                if skin.opensDirectlyToBentoSuite || islandBridge.driver.snapshot.activities.isEmpty {
                    islandBridge.openPages()
                } else {
                    islandBridge.driver.store.expand()
                }
                panel?.contentView?.needsDisplay = true
            } else {
                islandBridge.driver.store.collapse()
            }
        }
        LiveActivityFeed.shared.isNotchExpanded = model.isExpanded
        if !hover.isOpen { syncWindow() }
    }

    /// Shortcut paging: open the notch if closed, then step one page (the dots' mouse-only gap).
    func stepPage(forward: Bool) {
        guard panel != nil else { return }
        hover.forceOpen()
        model.isOpen = true
        model.stepPage(forward: forward)
        if skin.usesIslandSurfaceEngine {
            islandBridge.openPages()
        } else {
            applyOpenState()
        }
        startHoverPolling()
    }

    /// Phase 9d shortcut: open the notch on its Tools tab, or close it if it is already showing it.
    func toggleTools() {
        guard panel != nil else { return }
        let expanded = model.isOpen || (skin.usesIslandSurfaceEngine && islandBridge.driver.snapshot.expanded != nil)
        if expanded, model.activePage == .studioHub { collapse(); return }
        openPage(.studioHub)
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
        if skin.usesIslandSurfaceEngine {
            islandBridge.driver.store.collapse()
        }
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
        syncDynamicIslandConfiguration()
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
        if skin.usesIslandSurfaceEngine {
            let onScrub: ((Double) -> Void)?
            switch id {
            case "hud.volume":
                onScrub = { [weak self] next in _ = self?.statusService.setVolume(Float(next)) }
            case "hud.brightness":
                onScrub = { [weak self] next in
                    guard let self, let screen = self.targetScreen() else { return }
                    DisplayBrightness.shared.set(next, for: screen)
                }
            default:
                onScrub = nil
            }
            islandBridge.showHardwareHUD(id: id, icon: icon, title: title, level: level, onScrub: onScrub)
            return
        }
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
        let islandExpanded = skin.usesIslandSurfaceEngine && islandBridge.driver.scene.presentation == .expanded
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
            if self.pendingShrink?.frame == target, !immediate { return }
            self.pendingShrink?.work.cancel()
            self.pendingShrink = nil
            guard target != panel.frame else { return }
            let grows = target.width >= panel.frame.width && target.height >= panel.frame.height
            if grows || immediate {
                panel.setFrame(target, display: true)
            } else {
                let work = DispatchWorkItem { [weak self] in
                    guard let self, let panel = self.panel, let screen = self.targetScreen() else { return }
                    self.pendingShrink = nil
                    panel.setFrame(self.windowFrame(on: screen), display: true)
                }
                self.pendingShrink = (target, work)
                let style = NotchOpenAnimation(rawValue: UserDefaults.standard.string(forKey: NotchOpenAnimation.defaultsKey) ?? "") ?? .boring
                let duration = self.skin == .liquid || self.skin == .dynamicIsland ? 0.55 : style.closeSpring.response + 0.10
                DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
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

        let horizontalMode: NotchGestureSupport.HorizontalMode = model.activePage == .audioDeck ? .trackSkip : .pageNavigation

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
        if panel != nil && skin.usesIslandSurfaceEngine {
            islandBridge.start()
        } else {
            islandBridge.stop()
            removeIslandOutsideClickMonitor()
        }
        guard let screen = targetScreen() else { return }
        let topology = ScreenTouchCapabilities.resolveTopology(for: screen)
        let touchEnabled = ScreenTouchCapabilities.isTouchModeActive(for: screen, setting: touchModeSetting)
        let driver = islandBridge.driver
        driver.keylineSetting = topology.keylineSetting(userEnabled: keylineEnabled)
        driver.glassEnabled = IslandSurfaceGlassPolicy.isLiquidGlassEnabled()
        driver.metalMorphOptIn = IslandSurfaceGlassPolicy.isMetalMorphOptIn()
        driver.stageWidth = max(560, Double(model.openSize.width + 64))
        driver.applySkinAndSize(skin: skin, openSize: model.openSize, isWide: isWide)
        driver.updateDisplayTopology(topology, touchEnabled: touchEnabled, nonNotchBehavior: nonNotchBehavior)
        syncDynamicIslandPanelInteraction()

        if skin.usesIslandSurfaceEngine, islandStateSubscription == nil {
            islandStateSubscription = driver.$scene
                .combineLatest(driver.$snapshot)
                .receive(on: RunLoop.main)
                .sink { [weak self] scene, snapshot in
                    guard let self, self.skin.usesIslandSurfaceEngine else { return }
                    self.syncDynamicIslandPanelInteraction()
                    self.syncWindow(immediate: scene.presentation == .expanded)
                    if scene.presentation == .expanded {
                        if snapshot.expanded?.reason == .user, !self.hover.isOpen {
                            self.hover.forceOpen()
                            self.model.isOpen = true
                            LiveActivityFeed.shared.isNotchExpanded = true
                            self.startHoverPolling()
                        }
                        self.installIslandOutsideClickMonitor()
                    } else {
                        if self.hover.isOpen {
                            self.hover.forceClose()
                            self.model.isOpen = false
                            LiveActivityFeed.shared.isNotchExpanded = false
                        }
                        self.islandBridge.removePagesPlaceholder()
                        self.removeIslandOutsideClickMonitor()
                    }
                }
        }
    }

    private func syncDynamicIslandPanelInteraction() {
        guard skin.usesIslandSurfaceEngine else {
            panel?.ignoresMouseEvents = false
            return
        }
        let driver = islandBridge.driver
        let mediaHidden = mediaWantsIslandHidden() && driver.scene.presentation == .idle
        let hidesAtRest = (driver.topology.hidesAtRest(
            activeCount: driver.snapshot.activities.count,
            nonNotchBehavior: driver.nonNotchIdleBehavior
        ) || mediaHidden) && driver.scene.presentation == .idle
        if panel?.ignoresMouseEvents != hidesAtRest {
            panel?.ignoresMouseEvents = hidesAtRest
        }
        // A media fullscreen on a notchless display actually takes the island away; the rest state
        // only needs to stop taking clicks, but a video should not have a capsule in front of it.
        let alpha: CGFloat = mediaHidden ? 0 : 1
        if let panel, panel.alphaValue != alpha { panel.alphaValue = alpha }
    }

    /// AT-4: a playing video in a watching app, fullscreen, on a display without a notch. Reads the
    /// profile for this display, then one WindowServer list; nothing runs when the display has a
    /// hardware notch or the frontmost app is not media.
    private func mediaWantsIslandHidden() -> Bool {
        guard DisplayProfiles.isEnabled(),
              let app = NSWorkspace.shared.frontmostApplication,
              let bundle = app.bundleIdentifier,
              AppRuleCategory.media.matches(bundleID: bundle) else { return false }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return false }

        // The media window can be fullscreen on any display, not the one the island sits on: a
        // video fullscreen on the 4K is exactly the case that should clear the built-in's island.
        // Each notchless display with the media window covering it decides from its own profile.
        for screen in NSScreen.screens where screen.safeAreaInsets.top == 0 {
            let covers = list.contains { info in
                guard (info[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier,
                      (info[kCGWindowLayer as String] as? Int) == 0,
                      let dict = info[kCGWindowBounds as String] as? [String: Any],
                      let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return false }
                // A native-fullscreen window is the one that covers the display exactly.
                return abs(bounds.width - screen.frame.width) <= 2 && abs(bounds.height - screen.frame.height) <= 2
            }
            guard covers else { continue }
            let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let role = DisplayRole.resolve(isBuiltin: CGDisplayIsBuiltin(CGDirectDisplayID(number)) != 0)
            let profile = DisplayProfiles.resolve(
                key: DisplayIdentity.uuidString(for: screen) ?? screen.localizedName,
                name: screen.localizedName,
                role: role,
                profiles: DisplayProfiles.stored()
            )
            if profile.hideIslandForMedia { return true }
        }
        return false
    }

    private func installIslandOutsideClickMonitor() {
        guard islandOutsideClickMonitor == nil else { return }
        islandOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.skin.usesIslandSurfaceEngine, self.islandBridge.driver.scene.presentation == .expanded else { return }
                let loc = NSEvent.mouseLocation
                guard let panelFrame = self.panel?.frame else {
                    self.collapse()
                    return
                }
                if !panelFrame.contains(loc) {
                    self.collapse()
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

    private func stageDrop(_ pasteboard: NSPasteboard) -> Bool {
        guard let shelf = model.shelfStore ?? AppDelegate.shared?.shelfStore else { return false }
        let localTray = UserDefaults.standard.object(forKey: ShelfPolicy.syncNotchTrayKey) as? Bool == false
        let files = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
            .filter(\.isFileURL)
        if !files.isEmpty {
            shelf.stash(paths: files.map(\.path))
            if localTray { DroppyFileTrayStore.shared.add(urls: files) }
        } else {
            guard pasteboard.availableType(from: [.fileURL]) == nil else { return false }
            let link = pasteboard.string(forType: .URL).flatMap { URL(string: $0) }
            guard let text = link?.absoluteString ?? pasteboard.string(forType: .string),
                  let saved = shelf.stashText(text, suggestedName: link?.host) else { return false }
            if localTray { DroppyFileTrayStore.shared.add(urls: [saved]) }
        }
        openPage(.shelf)
        return true
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
            guard self.skin.usesIslandSurfaceEngine else { return true }
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
/// displays or the per-display choice change. Events and shortcuts use the panel under the pointer.
@MainActor
final class NotchPanelCoordinator: LiveEventSink {
    private var controllers: [CGDirectDisplayID: NotchPanelController] = [:]
    private var designs: [CGDirectDisplayID: NotchDesign] = [:]
    /// MD-3: last topology-level placement, so a clamshell handover is recognised in one pass.
    private var lastRoles: [String: IslandRole] = [:]
    private var lastDisplayIDs: [String: CGDirectDisplayID] = [:]
    private var pointerScreenTimer: Timer?
    private var pointerDisplayID: CGDirectDisplayID?
    private var enabled = false
    private var observers = Set<AnyCancellable>()
    var theme: () -> NowPlayingTheme = { .auto } { didSet { controllers.values.forEach { $0.theme = theme } } }
    var onOpenSettings: () -> Void = {} { didSet { controllers.values.forEach { $0.onOpenSettings = onOpenSettings } } }
    var skin: LiveIslandSkin = .boring { didSet { reconcile() } }
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
        var rolesByDisplay: [CGDirectDisplayID: IslandRole] = [:]
        var roles: [String: IslandRole] = [:]
        let screens = NSScreen.screens
        let displayIDs = Dictionary(screens.compactMap { screen -> (String, CGDirectDisplayID)? in
            guard let uuid = DisplayIdentity.uuidString(for: screen), let id = screen.displayID else { return nil }
            return (uuid, id)
        }, uniquingKeysWith: { first, _ in first })
        updatePointerScreenTracking(screens: screens)
        if enabled {
            let stored = NotchDesign.stored()
            roles = islandRoles()
            for screen in screens {
                guard let id = screen.displayID else { continue }
                let uuid = DisplayIdentity.uuidString(for: screen)
                let role = uuid.flatMap { roles[$0] } ?? .wideBar
                guard role.showsIsland else { continue }
                let design = NotchDesign.resolve(
                    display: String(id),
                    displayUUID: uuid,
                    // MD-3: the placement mode decides the default shape (notch vs wide bar); the
                    // per-display override still wins.
                    hasHardwareNotch: role == .notch || role == .floatingPill,
                    stored: stored
                )
                if design != .off {
                    wanted[id] = design
                    rolesByDisplay[id] = role
                }
            }
        }

        // MD-3 clamshell handover: when a role moves to another display in one pass (the lid closed
        // and the external took over) re-target the existing controller instead of tearing it down,
        // so an open island and its page survive.
        let handover = IslandPlacement.handover(previous: lastRoles, current: roles)
        if enabled, handover.isRetarget, let from = handover.movedFrom, let to = handover.movedTo,
           let fromID = lastDisplayIDs[from], let toID = displayIDs[to],
           let controller = controllers[fromID], controllers[toID] == nil, let design = wanted[toID] {
            controllers[fromID] = nil
            designs[fromID] = nil
            controller.retarget(displayID: toID, design: design)
            controllers[toID] = controller
            designs[toID] = design
        }
        lastRoles = roles
        lastDisplayIDs = displayIDs

        for (id, c) in controllers where wanted[id] != designs[id] { c.setEnabled(false); controllers[id] = nil }
        designs = wanted
        let storedSkins = NotchDisplaySkin.stored()
        for (id, design) in wanted {
            let screen = screens.first { $0.displayID == id }
            let displaySkin = NotchDisplaySkin.resolve(
                display: String(id),
                displayUUID: screen.flatMap { DisplayIdentity.uuidString(for: $0) },
                fallback: skin,
                stored: storedSkins
            )
            // A floating-pill role keeps the wide-bar panel but rests as a compact capsule.
            let role = rolesByDisplay[id] ?? .wideBar
            let behavior: IslandNonNotchIdleBehavior = role == .floatingPill ? .compactPill : nonNotchBehavior
            if let existing = controllers[id] {
                if existing.skin != displaySkin { existing.skin = displaySkin }
                if existing.nonNotchBehavior != behavior { existing.nonNotchBehavior = behavior }
                continue
            }
            let c = NotchPanelController(displayID: id, design: design)
            c.theme = theme; c.onOpenSettings = onOpenSettings; c.skin = displaySkin
            c.touchModeSetting = touchModeSetting
            c.nonNotchBehavior = behavior
            c.keylineEnabled = keylineEnabled
            if let shelfStore { c.bindShelfStore(shelfStore) }
            controllers[id] = c
            c.setEnabled(true)
        }
    }

    private func updatePointerScreenTracking(screens: [NSScreen]) {
        guard enabled, IslandPlacementMode.current() == .followActiveDisplay, screens.count > 1 else {
            pointerScreenTimer?.invalidate()
            pointerScreenTimer = nil
            pointerDisplayID = nil
            return
        }
        pointerDisplayID = Self.screenUnderPointer(screens)?.displayID
        guard pointerScreenTimer == nil else { return }
        // Tracking only runs for the explicit pointer-following mode, without a global mouse tap.
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let current = Self.screenUnderPointer(NSScreen.screens)?.displayID
                if current != self.pointerDisplayID { self.reconcile() }
            }
        }
        timer.tolerance = 0.04
        RunLoop.main.add(timer, forMode: .common)
        pointerScreenTimer = timer
    }

    private static func screenUnderPointer(_ screens: [NSScreen]) -> NSScreen? {
        let cursor = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
    }

    /// MD-3: topology-level placement for the connected screens. `followActiveDisplay` uses the
    /// display under the pointer, so moving the pointer (or the lid) moves the one island.
    private func islandRoles() -> [String: IslandRole] {
        let screens = NSScreen.screens
        let displays: [IslandPlacement.Display] = screens.compactMap { screen in
            guard let uuid = DisplayIdentity.uuidString(for: screen) else { return nil }
            let isBuiltIn = screen.displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false
            return IslandPlacement.Display(uuid: uuid,
                                           hasHardwareNotch: screen.safeAreaInsets.top > 0,
                                           isBuiltIn: isBuiltIn)
        }
        let activeUUID = Self.screenUnderPointer(screens).flatMap { DisplayIdentity.uuidString(for: $0) }
        return IslandPlacement.resolve(mode: IslandPlacementMode.current(), displays: displays, activeUUID: activeUUID)
    }

    func show(_ event: LiveEvent) { underPointer?.show(event) }

    private var underPointer: NotchPanelController? {
        let p = NSEvent.mouseLocation
        let id = NSScreen.screens.first { $0.frame.contains(p) }?.displayID
        return id.flatMap { controllers[$0] }
            ?? NSScreen.main?.displayID.flatMap { controllers[$0] }
            ?? controllers.values.first
    }

    func toggleTools() { underPointer?.toggleTools() }
    func stepPage(forward: Bool) { underPointer?.stepPage(forward: forward) }
}
