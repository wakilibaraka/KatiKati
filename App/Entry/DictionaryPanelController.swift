import AppKit
import SwiftUI

/// The Dictionary panel: glass card anchored above the Dictionary Dock icon with a `v` pointer
/// by default, or floating cleanly at Bottom / Center Float without `v`. Key-capable; closes on
/// Esc, chevron, toggling the icon, or outside click according to `UtilityDismissalBehavior`.
@MainActor
final class DictionaryPanelController {
    private final class DictionaryPanel: NonConstrainingPanel {
        override var canBecomeKey: Bool { true }
        override func cancelOperation(_ sender: Any?) { orderOut(nil) }
    }

    private var panel: NSPanel?
    private let model = DictionaryPanelModel()
    private let arrow = StackPopupArrowModel()
    private var resignObserver: NSObjectProtocol?
    private var anchorRect: CGRect?
    private var isPinned = false

    var utilityConfigProvider: () -> DockUtilitiesConfig = { .default }
    var stripPlacementProvider: () -> StripPlacement = { .bottom }
    var usesLiquidGlassProvider: () -> Bool = { false }

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle(anchorRect: CGRect? = nil) {
        if let anchorRect { self.anchorRect = anchorRect }
        isShown ? dismiss() : show(word: nil, anchorRect: anchorRect)
    }

    func show(word: String?, anchorRect: CGRect? = nil) {
        if let anchorRect { self.anchorRect = anchorRect }
        let targetScreen = anchorRect.flatMap { rect in NSScreen.screens.first { $0.frame.intersects(rect) } }
            ?? NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main
        guard let screen = targetScreen else { return }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let word { model.lookup(word) }

        let cfg = utilityConfigProvider()
        let placement = stripPlacementProvider()
        let layout = PanelGeometry.utilityPanelFrame(
            plateSize: DictionaryPanelView.plateSize,
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
    }

    func dismiss() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let panel = DictionaryPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let view = DictionaryPanelView(
            model: model,
            arrow: arrow,
            usesLiquidGlass: usesLiquidGlassProvider(),
            isPinned: Binding(get: { [weak self] in self?.isPinned ?? false },
                              set: { [weak self] in self?.isPinned = $0 }),
            onClose: { [weak self] in self?.dismiss() }
        )
        panel.contentView = NSHostingView(rootView: view)
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Exclude clicks inside the Dock Dictionary icon so toggle() handles close cleanly.
                if let anchor = self.anchorRect, anchor.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation) {
                    return
                }
                let cfg = self.utilityConfigProvider()
                if cfg.dismissalBehavior.dismissesOnOutsideClick(
                    isTerminal: false,
                    placement: cfg.effectivePlacementForPreset,
                    isPinned: self.isPinned
                ) {
                    self.dismiss()
                }
            }
        }
        return panel
    }
}
