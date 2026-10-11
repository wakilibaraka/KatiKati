import AppKit
import SwiftUI

/// One edge-bar panel (Phase 7A foundation): a non-activating, all-Spaces panel hugging a screen
/// side. Content is a placeholder until the notes / status / widgets slices land. Owned by
/// `TaskbarScreenOrchestrator`, one per `EdgeSlotSet.SlotKey`; never part of `units`.
@MainActor
final class EdgeBarPanelController {
    let slotKey: EdgeSlotSet.SlotKey
    private let service: SystemStatusService
    private let popup = EdgeStatusPopupController()
    private var content: [EdgeBarContent] = []
    private var host: NSHostingView<EdgeBarContentView>?
    private var lastVisibleFrame: CGRect = .zero
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

    init(slotKey: EdgeSlotSet.SlotKey, service: SystemStatusService) {
        self.slotKey = slotKey
        self.service = service
    }

    var allSpacesPanels: [NSPanel] { panel.map { [$0] } ?? [] }

    /// Positions the panel on `screen` and shows/hides it. `visible == false` (sibling island
    /// bar hidden by fullscreen) hides it with the same reconcile pass — atomic per display.
    func update(screen: NSScreen?, visible: Bool, content: [EdgeBarContent], autoHide: Bool = false, gap: CGFloat, margin: CGFloat, metrics: PanelLayoutMetrics) {
        if autoHideEnabled != autoHide {
            autoHideEnabled = autoHide
            autoHidden = false
            cancelIdleTimer()
        }
        shouldBeVisible = false
        guard visible, let screen, !content.isEmpty else {
            popup.dismiss()
            hide()
            return
        }
        let frame = PanelGeometry.edgeBarTargetFrame(
            side: slotKey.side,
            contentHeight: EdgeBarLayout.contentHeight(content),
            width: EdgeBarLayout.width,
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
        lastVisibleFrame = screen.visibleFrame
        let panel = self.panel ?? makePanel(frame: frame)
        self.panel = panel
        if self.content != content || host == nil {
            self.content = content
            installContent(in: panel)
        }
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
        popup.dismiss()
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
            mouseInBar: lastFrame.contains(mouse),
            popupOpen: popup.isShown
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
                                     mouseInBar: lastFrame.contains(mouse),
                                     popupOpen: popup.isShown) == .armIdleHide else { return }
        autoHidden = true
        hide()
    }

    private func cancelIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    func tearDown() {
        popup.tearDown()
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
        return panel
    }

    private func installContent(in panel: NSPanel) {
        let root = EdgeBarContentView(content: content, service: service) { [weak self] kind, rect in
            self?.statusTapped(kind, localRect: rect)
        }
        let plate = NSVisualEffectView(frame: CGRect(origin: .zero, size: panel.frame.size))
        plate.material = .hudWindow
        plate.state = .active
        plate.wantsLayer = true
        plate.layer?.cornerRadius = 14
        plate.layer?.masksToBounds = true
        plate.autoresizingMask = [.width, .height]
        let host = NSHostingView(rootView: root)
        host.frame = plate.bounds
        host.autoresizingMask = [.width, .height]
        plate.addSubview(host)
        panel.contentView = plate
        self.host = host
    }

    /// SwiftUI reports the tile in top-left view space; convert to bottom-left screen space.
    private func statusTapped(_ kind: StatusKind, localRect: CGRect) {
        guard let panel else { return }
        let anchor = CGRect(
            x: panel.frame.minX + localRect.minX,
            y: panel.frame.maxY - localRect.maxY,
            width: localRect.width, height: localRect.height
        )
        popup.toggle(kind, anchor: anchor, side: slotKey.side, visibleFrame: lastVisibleFrame, service: service)
    }
}
