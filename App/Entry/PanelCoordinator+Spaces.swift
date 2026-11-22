import AppKit
import ApplicationServices
import Combine
import QuartzCore
import SwiftUI
import os

// PanelCoordinator · 桌面（Space）相关：常驻所有桌面的成员资格修复（issue #19）与钉进私有空间。
// 2026-09-05 从 PanelCoordinator.swift 按 extension 拆出，只搬不改。
extension PanelCoordinator {
    /// 读回成员资格，把「本该在所有桌面上、实际只剩当前桌面」的面板补回去。
    ///
    /// 机制与为什么只有这一种形状管用，见 `AllSpacesMembership`。这里三件事一件都不能省：
    /// ① 先读回再决定动不动手——健康时零副作用；② 换值必须隔一轮 runloop 再赋回，
    /// 同一轮里改回去等于没改；③ 赋回之后还要再读一次，**单次修复不保证成功**。
    func repairAllSpacesMembershipIfNeeded(attempt: Int = 1) {
        guard Self.spaceMembershipRepairEnabled, !isSuspendedForPermissionLoss else { return }
        if attempt == 1 && spaceMembershipRepairInFlight { return }
        guard let dock = dockPanel else { return }
        // 钉进私有空间的面板不在任何桌面上，这个修复会把它当「丢了成员资格」反复清空重赋；
        // 只修没钉住的（宿主不可用时 = 全部，行为同旧）。
        let repairCandidates = allSpacesPanels.filter { panel in
            !(overlaySpaceHost?.isPinned(windowNumber: panel.windowNumber) ?? false)
        }
        guard !repairCandidates.isEmpty else {
            spaceMembershipRepairInFlight = false
            return
        }

        guard let uuid = DisplayIdentity.uuidString(for: panelCurrentScreen(panel: dock)),
              let layout = ManagedSpaceLayoutReader.layout(forDisplayUUID: uuid) else {
            spaceMembershipRepairInFlight = false
            return
        }
        let desktops = layout.orderedSpaceIDs.filter { !layout.fullscreenSpaceIDs.contains($0) }

        let broken = repairCandidates.filter { panel in
            guard let owned = WindowSpaceMembershipReader.spaceIDs(forWindowNumber: panel.windowNumber)
            else { return false }   // 读不到 = 不知道，不能当成「丢了」
            return !AllSpacesMembership.missingSpaceIDs(
                windowSpaceIDs: owned,
                desktopSpaceIDs: desktops
            ).isEmpty
        }
        guard !broken.isEmpty else {
            if attempt > 1 {
                logger.info("[space-membership] repaired attempts=\(attempt - 1, privacy: .public)")
            }
            spaceMembershipRepairInFlight = false
            return
        }
        guard AllSpacesMembership.shouldRetry(attempt: attempt - 1) else {
            logger.error("[space-membership] give up after \(attempt - 1, privacy: .public) attempts")
            spaceMembershipRepairInFlight = false
            return
        }

        spaceMembershipRepairInFlight = true
        for panel in broken { panel.collectionBehavior = [] }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for panel in broken { panel.collectionBehavior = PanelCollectionBehavior.standard }
            DispatchQueue.main.asyncAfter(deadline: .now() + AllSpacesMembership.verifyDelay) { [weak self] in
                self?.repairAllSpacesMembershipIfNeeded(attempt: attempt + 1)
            }
        }
    }

    // MARK: - 常驻面板钉进私有空间（桌面互滑时底板不发灰）

    /// 把任务条 / 玻璃底板 / 胶囊钉进进程唯一的私有空间。机理与实测边界见 `OverlaySpaceHost`。
    func pinResidentPanelsIfNeeded() {
        guard let host = overlaySpaceHost, !isSuspendedForPermissionLoss else { return }
        let windowNumbers = allSpacesPanels.map(\.windowNumber)
        guard !windowNumbers.isEmpty else { return }
        if !host.pin(windowNumbers: windowNumbers) {
            logger.error("[overlay-space] pin failed windows=\(windowNumbers, privacy: .public)")
        }
    }

    /// 瞬时面板（抽屉 / 弹窗 / 名字气泡）**也要钉进同一空间**——它们都会和任务条那几扇窗口的范围
    /// （含 20pt 阴影透明边）重叠，而留在桌面空间的窗口不论 `level` 都被合成在私有空间**下面**：
    /// 抽屉最下一行压在胶囊窗口的阴影边里就发暗，启动弹跳往上一抬又变亮（owner 2026-09-03，
    /// `DOCK_OVERLAY_SPACE=0` A/B 坐实）。每次 order front 后补钉一次，已钉住的只是一次廉价读回。
    func pinOverlappingPanelIfNeeded(_ panel: NSPanel) {
        guard let host = overlaySpaceHost, !isSuspendedForPermissionLoss, panel.windowNumber > 0 else { return }
        if !host.pin(windowNumbers: [panel.windowNumber]) {
            logger.error("[overlay-space] pin failed window=\(panel.windowNumber, privacy: .public)")
        }
    }
}

