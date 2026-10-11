import AppKit

/// One edge-bar panel (Phase 7A foundation): a non-activating, all-Spaces panel hugging a screen
/// side. Content is a placeholder until the notes / status / widgets slices land. Owned by
/// `TaskbarScreenOrchestrator`, one per `EdgeSlotSet.SlotKey`; never part of `units`.
@MainActor
final class EdgeBarPanelController {
    static let placeholderWidth: CGFloat = 56
    static let placeholderHeight: CGFloat = 160

    let slotKey: EdgeSlotSet.SlotKey
    private(set) var panel: NSPanel?
    private var isHidden = true
    /// Auto-hide (7A-3): `autoHidden` is separate from `isHidden` (fullscreen / island hide).
    private var autoHideEnabled = false
    private var autoHidden = false
    /// Island-side verdict (fullscreen / sibling hidden); auto-hide never overrides it.
    private var shouldBeVisible = false
    private var idleTimer: Timer?
    private var lastFrame: CGRect = .zero
    private var lastScreenFrame: CGRect = .zero

    init(slotKey: EdgeSlotSet.SlotKey) {
        self.slotKey = slotKey
    }

    var allSpacesPanels: [NSPanel] { panel.map { [$0] } ?? [] }

    /// Positions the panel on `screen` and shows/hides it. `visible == false` (sibling island
    /// bar hidden by fullscreen) hides it with the same reconcile pass — atomic per display.
    func update(screen: NSScreen?, visible: Bool, autoHide: Bool = false, gap: CGFloat, margin: CGFloat, metrics: PanelLayoutMetrics) {
        if autoHideEnabled != autoHide {
            autoHideEnabled = autoHide
            autoHidden = false
            cancelIdleTimer()
        }
        shouldBeVisible = false
        guard visible, let screen else {
            hide()
            return
        }
        let frame = PanelGeometry.edgeBarTargetFrame(
            side: slotKey.side,
            contentHeight: Self.placeholderHeight,
            width: Self.placeholderWidth,
            on: PanelCoordinator.screenGeometry(screen),
            gap: gap,
            margin: margin,
            metrics: metrics
        )
        guard frame.height > 0, frame.width > 0 else {
            hide()
            return
        }
        shouldBeVisible = true
        lastFrame = frame
        lastScreenFrame = screen.frame
        let panel = self.panel ?? makePanel(frame: frame)
        self.panel = panel
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if autoHideEnabled && autoHidden {
            hide()
            return
        }
        if isHidden {
            panel.orderFrontRegardless()
            isHidden = false
        }
    }

    func hide() {
        guard !isHidden else { return }
        panel?.orderOut(nil)
        isHidden = true
    }

    /// Called from the orchestrator's existing mouse poll; no timers run while the bar is hidden.
    func pollMouse(_ mouse: CGPoint) {
        guard autoHideEnabled, lastFrame != .zero else { return }
        let zone = EdgeBarAutoHide.hotZone(side: slotKey.side, screenFrame: lastScreenFrame, barFrame: lastFrame)
        let action = EdgeBarAutoHide.action(
            isHidden: autoHidden,
            mouseInHotZone: zone.contains(mouse),
            mouseInBar: lastFrame.contains(mouse)
        )
        switch action {
        case .none: break
        case .reveal:
            autoHidden = false
            if shouldBeVisible, isHidden, let panel {
                panel.orderFrontRegardless()
                isHidden = false
            }
        case .armIdleHide:
            guard idleTimer == nil, !isHidden else { return }
            let timer = Timer(timeInterval: EdgeBarAutoHide.idleDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.idleTimerFired() }
            }
            RunLoop.main.add(timer, forMode: .common)
            idleTimer = timer
        case .cancelIdleHide:
            cancelIdleTimer()
        }
    }

    private func idleTimerFired() {
        idleTimer = nil
        let mouse = NSEvent.mouseLocation
        let zone = EdgeBarAutoHide.hotZone(side: slotKey.side, screenFrame: lastScreenFrame, barFrame: lastFrame)
        guard EdgeBarAutoHide.action(isHidden: false, mouseInHotZone: zone.contains(mouse),
                                     mouseInBar: lastFrame.contains(mouse)) == .armIdleHide else { return }
        autoHidden = true
        hide()
    }

    private func cancelIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    func tearDown() {
        cancelIdleTimer()
        panel?.orderOut(nil)
        panel = nil
        isHidden = true
    }

    private func makePanel(frame: CGRect) -> NSPanel {
        let panel = NonConstrainingPanel(
            contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = PanelCollectionBehavior.standard
        panel.isFloatingPanel = true
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        let plate = NSVisualEffectView(frame: CGRect(origin: .zero, size: frame.size))
        plate.material = .hudWindow
        plate.state = .active
        plate.wantsLayer = true
        plate.layer?.cornerRadius = 14
        plate.autoresizingMask = [.width, .height]
        panel.contentView = plate
        return panel
    }
}
