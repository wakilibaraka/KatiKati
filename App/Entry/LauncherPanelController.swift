import AppKit
import Combine
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
    var scrollDirection: () -> LauncherScrollDirection = { .horizontal }
    /// 57b: fullscreen (default), a centred card or a popover under the summoning point. Read at each summon.
    var presentation: () -> LauncherPresentation = { .default }
    var look: () -> (theme: LauncherTheme, tint: LauncherTint) = { (.system, .none) }
    /// Height the KatiKati bottom bar occupies (it floats above `visibleFrame`), so the launcher never sits under it.
    var bottomBarReserve: () -> Double = { 0 }
    /// Phase 18d: space a KatiKati side rail takes on the left / right.
    var sideBarReserve: () -> (leading: Double, trailing: Double) = { (0, 0) }
    /// Bundle ids of the apps kept in the dock; they open page 1 as Pinned.
    var keptApps: () -> [String] = { [] }
    private var backdrop: LauncherBackdrop?
    private var prefsObserver: AnyCancellable?
    private var scrollMonitor: Any?
    private var scrollAccum: CGFloat = 0
    private var scrollFired = false
    private var lastWheelTurn = Date.distantPast

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle() { isShown ? dismiss() : show() }

    func show() {
        guard !isShown else { return }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        model.state = store.load()
        model.searchPosition = searchPosition()
        model.scrollDirection = scrollDirection()
        let mode = presentation()
        let frame = LauncherPanelFrame.rect(mode: mode, screen: screen.frame, visible: screen.visibleFrame,
                                            anchor: NSEvent.mouseLocation)
        // Fullscreen still has to clear the menu bar and notch; a windowed card already sits inside `visibleFrame`.
        model.screenInsets = mode == .fullscreen
            ? LauncherScreenInsets.compute(
                frame: screen.frame, visible: screen.visibleFrame, safeTop: Double(screen.safeAreaInsets.top),
                extraBottom: bottomBarReserve(),
                extraLeading: sideBarReserve().leading, extraTrailing: sideBarReserve().trailing)
            : (top: 0, bottom: bottomBarReserve(),
               leading: sideBarReserve().leading, trailing: sideBarReserve().trailing)
        model.query = ""
        model.editing = false
        model.focusedID = nil
        model.openFolderID = nil
        model.prefs = LauncherPrefs.load()
        model.keptIDs = keptApps()
        model.runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        indexer.start()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let look = self.look()
        panel.appearance = backdrop?.apply(theme: look.theme, tint: look.tint, screen: screen)
        backdrop?.setBlurStrength(model.prefs.blur)
        backdrop?.setCornerRadius(mode == .fullscreen ? 0 : 22)
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        model.focusNonce += 1
        model.pageIndex = 0
        installScrollMonitor()
    }

    /// Swipe or scroll turns pages while the launcher shows sliding pages: a trackpad swipe turns one page per gesture,
    /// a mouse wheel one page per notch (debounced).
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
            return event
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
    }

    private func handleScroll(_ event: NSEvent) {
        guard isShown, model.query.isEmpty, model.scrollDirection == .horizontal else { return }
        // Line-based wheel events may carry only the raw deltas.
        let dx = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.deltaX
        let dy = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
        let delta = abs(dx) > abs(dy) ? -dx : -dy
        // A real trackpad swipe reports gesture phases; anything without them (mouse wheel, remote or synthetic scrolling)
        // is treated as one page per click.
        if event.hasPreciseScrollingDeltas, !(event.phase.isEmpty && event.momentumPhase.isEmpty) {
            if event.phase == .began { scrollAccum = 0; scrollFired = false }
            guard event.momentumPhase.isEmpty else { return }
            scrollAccum += delta
            if !scrollFired, abs(scrollAccum) > 30 {
                scrollFired = true
                model.pageTurns.send(scrollAccum > 0 ? 1 : -1)
            }
            if event.phase == .ended || event.phase == .cancelled { scrollAccum = 0; scrollFired = false }
        } else if abs(delta) > 0.01, Date().timeIntervalSince(lastWheelTurn) > 0.3 {
            lastWheelTurn = Date()
            model.pageTurns.send(delta > 0 ? 1 : -1)
        }
    }

    func dismiss() {
        if panel?.isVisible == true { persist() }
        removeScrollMonitor()
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

    private func toggleHidden(_ app: LauncherApp) {
        model.state.hidden = LauncherOrdering.toggleHidden(model.state.hidden, app.bundleID)
        try? store.save(model.state)
    }

    private func reveal(_ app: LauncherApp) {
        dismiss()
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
    }

    private func copyPath(_ app: LauncherApp) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(app.path, forType: .string)
    }

    /// Drag-reorder in All Apps: the order on screen becomes the stored order, then the app moves in front of `target`.
    private func move(_ bundleID: String, before target: LauncherApp?) {
        let shown = shownIDs()
        model.state.order = LauncherOrdering.move(shown, moving: bundleID, before: target?.bundleID ?? shown.first)
        try? store.save(model.state)
    }

    private func persist() { try? store.save(model.state) }

    /// What All Apps shows right now (loose apps + folder cells), in the user's order — the base for drag/folder edits.
    private func shownIDs() -> [String] {
        let visible = indexer.apps.filter { !model.state.hidden.contains($0.bundleID) }
        let cells = LauncherFolders.loose(visible, folders: model.state.folders) + model.state.folders.map(LauncherFolders.cell)
        return LauncherOrdering.ordered(cells.sorted(by: LauncherAppIndex.nameOrder), by: model.state.order).map(\.bundleID)
    }

    /// Edit mode: dropping an app on another app makes a folder where the target was; dropping it on a folder adds it.
    private func dropOnto(_ dragged: String, target: LauncherApp) {
        guard dragged != target.bundleID, !LauncherFolders.isFolderID(dragged) else { return }
        if LauncherFolders.isFolderID(target.bundleID) {
            model.state.folders = LauncherFolders.add(model.state.folders, appID: dragged, to: target.bundleID)
        } else {
            makeFolder(with: [target.bundleID, dragged], replacing: target.bundleID)
        }
        persist()
    }

    private func newFolder(_ app: LauncherApp) {
        makeFolder(with: [app.bundleID], replacing: app.bundleID)
        persist()
    }

    private func makeFolder(with appIDs: [String], replacing target: String) {
        let seeded = shownIDs()
        let id = LauncherFolders.newID()
        model.state.folders = LauncherFolders.create(model.state.folders, id: id, name: String(localized: "Folder"), appIDs: appIDs)
        model.state.order = LauncherFolders.order(seeded, replacing: target, with: id)
        model.openFolderID = nil
    }

    /// Phase 30b: confirm and move an app / its data to the Trash.
    private func confirmRemoval(_ app: LauncherApp, _ removal: AppRemoval) {
        AppRemovalService.confirmAndPerform(bundleID: app.bundleID, name: app.name, appPath: app.path, removal: removal)
    }

    private func quickAction(_ action: LauncherQuickAction) {
        dismiss()
        switch action {
        case .open(let url), .webSearch(let url): NSWorkspace.shared.open(url)
        }
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
        let host = NSHostingView(rootView: LauncherView(indexer: indexer, model: model, actions: LauncherActions(
            launch: { [weak self] in self?.launch($0) },
            togglePin: { [weak self] in self?.togglePin($0) },
            toggleHidden: { [weak self] in self?.toggleHidden($0) },
            reveal: { [weak self] in self?.reveal($0) },
            copyPath: { [weak self] in self?.copyPath($0) },
            move: { [weak self] id, target in self?.move(id, before: target) },
            close: { [weak self] in self?.dismiss() },
            persist: { [weak self] in self?.persist() },
            quickAction: { [weak self] in self?.quickAction($0) },
            dropOnto: { [weak self] id, target in self?.dropOnto(id, target: target) },
            newFolder: { [weak self] in self?.newFolder($0) },
            uninstall: { [weak self] in self?.confirmRemoval($0, .uninstall) },
            deleteData: { [weak self] in self?.confirmRemoval($0, .deleteData) })))
        prefsObserver = model.$prefs.sink { [weak self] in self?.backdrop?.setBlurStrength($0.blur) }
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