// MARK: - Mission Control session (MC-2)

/// Watches the Dock's overview and drives the MC-3 surface while it is open. Detection is
/// event-driven: an AX observer on the Dock plus the Space-change notification. There is no timer, no
/// poll and no run-loop spin, so a closed Mission Control costs nothing. Every monitor and panel this
/// type creates is torn down in `stop()`, and the whole session is off unless the section is enabled.
@MainActor
final class MissionControlSession {
    static let shared = MissionControlSession()
    private let logger = Logger(subsystem: "com.katikati.app", category: "mission-control")

    private var observer: AXObserver?
    private var dockPID: pid_t?
    private var workspaceObserver: NSObjectProtocol?
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    /// One render panel per display, keyed by CGDirectDisplayID. Mission Control spans every screen,
    /// so a single main-screen panel would leave thumbnails on other displays unadorned and would map
    /// their frames with the wrong origin.
    private var renderPanels: [CGDirectDisplayID: NSPanel] = [:]
    private var controlPanel: NSPanel?
    private var screenObserver: NSObjectProtocol?
    /// The overview's filter, hover and keyboard target; all transition rules live in Core so they
    /// are covered by `MissionControlInteractionTests` instead of only by the live session.
    private var interaction = MissionControlInteraction()
    /// Set when the overlay is dismissed on purpose (Return raised a window), so the Dock-closing
    /// animation cannot immediately re-open it from an AX notification.
    private var suspendedUntil: Date?
    /// Throttles the on-demand activation probe; Mission Control publishes no readable Dock AX
    /// notification on macOS 26, so entry is recognised from the gesture/click/key that opens it.
    private var nextActivationProbe = Date.distantPast
    private var configuration = MissionControlConfiguration()
    private var isActive = false
    /// Pure enter/exit rules, so a probe without a backdrop or without thumbnails is a teardown.
    private var presence = MissionControlPresence()
    /// Probes only while the overlay is up: Mission Control closes without a readable Dock event, so
    /// nothing else would ever notice the overview is gone.
    private var exitWatchdog: Timer?
    /// Slow entry probe while the overlay is down. The keyboard path cannot depend on the global key
    /// monitor (Input Monitoring is optional), and gestures/hot corners rarely post anything usable,
    /// so one cheap CGWindowList read every 1.5 s is what makes entry reliable for every opener.
    private var idleProbe: Timer?
    private var activationObserver: NSObjectProtocol?

    private var frames: [MissionControlWindowFrame] { interaction.frames }
    private var hoveredID: MissionControlWindowFrame.ID? { interaction.hoveredID }
    private var focusedID: MissionControlWindowFrame.ID? { interaction.focusedID }
    private var query: String { interaction.query }
    private var isEnabled = false

