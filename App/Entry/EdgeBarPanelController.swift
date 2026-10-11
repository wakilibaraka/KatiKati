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

    init(slotKey: EdgeSlotSet.SlotKey) {
        self.slotKey = slotKey
    }

    var allSpacesPanels: [NSPanel] { panel.map { [$0] } ?? [] }

    /// Positions the panel on `screen` and shows/hides it. `visible == false` (sibling island
    /// bar hidden by fullscreen) hides it with the same reconcile pass — atomic per display.
    func update(screen: NSScreen?, visible: Bool, gap: CGFloat, margin: CGFloat, metrics: PanelLayoutMetrics) {
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
        let panel = self.panel ?? makePanel(frame: frame)
        self.panel = panel
        if panel.frame != frame { panel.setFrame(frame, display: true) }
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

    func tearDown() {
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
