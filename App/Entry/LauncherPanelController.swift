import AppKit
import SwiftUI

private final class LauncherPanel: NonConstrainingPanel {
    override var canBecomeKey: Bool { true }
}

/// Full-screen launcher panel (Phase 7B-L2), summoned by ⌥Space or the left FAB. Created on first use; the indexer
/// runs only while the panel is up. ⌥Space while open closes it.
@MainActor
final class LauncherPanelController {
    private var panel: NSPanel?
    private let indexer = LauncherIndexer()
    private let model = LauncherModel()
    private let store = LauncherStore(url: LauncherStore.defaultURL)
    /// Read at each summon so a Settings change applies immediately.
    var searchPosition: () -> LauncherSearchPosition = { .top }
    var scrollDirection: () -> LauncherScrollDirection = { .vertical }
    var look: () -> (theme: LauncherTheme, tint: LauncherTint) = { (.system, .none) }
    /// Height the KatiKati bottom bar occupies (it floats above `visibleFrame`), so the launcher never sits under it.
    var bottomBarReserve: () -> Double = { 0 }
    private var backdrop: LauncherBackdrop?

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle() { isShown ? dismiss() : show() }

    func show() {
        guard !isShown else { return }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        model.state = store.load()
        model.searchPosition = searchPosition()
        model.scrollDirection = scrollDirection()
        model.screenInsets = LauncherScreenInsets.compute(
            frame: screen.frame, visible: screen.visibleFrame, safeTop: Double(screen.safeAreaInsets.top),
            extraBottom: bottomBarReserve())
        model.query = ""
        indexer.start()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let look = self.look()
        panel.appearance = backdrop?.apply(theme: look.theme, tint: look.tint, screen: screen)
        panel.setFrame(screen.frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        model.focusNonce += 1
    }

    func dismiss() {
        panel?.orderOut(nil)
        indexer.stop()
        model.query = ""
    }

    func tearDown() {
        dismiss()
        panel = nil
    }

    private func launch(_ app: LauncherApp) {
        LauncherAppIndex.recordLaunch(&model.state.usage, bundleID: app.bundleID, at: Date())
        try? store.save(model.state)
        dismiss()
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: NSWorkspace.OpenConfiguration())
    }

    private func togglePin(_ app: LauncherApp) {
        model.state.pinned = LauncherAppIndex.togglePin(model.state.pinned, app.bundleID)
        try? store.save(model.state)
    }

    private func makePanel() -> NSPanel {
        let panel = LauncherPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let blur = LauncherBackdrop()
        backdrop = blur
        let host = NSHostingView(rootView: LauncherView(
            indexer: indexer, model: model,
            onLaunch: { [weak self] in self?.launch($0) },
            onTogglePin: { [weak self] in self?.togglePin($0) }, onClose: { [weak self] in self?.dismiss() }))
        host.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: blur.leadingAnchor), host.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            host.topAnchor.constraint(equalTo: blur.topAnchor), host.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        panel.contentView = blur
        return panel
    }
}