    /// The pane calls this when its switch changes; app launch calls `start()` when the stored switch
    /// is already on, so a relaunch keeps working without opening Settings.
    func applyEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled { start() } else { stop() }
    }

    func start() {
        guard MissionControlSettings.isEnabled(), !isActive else { return }
        isEnabled = true
        // Loaded before the line so the log states the configuration this session actually started
        // with; `Logger.info` takes an autoclosure, so every member read needs `self.`.
        configuration = MissionControlSettings.load()
        logger.info("[mission-control] start enabled=\(self.isEnabled, privacy: .public) keyboard=\(self.configuration.naming.keyboardEnabled, privacy: .public) navigation=\(self.configuration.naming.navigationEnabled, privacy: .public) filter=\(self.configuration.naming.filterEnabled, privacy: .public) hoverKeys=\(self.configuration.actions.hoverKeys.isEnabled, privacy: .public) axTrusted=\(AXIsProcessTrusted(), privacy: .public)")
        guard AXIsProcessTrusted() else { return }
        guard let dock = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.dock"
        }) else { return }

        if observer == nil {
            dockPID = dock.processIdentifier
            var created: AXObserver?
            guard AXObserverCreate(dock.processIdentifier, Self.observerCallback, &created) == .success,
                  let created else { return }
            observer = created
            let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
            for note in [kAXWindowCreatedNotification, kAXUIElementDestroyedNotification, kAXTitleChangedNotification] {
                AXObserverAddNotification(created, dockElement, note as CFString, Unmanaged.passUnretained(self).toOpaque())
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        }

        if workspaceObserver == nil {
            workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }

        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isActive else { return }
                    self.showPanels()
                    self.updateHover(at: Self.pointerLocation())
                }
            }
        }

        if activationObserver == nil {
            // Returning to a normal app is the clearest exit signal there is; refresh then sees the
            // Dock backdrop gone and tears the panels down.
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }

        if mouseMonitor == nil {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        ) { [weak self] event in
                MainActor.assumeIsolated { self?.handleMouse(event) }
            }
        }
        if keyMonitor == nil {
            keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                MainActor.assumeIsolated { self?.handleKey(event) }
            }
        }

        refresh()
        startIdleProbe()
    }

    func stop() {
        stopExitWatchdog()
        stopIdleProbe()
        presence.close()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        dockPID = nil
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        workspaceObserver = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        hidePanels()
        interaction.close()
        isActive = false
        suspendedUntil = Date().addingTimeInterval(0.6)
    }

    private static let observerCallback: AXObserverCallback = { _, _, _, refcon in
        guard let refcon else { return }
        let session = Unmanaged<MissionControlSession>.fromOpaque(refcon).takeUnretainedValue()
        DispatchQueue.main.async {
            MainActor.assumeIsolated { session.refresh() }
        }
    }

    private func refresh() {
        if let suspendedUntil, Date() < suspendedUntil { return }
        guard isEnabled, MissionControlSettings.isEnabled() else {
            stop()
            return
        }
        let probe = MissionControlDockProbe.probe()
        logger.debug("[mission-control] probe active=\(probe.isActive, privacy: .public) readable=\(probe.dockReadable, privacy: .public) frames=\(probe.frames.count, privacy: .public)")
        switch presence.observe(backdropVisible: probe.isActive, thumbnailCount: probe.frames.count) {
        case .enter:
            stopIdleProbe()
            configuration = MissionControlSettings.load()
            interaction.open(with: probe.frames)
            isActive = true
            showPanels()
            startExitWatchdog()
            updateHover(at: Self.pointerLocation())
        case .none:
            guard presence.isActive else { return }
            // A refresh comes from any AX or Space notification, including title changes while the
            // user is typing a filter; `update` keeps the query and target so the overview cannot
            // reset under them.
            configuration = MissionControlSettings.load()
            interaction.update(frames: probe.frames)
            updateRender()
            updateHover(at: Self.pointerLocation())
        case .exit:
            dismiss()
        }
    }

    /// Exit detection: the Dock publishes no readable Mission Control notifications on macOS 26 and
    /// the activation probe only runs while the overlay is down, so while it is up we probe on a
    /// short timer. One inactive probe tears everything down; nothing here runs once dismissed.
    private func startExitWatchdog() {
        guard exitWatchdog == nil else { return }
        let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        exitWatchdog = timer
    }

    private func stopExitWatchdog() {
        exitWatchdog?.invalidate()
        exitWatchdog = nil
    }

    private func startIdleProbe() {
        guard idleProbe == nil, isEnabled else { return }
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isActive else { return }
                self.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleProbe = timer
    }

    private func stopIdleProbe() {
        idleProbe?.invalidate()
        idleProbe = nil
    }

    // MARK: Panels

    private func showPanels() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        logger.info("[mission-control] show panels frames=\(self.frames.count, privacy: .public) screens=\(screens.count, privacy: .public)")
        var live: Set<CGDirectDisplayID> = []
        for screen in screens {
            let id = Self.displayID(of: screen)
            live.insert(id)
            let render = renderPanels[id] ?? makePanel(clickThrough: true, level: .screenSaver)
            render.setFrame(screen.frame, display: true)
            renderPanels[id] = render
            render.orderFrontRegardless()
        }
        for (id, panel) in renderPanels where !live.contains(id) {
            panel.orderOut(nil)
            renderPanels.removeValue(forKey: id)
        }
        updateRender()

        if controlPanel == nil {
            controlPanel = makePanel(clickThrough: false, level: .screenSaver)
        }
        controlPanel?.contentView = NSHostingView(rootView: MissionControlControlCluster(
            actions: configuration.actions.buttons.shownActions,
            appearance: configuration.presentation.appearance,
            onAction: { [weak self] action in self?.perform(action) }
        ))
        controlPanel?.orderFrontRegardless()
        placeControls()
    }

    private func makePanel(clickThrough: Bool, level: NSWindow.Level) -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = level
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = clickThrough
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }

    private func hidePanels() {
        for panel in renderPanels.values { panel.orderOut(nil) }
        controlPanel?.orderOut(nil)
    }

    // MARK: Pointer and keys

    private func handleMouse(_ event: NSEvent) {
        guard isActive else {
            switch event.type {
            case .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
                scheduleActivationProbe()
            default:
                break
            }
            return
        }
        switch event.type {
        case .mouseMoved:
            updateHover(at: Self.axLocation(of: event))
        case .rightMouseDown:
            guard let action = configuration.actions.mouse.action(for: .right) else { return }
            perform(action, source: .pointer)
        case .otherMouseDown:
            guard event.buttonNumber == 2,
                  let action = configuration.actions.mouse.action(for: .middle) else { return }
            perform(action, source: .pointer)
        default:
            break
        }
    }

    private func handleKey(_ event: NSEvent) {
        // Entry detection is not a keyboard-control opt-in: F3 / ⌃↑ must arm the probe even for a
        // user who keeps KatiKati out of Mission Control's own keyboard handling. Otherwise a
        // keyboard-opened overview was never decorated at all.
        guard isActive else {
            if Self.opensOverview(event) { scheduleActivationProbe() }
            return
        }
        // Every path *inside* the overlay is opt-in. Without it Mission Control keeps its own
        // keyboard handling and the overlay stays purely visual plus pointer actions.
        guard configuration.naming.keyboardEnabled else { return }
        let modifiers = Self.modifiers(of: event.modifierFlags)
        let characters = event.charactersIgnoringModifiers ?? ""

        // Overview navigation: Tab / arrows move the keyboard target, Return raises it. These run
        // before the hover shortcuts so a plain key never triggers a window action by accident.
        // Navigation is its own opt-in: a user may want type-to-filter without handing Tab/Return
        // to KatiKati, or the other way round.
        if configuration.naming.navigationEnabled,
           modifiers.isEmpty || modifiers == [.shift] {
            let step: Int? = {
                switch event.keyCode {
                case 48: return modifiers == [.shift] ? -1 : 1      // Tab / ⇧Tab
                case 124, 125: return 1                              // → / ↓
                case 123, 126: return -1                             // ← / ↑
                default: return nil
                }
            }()
            if let step {
                apply(interaction.handle(.moveFocus(step: step)))
                return
            }
            if event.keyCode == 36 {
                apply(interaction.handle(.raise))
                return
            }
        }
        if modifiers == configuration.actions.hoverKeys.modifiers,
           let action = configuration.actions.hoverKeys.action(forKey: characters, modifiers: modifiers) {
            perform(action, source: .keyboard)
            return
        }
        guard configuration.naming.filterEnabled, modifiers.isEmpty else {
            // Escape still leaves the overview when keyboard navigation is on, even if filtering is
            // off; it clears an empty filter and dismisses on the next press.
            if configuration.naming.navigationEnabled, event.keyCode == 53, modifiers.isEmpty {
                apply(interaction.handle(.escape))
            }
            return
        }
        if event.keyCode == 53 {
            apply(interaction.handle(.escape))
            return
        }
        if event.keyCode == 51 {
            apply(interaction.handle(.deleteBackward))
            return
        }
        if characters.count == 1, let scalar = characters.unicodeScalars.first,
           CharacterSet.alphanumerics.contains(scalar) || "-_. '".unicodeScalars.contains(scalar) {
            apply(interaction.handle(.text(characters)))
        }
    }

    /// Mission Control's opening gesture is not observable through the Dock on this macOS, so entry is
    /// probed once shortly after the key, click, swipe or hot-corner that can open it. Probe calls are
    /// throttled and there is no timer while the overview is closed.
    private func scheduleActivationProbe() {
        guard Date() >= nextActivationProbe else { return }
        logger.info("[mission-control] activation probe scheduled")
        nextActivationProbe = Date().addingTimeInterval(0.9)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self, !self.isActive else { return }
            guard let suspendedUntil = self.suspendedUntil, Date() < suspendedUntil else {
                self.refresh()
                return
            }
            // A Raise dismiss suspends re-entry for 0.6 s; retry once after it instead of dropping the
            // user's genuine re-open because it landed inside that window.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, !self.isActive else { return }
                self.refresh()
            }
        }
    }

    private static func opensOverview(_ event: NSEvent) -> Bool {
        let modifiers = modifiers(of: event.modifierFlags)
        switch event.keyCode {
        case 99, 160: return true                                  // F3 / Mission Control key
        case 126: return modifiers == [.control]                   // ⌃↑
        default: return false
        }
    }

    /// Runs the pure interaction's answer: redraw from the new state, raise a window through AX and
    /// leave the overview, or dismiss it outright (Escape with no filter).
    private func apply(_ effects: [MissionControlInteraction.Effect]) {
        for effect in effects {
            switch effect {
            case .render:
                updateRender()
            case .dismiss:
                dismiss()
            case .raise(let id):
                if let frame = frames.first(where: { $0.id == id }) {
                    _ = WindowActionExecutor.raise(frame)
                }
                dismiss()
            }
        }
    }

    /// Hides the overlay without tearing down monitors: the session stays subscribed, and the next
    /// Dock activation reuses it. Used when Return raises a window (the overview is done at that
    /// point) and when the Dock leaves overview mode.
    private func dismiss() {
        stopExitWatchdog()
        presence.close()
        hidePanels()
        interaction.close()
        isActive = false
        suspendedUntil = Date().addingTimeInterval(0.6)
        startIdleProbe()
    }

    /// Rebuilds every display's render panel from the current frames, configuration and live session
    /// state (hover, keyboard target, filter). Called on every state change, never on a timer.
    private func updateRender() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let groups = MissionControlScreenGeometry.framesByScreen(
            frames, screens: screens.map(\.frame),
            primaryHeight: MissionControlScreenGeometry.primaryHeight(screens.map(\.frame))
        )
        let filterScreen = focusedTargetScreenIndex(screens: screens) ?? hoveredScreenIndex(screens: screens)
        for (index, screen) in screens.enumerated() {
            guard let render = renderPanels[Self.displayID(of: screen)] else { continue }
            render.contentView = NSHostingView(rootView: MissionControlSurface(
                frames: groups[index],
                configuration: configuration,
                hoveredID: hoveredID,
                focusedID: focusedID,
                query: query,
                spaceTitle: spaceTitle(on: screen),
                spaceAccent: spaceAccent(on: screen),
                showsButtons: false,
                showsFilterChip: filterScreen == nil || filterScreen == index
            ))
        }
    }

    /// The filter readout follows the keyboard target (or the hovered window) to its display, so two
    /// panels never show the same query twice.
    private func focusedTargetScreenIndex(screens: [NSScreen]) -> Int? {
        guard let focusedID, let frame = frames.first(where: { $0.id == focusedID }) else { return nil }
        return Self.screenIndex(of: frame, screens: screens)
    }

    private func hoveredScreenIndex(screens: [NSScreen]) -> Int? {
        guard let hoveredID, let frame = frames.first(where: { $0.id == hoveredID }) else { return nil }
        return Self.screenIndex(of: frame, screens: screens)
    }

    private func updateHover(at point: CGPoint) {
        let target = MissionControlTargetRanker.target(at: point, in: frames)
        guard target?.id != hoveredID else { return }
        interaction.hover(target?.id)
        updateRender()
        controlPanel?.orderFrontRegardless()
        placeControls()
    }

    private func placeControls() {
        guard let panel = controlPanel else { return }
        let hidden = CGRect(x: -10_000, y: -10_000, width: 80, height: 30)
        guard configuration.actions.buttons.showsOnHover else {
            panel.setFrame(hidden, display: false)
            return
        }
        let screens = NSScreen.screens
        guard let hoveredID, let frame = frames.first(where: { $0.id == hoveredID }),
              let index = Self.screenIndex(of: frame, screens: screens) else {
            panel.setFrame(hidden, display: false)
            return
        }
        let screen = screens[index]
        let primaryHeight = MissionControlScreenGeometry.primaryHeight(screens.map(\.frame))
        let local = MissionControlScreenGeometry.local(frame.frame, on: screen.frame, primaryHeight: primaryHeight)
        let width: CGFloat = CGFloat(configuration.actions.buttons.shownActions.count) * 27 + 12
        let clampedX: CGFloat = min(screen.frame.maxX - width - 8, screen.frame.minX + local.maxX - width - 8)
        let clampedY: CGFloat = max(screen.frame.minY + 8, screen.frame.maxY - local.minY - 40)
        panel.setFrame(CGRect(origin: CGPoint(x: clampedX, y: clampedY), size: CGSize(width: width, height: 34)), display: true)
    }

    private func perform(_ action: MissionControlWindowAction, source: MissionControlInteraction.Source = .pointer) {
        guard let frame = interaction.target(for: source) else { return }
        _ = WindowActionExecutor.perform(action, on: frame)
        refresh()
    }

    /// Each display has its own current Space and name; the pill on a secondary screen must not copy
    /// the main display's.
    private func spaceTitle(on screen: NSScreen) -> String? {
        guard let uuid = DisplayIdentity.uuidString(for: screen),
              let layout = ManagedSpaceLayoutReader.layout(forDisplayUUID: uuid),
              let index = layout.orderedSpaceIDs.firstIndex(of: layout.currentSpaceID) else {
            return configuration.naming.spaceTitle(forSpaceID: "", index: 1)
        }
        return configuration.naming.spaceTitle(forSpaceID: String(layout.currentSpaceID), index: index + 1)
    }

    private func spaceAccent(on screen: NSScreen) -> MissionControlColor? {
        guard let uuid = DisplayIdentity.uuidString(for: screen),
              let layout = ManagedSpaceLayoutReader.layout(forDisplayUUID: uuid) else { return nil }
        return configuration.colouring.accent(forSpaceID: String(layout.currentSpaceID))
    }

    // MARK: Geometry

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    private static func screenIndex(of frame: MissionControlWindowFrame, screens: [NSScreen]) -> Int? {
        MissionControlScreenGeometry.screenIndex(
            containing: frame.frame, screens: screens.map(\.frame),
            primaryHeight: MissionControlScreenGeometry.primaryHeight(screens.map(\.frame))
        )
    }

    private static func pointerLocation() -> CGPoint {
        let cocoa = NSEvent.mouseLocation
        let height = MissionControlScreenGeometry.primaryHeight(NSScreen.screens.map(\.frame))
        return CGPoint(x: cocoa.x, y: height - cocoa.y)
    }

    private static func axLocation(of event: NSEvent) -> CGPoint {
        let cocoa = NSEvent.mouseLocation
        let height = NSScreen.screens.first?.frame.maxY ?? 0
        return CGPoint(x: cocoa.x, y: height - cocoa.y)
    }

    private static func modifiers(of flags: NSEvent.ModifierFlags) -> Set<MissionControlModifier> {
        var result: Set<MissionControlModifier> = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        return result
    }
}
