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
    var scrollDirection: () -> LauncherScrollDirection = { .vertical }
    /// Whether the start page shows the pinned row above All Apps.
    var pinnedRow: () -> Bool = { true }
    /// Windowed or fullscreen presentation. Read at each summon.
    var presentation: () -> LauncherPresentation = { .default }
    var look: () -> (theme: LauncherTheme, tint: LauncherTint) = { (.system, .none) }
    /// Height the KatiKati bottom bar occupies (it floats above `visibleFrame`), so the launcher never sits under it.
    var bottomBarReserve: () -> Double = { 0 }
    /// Phase 18d: space a KatiKati side rail takes on the left / right.
    var sideBarReserve: () -> (leading: Double, trailing: Double) = { (0, 0) }
    /// Bundle ids of the apps kept in the dock; they open page 1 as Pinned.
    var keptApps: () -> [String] = { [] }
    /// Stashed app bundle IDs from PopStore / DrawerStore so Launcher's Drawer preset surfaces them.
    var stashedApps: () -> [String] = { [] }
    /// Live screen rect of the Dock's Launcher tile for `aboveIcon` anchoring.
    var anchorRect: () -> CGRect? = { nil }
    var isKeptInDock: (String) -> Bool = { _ in false }
    var toggleKeepInDock: (String) -> Void = { _ in }
    var openSettings: () -> Void = {}
    /// Called just before the launcher appears so competing floating panels (Quick Settings, Widgets, Drawers) dismiss cleanly.
    var onWillShow: () -> Void = {}
    private var backdrop: LauncherBackdrop?
    private var prefsObserver: AnyCancellable?
    private var scrollMonitor: Any?
    private var outsideGlobalMonitor: Any?
    private var scrollAccum: CGFloat = 0
    private var scrollFired = false
    private var lastWheelTurn = Date.distantPast
    private var recentFilesGeneration = 0

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle() { isShown ? dismiss() : show() }

    func show() {
        guard !isShown else { return }
        onWillShow()
        model.prefs = LauncherPrefs.load()
        let anchor = anchorRect()
        let mouseScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        let anchorScreen = anchor.flatMap { rect in NSScreen.screens.first { $0.frame.intersects(rect) } }
        let screen = (model.prefs.anchorMode == .aboveIcon ? (anchorScreen ?? mouseScreen) : mouseScreen) ?? NSScreen.main
        guard let screen else { return }
        model.state = store.load()
        model.searchPosition = searchPosition()
        model.scrollDirection = scrollDirection()
        model.pinnedRow = pinnedRow()
        let mode = presentation()
        let rails = sideBarReserve()
        let anchorX = model.prefs.anchorMode == .aboveIcon ? anchor?.midX : nil
        let frame = LauncherPanelFrame.rect(mode: mode, screen: screen.frame, visible: screen.visibleFrame,
                                            dockReserve: CGFloat(bottomBarReserve()),
                                            leading: CGFloat(rails.leading), trailing: CGFloat(rails.trailing),
                                            anchorX: anchorX, anchorMode: model.prefs.anchorMode)
        // Only fullscreen spans the full screen and needs safe-area/bar insets; windowed cards already sit inside `visible`.
        model.presentation = mode
        model.screenInsets = mode == .fullscreen
            ? LauncherScreenInsets.compute(
                frame: screen.frame, visible: screen.visibleFrame, safeTop: Double(screen.safeAreaInsets.top),
                extraBottom: bottomBarReserve(),
                extraLeading: rails.leading, extraTrailing: rails.trailing)
            : (top: 0, bottom: 0, leading: 0, trailing: 0)
        model.query = ""
        model.editing = false
        model.focusedID = nil
        model.openFolderID = nil
        model.showingAllApps = false
        model.selectedCategory = .favorites
        model.keptIDs = keptApps()
        model.stashedAppIDs = stashedApps()
        model.runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        recentFilesGeneration &+= 1
        let recentGen = recentFilesGeneration
        let usageSnapshot = model.state.usage
        Task.detached(priority: .userInitiated) { [weak self] in
            let loaded = LauncherPanelController.loadRecentFiles(usage: usageSnapshot)
            await MainActor.run { [weak self] in
                guard let self, self.recentFilesGeneration == recentGen else { return }
                self.model.recentFiles = loaded
            }
        }
        if model.prefs.searchScope.recentFiles { FileIndexService.shared.prepare() }
        indexer.start()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let look = self.look()
        panel.appearance = backdrop?.apply(theme: look.theme, tint: look.tint, screen: screen)
        backdrop?.setBlurStrength(model.prefs.blur)
        backdrop?.setCornerRadius(mode == .fullscreen ? 0 : (mode == .drawer ? 18 : 20))
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        model.focusNonce += 1
        model.pageIndex = 0
        installScrollMonitor()
    }

    /// Swipe or scroll turns pages while the launcher shows sliding pages: a trackpad swipe turns one page per gesture,
    /// a mouse wheel one page per notch (debounced).
    private func installScrollMonitor() {
        if outsideGlobalMonitor == nil {
            outsideGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let panel = self.panel, panel.isVisible else { return }
                    if !panel.frame.contains(NSEvent.mouseLocation) {
                        self.dismiss()
                    }
                }
            }
        }
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
            return event
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        if let outsideGlobalMonitor { NSEvent.removeMonitor(outsideGlobalMonitor) }
        outsideGlobalMonitor = nil
    }

    private func handleScroll(_ event: NSEvent) {
        let pagedMode = model.presentation == .centred || model.presentation == .fullscreen
        guard isShown, pagedMode, model.query.isEmpty, model.scrollDirection == .horizontal else { return }
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
        case .open(let url), .webSearch(let url):
            NSWorkspace.shared.open(url)
        case .askAI(let query):
            let term = query.isEmpty ? "AI Assistant" : query
            if let url = URL(string: "https://duckduckgo.com/?q=" + (("! " + term).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func runMacro(_ macro: BarMacro) {
        if macro.needsConfirm {
            let alert = NSAlert()
            alert.messageText = String(localized: "Are you sure?")
            alert.informativeText = macro.title
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "Continue"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        dismiss()
        BarActionService.run(macro)
    }

    private func quitApp(_ app: LauncherApp) {
        let targets = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
            .filter { $0.activationPolicy == .regular }
        for running in targets { _ = running.terminate() }
        model.runningIDs.remove(app.bundleID)
    }

    private func openPlace(_ url: URL) {
        dismiss()
        NSWorkspace.shared.open(url)
    }

    nonisolated private static func loadRecentFiles(usage: [String: LauncherUsage]) -> [LauncherRecentItem] {
        var items: [LauncherRecentItem] = []
        var seen = Set<String>()
        let topApps = usage.sorted { $0.value.lastLaunched > $1.value.lastLaunched }.prefix(4).map(\.key)
        for bid in topApps {
            for url in RecentDocumentsReader.recentDocuments(for: bid, maxCount: 2) {
                let path = url.path
                guard !seen.contains(path), FileManager.default.fileExists(atPath: path) else { continue }
                seen.insert(path)
                let parent = url.deletingLastPathComponent().lastPathComponent
                items.append(LauncherRecentItem(name: url.lastPathComponent, path: path, subtitle: parent))
                if items.count >= 4 { return items }
            }
        }
        for folder in RecentDocumentsReader.recentFinderFolders(maxCount: 4) where !seen.contains(folder.url.path) {
            seen.insert(folder.url.path)
            items.append(LauncherRecentItem(name: folder.title, path: folder.url.path, subtitle: String(localized: "Folder")))
            if items.count >= 4 { break }
        }
        return items
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
            deleteData: { [weak self] in self?.confirmRemoval($0, .deleteData) },
            runMacro: { [weak self] in self?.runMacro($0) },
            quitApp: { [weak self] in self?.quitApp($0) },
            isKeptInDock: { [weak self] in self?.isKeptInDock($0) ?? false },
            toggleKeepInDock: { [weak self] app in
                self?.toggleKeepInDock(app.bundleID)
                self?.model.keptIDs = self?.keptApps() ?? []
            },
            openPlace: { [weak self] in self?.openPlace($0) },
            openSettings: { [weak self] in
                self?.dismiss()
                self?.openSettings()
            })))
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
