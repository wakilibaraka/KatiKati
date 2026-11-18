import AppKit
import SwiftUI

/// The Terminal panel: glass card anchored above the Terminal Dock icon with a `v` pointer by
/// default, or floating cleanly at Bottom / Center Float without `v`. Hiding keeps shells running
/// (hide ≠ kill); dismissal on outside clicks follows `UtilityDismissalBehavior` (default persistent).
@MainActor
final class TerminalPanelController {
    private final class TerminalPanel: NonConstrainingPanel {
        override var canBecomeKey: Bool { true }
    }

    private var panel: NSPanel?
    private lazy var model = TerminalPanelModel()
    private let arrow = StackPopupArrowModel()
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var anchorRect: CGRect?
    private var isPinned = false

    var utilityConfigProvider: () -> DockUtilitiesConfig = { .default }
    var stripPlacementProvider: () -> StripPlacement = { .bottom }
    var usesLiquidGlassProvider: () -> Bool = { false }

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle(anchorRect: CGRect? = nil) {
        if let anchorRect { self.anchorRect = anchorRect }
        isShown ? dismiss() : show(anchorRect: anchorRect)
    }

    func show(anchorRect: CGRect? = nil) {
        if let anchorRect { self.anchorRect = anchorRect }
        let targetScreen = anchorRect.flatMap { rect in NSScreen.screens.first { $0.frame.intersects(rect) } }
            ?? NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main
        guard let screen = targetScreen else { return }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        let cfg = utilityConfigProvider()
        let placement = stripPlacementProvider()
        let layout = PanelGeometry.utilityPanelFrame(
            plateSize: TerminalPanelView.plateSize,
            anchorVisibleRect: self.anchorRect,
            placement: cfg.popoverPlacement,
            flyoutPreset: cfg.flyoutPreset,
            stripPlacement: placement,
            on: PanelCoordinator.screenGeometry(screen)
        )
        arrow.edge = placement == .left ? .leading : (placement == .right ? .trailing : .bottom)
        arrow.isHidden = !layout.showsArrow
        arrow.offsetFromCenter = layout.arrowOffsetFromCenter
        panel.setFrame(layout.frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        installClickMonitorsIfNeeded()
    }

    func dismiss() {
        removeClickMonitors()
        panel?.orderOut(nil)
    }

    private func installClickMonitorsIfNeeded() {
        removeClickMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.dismissIfConfiguredOutside()
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor [weak self] in self?.dismissIfConfiguredOutside() }
        }
    }

    private func removeClickMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
    }

    private func dismissIfConfiguredOutside() {
        guard let panel, panel.isVisible else { return }
        let mouse = NSEvent.mouseLocation
        let plate = PanelGeometry.folderPopupPlateFrame(panelFrame: panel.frame)
        guard !plate.contains(mouse) else { return }
        if let anchorRect, anchorRect.insetBy(dx: -6, dy: -6).contains(mouse) { return }
        let cfg = utilityConfigProvider()
        if cfg.dismissalBehavior.dismissesOnOutsideClick(
            isTerminal: true,
            placement: cfg.effectivePlacementForPreset,
            isPinned: isPinned
        ) {
            dismiss()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = TerminalPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let view = TerminalPanelView(
            model: model,
            arrow: arrow,
            usesLiquidGlass: usesLiquidGlassProvider(),
            isPinned: Binding(get: { [weak self] in self?.isPinned ?? false },
                              set: { [weak self] in self?.isPinned = $0 }),
            onClose: { [weak self] in self?.dismiss() }
        )
        panel.contentView = NSHostingView(rootView: view)
        return panel
    }
}
