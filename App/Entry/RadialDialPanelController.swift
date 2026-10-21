import AppKit
import SwiftUI
import Combine

/// Phase 31e: Manages the floating, non-activating radial dial panel and handles keyboard/mouse invocation.
@MainActor
final class RadialDialPanelController: ObservableObject {
    static let shared = RadialDialPanelController()

    private final class RadialDialPanel: NonConstrainingPanel {
        // Key (without activating the app) so the dial can take 1–9 / arrows / Return itself.
        override var canBecomeKey: Bool { true }
        override func cancelOperation(_ sender: Any?) { orderOut(nil) }
    }

    private var panel: NSPanel?
    private var outsideMonitor: Any?
    private var escKeyMonitor: Any?
    private var escLocalKeyMonitor: Any?
    private var mouseTriggerMonitor: Any?
    private var localMouseTriggerMonitor: Any?
    private var pointerMonitors: [Any] = []
    private var releaseMonitors: [Any] = []
    private var shownAt = Date.distantPast
    private var openedByMouse = false
    private let state = RadialDialState()

    @Published private(set) var isShown: Bool = false
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "com.katikati.dial.enabled")
            setupMouseTriggerMonitor()
        }
    }

    @Published var theme: RadialDialTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: "com.katikati.dial.theme")
        }
    }

    @Published var mouseTrigger: RadialMouseTrigger {
        didSet {
            UserDefaults.standard.set(mouseTrigger.rawValue, forKey: "com.katikati.dial.mouseTrigger")
            setupMouseTriggerMonitor()
        }
    }

    @Published var triggerMode: RadialTriggerMode {
        didSet {
            UserDefaults.standard.set(triggerMode.rawValue, forKey: "com.katikati.dial.triggerMode")
        }
    }

    private var pages: [RadialDialPage] = RadialDialPresets.defaultPages()

    init() {
        let storedEnabled = UserDefaults.standard.object(forKey: "com.katikati.dial.enabled") as? Bool ?? true
        let storedThemeRaw = UserDefaults.standard.string(forKey: "com.katikati.dial.theme") ?? RadialDialTheme.lilacGlass.rawValue
        let storedMouseRaw = UserDefaults.standard.string(forKey: "com.katikati.dial.mouseTrigger") ?? RadialMouseTrigger.off.rawValue
        let storedModeRaw = UserDefaults.standard.string(forKey: "com.katikati.dial.triggerMode") ?? RadialTriggerMode.tapToggle.rawValue

        self.isEnabled = storedEnabled
        self.theme = RadialDialTheme(rawValue: storedThemeRaw) ?? .lilacGlass
        self.mouseTrigger = RadialMouseTrigger(rawValue: storedMouseRaw) ?? .off
        self.triggerMode = RadialTriggerMode(rawValue: storedModeRaw) ?? .tapToggle

        setupMouseTriggerMonitor()
        NotificationCenter.default.addObserver(self, selector: #selector(defaultsDidChange), name: UserDefaults.didChangeNotification, object: nil)
    }

    @objc private func defaultsDidChange() {
        let storedEnabled = UserDefaults.standard.object(forKey: "com.katikati.dial.enabled") as? Bool ?? true
        let storedThemeRaw = UserDefaults.standard.string(forKey: "com.katikati.dial.theme") ?? RadialDialTheme.lilacGlass.rawValue
        let storedMouseRaw = UserDefaults.standard.string(forKey: "com.katikati.dial.mouseTrigger") ?? RadialMouseTrigger.off.rawValue
        let storedModeRaw = UserDefaults.standard.string(forKey: "com.katikati.dial.triggerMode") ?? RadialTriggerMode.tapToggle.rawValue

        if isEnabled != storedEnabled { isEnabled = storedEnabled }
        if theme.rawValue != storedThemeRaw, let t = RadialDialTheme(rawValue: storedThemeRaw) { theme = t }
        if mouseTrigger.rawValue != storedMouseRaw, let m = RadialMouseTrigger(rawValue: storedMouseRaw) { mouseTrigger = m }
        if triggerMode.rawValue != storedModeRaw, let md = RadialTriggerMode(rawValue: storedModeRaw) { triggerMode = md }
    }

    func toggle(page: RadialDialPageID? = nil, viaMouse: Bool = false) {
        if isShown {
            dismiss()
        } else {
            show(page: page, viaMouse: viaMouse)
        }
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func show(page: RadialDialPageID? = nil, viaMouse: Bool = false) {
        guard isEnabled else { return }
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }

        let dialSize = RadialDialMetrics.panelSize
        let panel = self.panel ?? makePanel()
        self.panel = panel

        state.pageIndex = page.flatMap { id in pages.firstIndex { $0.id == id } } ?? 0
        state.hoveredSector = nil
        state.isCenterHovered = false
        state.hubZone = 0

        let rootView = RadialDialView(
            pages: pages,
            state: state,
            theme: theme,
            onPointerUp: { [weak self] point in self?.pointerUp(at: point) }
        )

        let host = NSHostingView(rootView: rootView)
        host.frame = NSRect(x: 0, y: 0, width: dialSize, height: dialSize)
        panel.contentView = host

        // Position centered on cursor, clamped to screen visibleFrame
        let mouse = NSEvent.mouseLocation
        let visible = screen.visibleFrame
        let x = min(max(mouse.x - dialSize / 2, visible.minX + 8), visible.maxX - dialSize - 8)
        let y = min(max(mouse.y - dialSize / 2, visible.minY + 8), visible.maxY - dialSize - 8)

        panel.setFrame(NSRect(x: x, y: y, width: dialSize, height: dialSize), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey()
        isShown = true
        shownAt = Date()
        openedByMouse = viaMouse
        installOutsideMonitor()
        installEscMonitors()
        installPointerMonitors()
        trackPointer()
    }

    func dismiss() {
        guard isShown else { return }
        isShown = false
        RadialSnapPreviewPanelController.shared.hidePreview()
        removeOutsideMonitor()
        removeEscMonitors()
        removePointerMonitors()
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduceMotion ? 0 : 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // A re-summon during the fade keeps the panel.
            if self?.isShown == false { panel.orderOut(nil) }
        })
    }

    func tearDown() {
        dismiss()
        panel?.orderOut(nil)
        if let mouseTriggerMonitor {
            NSEvent.removeMonitor(mouseTriggerMonitor)
            self.mouseTriggerMonitor = nil
        }
        if let localMouseTriggerMonitor {
            NSEvent.removeMonitor(localMouseTriggerMonitor)
            self.localMouseTriggerMonitor = nil
        }
    }

    // MARK: Pointer, paging and keyboard

    private var currentPage: RadialDialPage { pages[min(max(state.pageIndex, 0), pages.count - 1)] }

    private func trackPointer() {
        guard isShown, let panel else { return }
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x - panel.frame.minX, y: panel.frame.maxY - mouse.y)
        let hit = RadialDialGeometry.hitTest(
            point: point,
            center: RadialDialMetrics.center,
            count: currentPage.items.count,
            innerRadius: RadialDialMetrics.innerRadius,
            outerRadius: RadialDialMetrics.outerRadius
        )
        var sector: Int?
        var inCenter = false
        if case .sector(let idx) = hit { sector = idx }
        if case .center = hit { inCenter = true }
        let zone = inCenter ? hubZone(for: point) : 0
        guard sector != state.hoveredSector || inCenter != state.isCenterHovered || zone != state.hubZone else { return }
        if sector != nil && sector != state.hoveredSector {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        state.hoveredSector = sector
        state.isCenterHovered = inCenter
        state.hubZone = zone
        updateSnapPreview(screen: panel.screen)
    }

    /// Left / right chevron column of the hub, else the hub body.
    private func hubZone(for point: CGPoint) -> Int {
        let dx = point.x - RadialDialMetrics.center.x
        return currentPage.items.isEmpty || pages.count < 2 ? 0 : (dx < -26 ? -1 : (dx > 26 ? 1 : 0))
    }

    private func updateSnapPreview(screen: NSScreen?) {
        let action: RadialDialActionType?
        if state.isCenterHovered, state.hubZone == 0 {
            action = currentPage.centerItem?.action
        } else if let idx = state.hoveredSector, idx < currentPage.items.count {
            action = currentPage.items[idx].action
        } else {
            action = nil
        }
        if case .snap(let position)? = action, let screen = screen ?? NSScreen.main {
            RadialSnapPreviewPanelController.shared.showPreview(for: position, on: screen, theme: theme)
        } else {
            RadialSnapPreviewPanelController.shared.hidePreview()
        }
    }

    private func pointerUp(at point: CGPoint) {
        let hit = RadialDialGeometry.hitTest(
            point: point,
            center: RadialDialMetrics.center,
            count: currentPage.items.count,
            innerRadius: RadialDialMetrics.innerRadius,
            outerRadius: RadialDialMetrics.outerRadius
        )
        switch hit {
        case .center:
            let zone = hubZone(for: point)
            if zone != 0 { step(zone) } else if let item = currentPage.centerItem { select(item) }
        case .sector(let idx):
            if idx < currentPage.items.count { select(currentPage.items[idx]) }
        case .outside:
            dismiss()
        }
    }

    private func select(_ item: RadialDialItem) {
        RadialSnapPreviewPanelController.shared.hidePreview()
        if case .page(let id) = item.action {
            go(to: id)
        } else {
            handleAction(item.action)
        }
    }

    private func go(to id: RadialDialPageID) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        setPage(index)
    }

    private func step(_ delta: Int) {
        guard pages.count > 1 else { return }
        setPage((state.pageIndex + delta + pages.count) % pages.count)
    }

    private func setPage(_ index: Int) {
        RadialSnapPreviewPanelController.shared.hidePreview()
        withAnimation(reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.3, dampingFraction: 0.78)) {
            state.pageIndex = index
            state.hoveredSector = nil
            state.isCenterHovered = false
            state.hubZone = 0
        }
        trackPointer()
    }

    /// Hold & Release: letting go of the summoning button picks the wedge under the cursor.
    /// A quick click (no wedge, under 0.3 s) leaves the dial open like a tap.
    private func mouseReleased() {
        guard isShown, openedByMouse, triggerMode == .holdRelease else { return }
        trackPointer()
        if let idx = state.hoveredSector, idx < currentPage.items.count {
            select(currentPage.items[idx])
        } else if Date().timeIntervalSince(shownAt) >= 0.3 {
            dismiss()
        }
    }

    /// 1–9 and 0 pick wedges, ← → / Tab turn the page, Return picks the center, ⌫ goes home.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        switch event.keyCode {
        case 53: dismiss()
        case 123: step(-1)
        case 124: step(1)
        case 48: step(event.modifierFlags.contains(.shift) ? -1 : 1)
        case 36, 76: if let item = currentPage.centerItem { select(item) }
        case 51: go(to: .main)
        default:
            guard let digit = event.charactersIgnoringModifiers.flatMap({ Int($0) }) else { return false }
            let index = (digit + 9) % 10   // 1 → 0 … 9 → 8, 0 → 9
            guard index < currentPage.items.count else { return true }
            select(currentPage.items[index])
        }
        return true
    }

    private func installPointerMonitors() {
        guard pointerMonitors.isEmpty else { return }
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let ups: NSEvent.EventTypeMask = [.rightMouseUp, .otherMouseUp]
        pointerMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: moves) { [weak self] _ in
                DispatchQueue.main.async { self?.trackPointer() }
            },
            NSEvent.addLocalMonitorForEvents(matching: moves) { [weak self] event in
                self?.trackPointer()
                return event
            },
            NSEvent.addGlobalMonitorForEvents(matching: ups) { [weak self] _ in
                DispatchQueue.main.async { self?.mouseReleased() }
            },
            NSEvent.addLocalMonitorForEvents(matching: ups) { [weak self] event in
                self?.mouseReleased()
                return event
            },
        ].compactMap { $0 }
    }

    private func removePointerMonitors() {
        pointerMonitors.forEach(NSEvent.removeMonitor)
        pointerMonitors = []
    }

    private func handleAction(_ action: RadialDialActionType) {
        dismiss()
        switch action {
        case .snap(let position):
            WindowSnapService.apply(position)
        case .launchApp(let bundleID, _):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        case .mediaPlayPause:
            NowPlayingService().togglePlayPause()
        case .mediaNext:
            NowPlayingService().nextTrack()
        case .mediaPrevious:
            NowPlayingService().previousTrack()
        case .captureArea:
            CaptureController.captureAreaToClipboard()
        case .captureWindow:
            CaptureController.captureWindowToClipboard()
        case .captureOCR:
            BarActionService.run(.ocr)
        case .openShelf:
            AppDelegate.shared?.toggleShelf()
        case .clipboard:
            AppDelegate.shared?.commandBarPanel.toggle()
        case .toggleTiling:
            TilingEngine.shared.setEnabled(!TilingEngine.shared.isEnabled)
        case .page, .custom:
            break
        }
    }

    private func makePanel() -> NSPanel {
        let panel = RadialDialPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }

    private func installOutsideMonitor() {
        guard outsideMonitor == nil else { return }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func removeOutsideMonitor() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        outsideMonitor = nil
    }

    private func installEscMonitors() {
        guard escKeyMonitor == nil else { return }
        escKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                DispatchQueue.main.async {
                    self?.dismiss()
                }
            }
        }
        escLocalKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func removeEscMonitors() {
        if let escKeyMonitor { NSEvent.removeMonitor(escKeyMonitor) }
        escKeyMonitor = nil
        if let escLocalKeyMonitor { NSEvent.removeMonitor(escLocalKeyMonitor) }
        escLocalKeyMonitor = nil
    }

    private func setupMouseTriggerMonitor() {
        if let mouseTriggerMonitor {
            NSEvent.removeMonitor(mouseTriggerMonitor)
            self.mouseTriggerMonitor = nil
        }
        if let localMouseTriggerMonitor {
            NSEvent.removeMonitor(localMouseTriggerMonitor)
            self.localMouseTriggerMonitor = nil
        }

        guard isEnabled && mouseTrigger != .off else { return }

        // Register global mouse event monitor matching rightMouseDown and otherMouseDown
        mouseTriggerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return }
            if self.matchesMouseTrigger(event) {
                DispatchQueue.main.async {
                    self.toggle(viaMouse: true)
                }
            }
        }

        localMouseTriggerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            if self.matchesMouseTrigger(event) {
                DispatchQueue.main.async {
                    self.toggle(viaMouse: true)
                }
                return nil
            }
            return event
        }
    }

    private func matchesMouseTrigger(_ event: NSEvent) -> Bool {
        switch mouseTrigger {
        case .off:
            return false
        case .middleClick:
            return event.type == .otherMouseDown && event.buttonNumber == 2 && !event.modifierFlags.contains(.option)
        case .controlRightClick:
            return event.type == .rightMouseDown && event.modifierFlags.contains(.control)
        case .optionRightClick:
            return event.type == .rightMouseDown && event.modifierFlags.contains(.option)
        case .commandRightClick:
            return event.type == .rightMouseDown && event.modifierFlags.contains(.command)
        case .shiftRightClick:
            return event.type == .rightMouseDown && event.modifierFlags.contains(.shift)
        case .optionMiddleClick:
            return event.type == .otherMouseDown && event.buttonNumber == 2 && event.modifierFlags.contains(.option)
        case .button4:
            return event.type == .otherMouseDown && event.buttonNumber == 3
        case .button5:
            return event.type == .otherMouseDown && event.buttonNumber == 4
        }
    }
}
