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

    private var observer: AXObserver?
    private var dockPID: pid_t?
    private var workspaceObserver: NSObjectProtocol?
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private var renderPanel: NSPanel?
    private var controlPanel: NSPanel?
    private var frames: [MissionControlWindowFrame] = []
    private var hoveredID: MissionControlWindowFrame.ID?
    private var focusedID: MissionControlWindowFrame.ID?
    /// Set when the overlay is dismissed on purpose (Return raised a window), so the Dock-closing
    /// animation cannot immediately re-open it from an AX notification.
    private var suspendedUntil: Date?
    private var configuration = MissionControlConfiguration()
    private var query = ""
    private var isActive = false
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
        configuration = MissionControlSettings.load()
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

        if mouseMonitor == nil {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                MainActor.assumeIsolated { self?.handleMouse(event) }
            }
        }
        if keyMonitor == nil {
            keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                MainActor.assumeIsolated { self?.handleKey(event) }
            }
        }

        refresh()
    }

    func stop() {
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
        hidePanels()
        frames = []
        hoveredID = nil
        focusedID = nil
        query = ""
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
        guard probe.isActive, !probe.frames.isEmpty else {
            if isActive { dismiss() }
            return
        }
        let wasActive = isActive
        configuration = MissionControlSettings.load()
        frames = probe.frames
        // A refresh comes from any AX or Space notification, including title changes while the user
        // is typing a filter; keep the query and target so the overview does not reset under them.
        if !wasActive { query = "" }
        if focusedID == nil || !probe.frames.contains(where: { $0.id == focusedID }) {
            focusedID = probe.frames.first?.id
        }
        isActive = true
        showPanels()
        updateHover(at: Self.pointerLocation())
    }

    // MARK: Panels

    private func showPanels() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let local = frames.map { Self.local($0, on: screen) }

        let render = renderPanel ?? makePanel(clickThrough: true, level: .screenSaver)
        render.setFrame(screen.frame, display: true)
        renderPanel = render
        updateRender()
        render.orderFrontRegardless()

        let controls = controlPanel ?? makePanel(clickThrough: false, level: .screenSaver)
        controls.contentView = NSHostingView(rootView: MissionControlControlCluster(
            actions: configuration.actions.buttons.shownActions,
            onAction: { [weak self] action in self?.perform(action) }
        ))
        controls.orderFrontRegardless()
        controlPanel = controls
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
        renderPanel?.orderOut(nil)
        controlPanel?.orderOut(nil)
    }

    // MARK: Pointer and keys

    private func handleMouse(_ event: NSEvent) {
        guard isActive else { return }
        switch event.type {
        case .mouseMoved:
            updateHover(at: Self.axLocation(of: event))
        case .rightMouseDown:
            guard let action = configuration.actions.mouse.action(for: .right) else { return }
            perform(action)
        case .otherMouseDown:
            guard event.buttonNumber == 2,
                  let action = configuration.actions.mouse.action(for: .middle) else { return }
            perform(action)
        default:
            break
        }
    }

    private func handleKey(_ event: NSEvent) {
        guard isActive else { return }
        let modifiers = Self.modifiers(of: event.modifierFlags)
        let characters = event.charactersIgnoringModifiers ?? ""

        // Overview navigation: Tab / arrows move the keyboard target, Return raises it. These run
        // before the hover shortcuts so a plain key never triggers a window action by accident.
        if modifiers.isEmpty || modifiers == [.shift] {
            let step: Int? = {
                switch event.keyCode {
                case 48: return modifiers == [.shift] ? -1 : 1      // Tab / ⇧Tab
                case 124, 125: return 1                              // → / ↓
                case 123, 126: return -1                             // ← / ↑
                default: return nil
                }
            }()
            if let step {
                let activeQuery = query
                let visible = { (frame: MissionControlWindowFrame) in
                    MissionControlFilter.matches(query: activeQuery, title: frame.title, app: frame.appName)
                }
                focusedID = MissionControlTargetRanker.next(
                    after: focusedID, step: step, in: frames, visible: visible
                )?.id
                updateRender()
                return
            }
            if event.keyCode == 36, let frame = Self.target(focusedID: focusedID, hoveredID: hoveredID, frames: frames) {
                _ = WindowActionExecutor.raise(frame)
                dismiss()
                return
            }
        }
        if modifiers == configuration.actions.hoverKeys.modifiers,
           let action = configuration.actions.hoverKeys.action(forKey: characters, modifiers: modifiers) {
            perform(action)
            return
        }
        guard configuration.naming.filterEnabled, modifiers.isEmpty else { return }
        if event.keyCode == 53 {
            query = ""
            focusedID = frames.first?.id
        } else if event.keyCode == 51 {
            if !query.isEmpty { query.removeLast() }
        } else if characters.count == 1, let scalar = characters.unicodeScalars.first,
                  CharacterSet.alphanumerics.contains(scalar) {
            query.append(Character(scalar))
        } else {
            return
        }
        focusedID = Self.firstVisible(in: frames, query: query)?.id
        updateRender()
    }

    /// Hides the overlay without tearing down monitors: the session stays subscribed, and the next
    /// Dock activation reuses it. Used when Return raises a window (the overview is done at that
    /// point) and when the Dock leaves overview mode.
    private func dismiss() {
        hidePanels()
        frames = []
        hoveredID = nil
        focusedID = nil
        query = ""
        isActive = false
    }

    private static func firstVisible(in frames: [MissionControlWindowFrame], query: String) -> MissionControlWindowFrame? {
        frames.first { MissionControlFilter.matches(query: query, title: $0.title, app: $0.appName) }
    }

    /// The window a keyboard action applies to: the explicit target first, the hovered window as a
    /// fallback for pointer-first use.
    private static func target(
        focusedID: MissionControlWindowFrame.ID?,
        hoveredID: MissionControlWindowFrame.ID?,
        frames: [MissionControlWindowFrame]
    ) -> MissionControlWindowFrame? {
        frames.first { $0.id == focusedID } ?? frames.first { $0.id == hoveredID }
    }

    /// Rebuilds the render panel's root view from the current frames, configuration and live session
    /// state (hover, keyboard target, filter). Called on every state change and never on a timer.
    private func updateRender() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first,
              let render = renderPanel else { return }
        let local = frames.map { Self.local($0, on: screen) }
        render.contentView = NSHostingView(rootView: MissionControlSurface(
            frames: local,
            configuration: configuration,
            hoveredID: hoveredID,
            focusedID: focusedID,
            query: query,
            spaceTitle: spaceTitle(),
            spaceAccent: spaceAccent(),
            showsButtons: false
        ))
    }

    private func updateHover(at point: CGPoint) {
        let target = MissionControlTargetRanker.target(at: point, in: frames)
        guard target?.id != hoveredID else { return }
        hoveredID = target?.id
        updateRender()
        controlPanel?.orderFrontRegardless()
        placeControls()
    }

    private func placeControls() {
        guard let panel = controlPanel else { return }
        guard configuration.actions.buttons.showsOnHover else {
            panel.setFrame(CGRect(x: -10_000, y: -10_000, width: 80, height: 30), display: false)
            return
        }
        guard let hoveredID, let frame = frames.first(where: { $0.id == hoveredID }),
              let screen = NSScreen.main ?? NSScreen.screens.first else {
            panel.setFrame(CGRect(x: -10_000, y: -10_000, width: 80, height: 30), display: false)
            return
        }
        let local = Self.local(frame, on: screen)
        let width: CGFloat = CGFloat(configuration.actions.buttons.shownActions.count) * 27 + 12
        let clampedX: CGFloat = min(screen.frame.maxX - width - 8, screen.frame.minX + local.frame.maxX - width - 8)
        let clampedY: CGFloat = max(screen.frame.minY + 8, screen.frame.maxY - local.frame.minY - 40)
        let origin = CGPoint(x: clampedX, y: clampedY)
        panel.setFrame(CGRect(origin: origin, size: CGSize(width: width, height: 34)), display: true)
    }

    private func perform(_ action: MissionControlWindowAction) {
        guard let frame = Self.target(focusedID: focusedID, hoveredID: hoveredID, frames: frames) else { return }
        _ = WindowActionExecutor.perform(action, on: frame)
        refresh()
    }

    private func spaceTitle() -> String? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first,
              let uuid = DisplayIdentity.uuidString(for: screen),
              let layout = ManagedSpaceLayoutReader.layout(forDisplayUUID: uuid),
              let index = layout.orderedSpaceIDs.firstIndex(of: layout.currentSpaceID) else {
            return configuration.naming.spaceTitle(forSpaceID: "", index: 1)
        }
        return configuration.naming.spaceTitle(forSpaceID: String(layout.currentSpaceID), index: index + 1)
    }

    private func spaceAccent() -> MissionControlColor? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first,
              let uuid = DisplayIdentity.uuidString(for: screen),
              let layout = ManagedSpaceLayoutReader.layout(forDisplayUUID: uuid) else { return nil }
        return configuration.colouring.accent(forSpaceID: String(layout.currentSpaceID))
    }

    // MARK: Geometry

    /// AX screen coordinates are top-left origin; the overlay panel's SwiftUI space starts at the
    /// screen's top-left too, so the conversion is a translation plus a vertical flip.
    private static func local(_ frame: MissionControlWindowFrame, on screen: NSScreen) -> MissionControlWindowFrame {
        let rect = CGRect(
            x: frame.frame.minX - screen.frame.minX,
            y: screen.frame.maxY - frame.frame.maxY,
            width: frame.frame.width,
            height: frame.frame.height
        )
        return MissionControlWindowFrame(
            id: frame.id, bundleID: frame.bundleID, appName: frame.appName, title: frame.title,
            frame: rect, state: frame.state, isFocused: frame.isFocused
        )
    }

    private static func pointerLocation() -> CGPoint {
        let cocoa = NSEvent.mouseLocation
        let height = NSScreen.screens.first?.frame.maxY ?? 0
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
