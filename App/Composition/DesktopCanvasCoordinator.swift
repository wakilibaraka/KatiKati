import AppKit
import Combine
import QuickLookUI

/// Publishes the active desktop-canvas coordinator to Settings without allocating the canvas when disabled.
@MainActor
final class DesktopCanvasManager: ObservableObject {
    static let shared = DesktopCanvasManager()
    @Published private(set) var activeCoordinator: DesktopCanvasCoordinator?

    private init() {}

    func setActive(_ coordinator: DesktopCanvasCoordinator?) {
        activeCoordinator = coordinator
    }
}

/// Coordinates floating desktop-layer panels, Quick Reveal monitors, snapping drags, and display reflow.
@MainActor
final class DesktopCanvasCoordinator {
    let store: DesktopBoxStore
    private let settingsStore: AppSettingsStore
    private let displayTopologyStore: DisplayTopologyStore

    private var controllers: [UUID: DesktopWidgetPanelController] = [:]
    private var revealState = DesktopRevealStateMachine()
    private var blankDesktopMonitor: BlankDesktopClickMonitor?
    private var quickRevealKeyMonitor: Any?
    private var quickRevealGlobalClickMonitor: Any?
    private var quickRevealLocalClickMonitor: Any?

    private var cancellables: Set<AnyCancellable> = []
    private var defaultObservers: [NSObjectProtocol] = []
    private var workspaceWakeObserver: NSObjectProtocol?

    private var dragOriginFrames: [UUID: CGRect] = [:]
    private var resizeOriginFrame: CGRect?
    private var autoOrganizeWindowController: DesktopAutoOrganizeWindowController?

    private var lastDoubleClickEnabled = false
    private var lastShowOnAllSpaces = true
    private var lastSnapGap: CGFloat = CGFloat(DesktopCanvasConfig.defaultSnapGap)
    private var lastEdgeMargin: CGFloat = CGFloat(DesktopCanvasConfig.defaultEdgeMargin)
    private var canvasTheme = DesktopCanvasThemeState.load()

    private let topologyArchive: DesktopTopologyArchiveStore
    private var lastTopologyDisplays: [TopologyDisplay] = []
    private var lastTopologySignature = ""
    private var pendingDisconnectWork: DispatchWorkItem?
    private var moveAllUndoPlan: MoveAllWidgetsUndoPlan?
    private var idleCleanupTimer: Timer?
    private var defaultsCoalesceWork: DispatchWorkItem?
    private var lastDesktopInteraction = ProcessInfo.processInfo.systemUptime
    private var lastIdleCleanup = ProcessInfo.processInfo.systemUptime

    init(
        store: DesktopBoxStore? = nil,
        settingsStore: AppSettingsStore,
        displayTopologyStore: DisplayTopologyStore,
        topologyArchiveStore: DesktopTopologyArchiveStore? = nil
    ) {
        self.store = store ?? DesktopBoxStore()
        self.settingsStore = settingsStore
        self.displayTopologyStore = displayTopologyStore
        self.topologyArchive = topologyArchiveStore ?? DesktopTopologyArchiveStore()
        self.lastDoubleClickEnabled = doubleClickDesktop
        self.lastShowOnAllSpaces = showOnAllSpaces
        self.lastSnapGap = snapGap
        self.lastEdgeMargin = edgeMargin
    }

    var isHiddenAll: Bool { revealState.visibility == .hiddenAll }
    var isQuickRevealed: Bool { revealState.visibility == .quickRevealed }

    func start() {
        guard cancellables.isEmpty, defaultObservers.isEmpty else { return }

        Publishers.CombineLatest4(
            settingsStore.$themeMaterial,
            settingsStore.$themeVibrancy,
            settingsStore.$themeContrast,
            settingsStore.$themeTranslucency
        )
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _, _ in self?.syncPanels() }
        .store(in: &cancellables)

        displayTopologyStore.$table
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleTopologyChange() }
            .store(in: &cancellables)

        store.$items
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncPanels() }
            .store(in: &cancellables)

        observeDefaultNotification(DesktopCanvasNotification.quickReveal) { [weak self] in
            self?.toggleQuickReveal()
        }
        observeDefaultNotification(DesktopCanvasNotification.toggleHidden) { [weak self] in
            self?.toggleHideAll()
        }
        observeDefaultNotification(UserDefaults.didChangeNotification) { [weak self] in
            self?.scheduleDefaultsChanged()
        }
        workspaceWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.handleTopologyChange() } }

        DesktopManagedStorage.cleanupOrphanedStagingDirectories()
        seedDefaultWidgetsIfNeeded()
        handleTopologyChange()
        syncBlankDesktopMonitor()
        syncPanels()
        startIdleCleanupTimer()
    }

    func tearDown() {
        flushNow()
        idleCleanupTimer?.invalidate()
        idleCleanupTimer = nil
        pendingDisconnectWork?.cancel()
        pendingDisconnectWork = nil
        defaultsCoalesceWork?.cancel()
        defaultsCoalesceWork = nil
        ScreenIdentifyOverlayController.shared.dismiss()
        autoOrganizeWindowController?.close()
        autoOrganizeWindowController = nil
        removeQuickRevealMonitors()
        blankDesktopMonitor?.stop()
        blankDesktopMonitor = nil
        cancellables.removeAll()
        for observer in defaultObservers { NotificationCenter.default.removeObserver(observer) }
        defaultObservers.removeAll()
        if let workspaceWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceWakeObserver)
            self.workspaceWakeObserver = nil
        }
        for controller in controllers.values { controller.tearDown() }
        controllers.removeAll()
    }

    func flushNow() { store.flushNow() }

    // MARK: - Visibility & Quick Reveal

    func toggleQuickReveal() {
        noteDesktopInteraction()
        guard revealState.toggleQuickReveal(now: ProcessInfo.processInfo.systemUptime) else { return }
        applyCurrentVisibility()
    }

    func toggleHideAll() {
        noteDesktopInteraction()
        guard revealState.toggleHiddenAll(now: ProcessInfo.processInfo.systemUptime) else { return }
        applyCurrentVisibility()
    }

    func requestDismissQuickReveal(reason: DesktopDismissReason) {
        noteDesktopInteraction()
        guard revealState.requestDismissQuickReveal(reason: reason) else { return }
        applyCurrentVisibility()
    }

    private func noteDesktopInteraction() {
        lastDesktopInteraction = ProcessInfo.processInfo.systemUptime
    }

    /// Resource Saver's visible-idle cleanup: purge thumbnail and image caches once the desktop has
    /// gone untouched for the profile's idle window. Hidden widget surfaces are released by their panels.
    private func startIdleCleanupTimer() {
        idleCleanupTimer?.invalidate()
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.cleanupCachesIfIdle() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        idleCleanupTimer = timer
    }

    private func cleanupCachesIfIdle() {
        let now = ProcessInfo.processInfo.systemUptime
        let window = DesktopPerformanceStore.shared.settings.visibleIdleCleanupSeconds
        guard now - lastDesktopInteraction >= window,
              now - lastIdleCleanup >= max(window, 10),
              !isQuickRevealed
        else { return }
        DesktopThumbnailCache.clearAll()
        DesktopAssetStore.clearCache()
        lastIdleCleanup = now
    }

    // MARK: - Box Actions

    func presentAddFolderBoxPanel() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Add")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addFolderBox(at: url)
    }

    func addFolderBox(at url: URL) {
        let normalized = FilePathNormalization.normalized(url.path)
        if var existing = store.items.first(where: { $0.backingPath == normalized }) {
            if existing.isHidden {
                existing.isHidden = false
                store.update(existing, immediate: true)
            }
            return
        }
        let target = screenContaining(point: NSEvent.mouseLocation)
        let siblings = store.items.filter { !$0.isHidden }.map(\.frame)
        let frame = DesktopLayoutEngine.initialPlacement(
            existing: siblings, visibleFrame: target.visibleFrame, gap: snapGap, edgeMargin: edgeMargin
        )
        let item = DesktopWidgetItem(
            kind: .folder,
            title: url.lastPathComponent,
            backingPath: normalized,
            displayUUID: target.uuid,
            frame: frame,
            normalizedFrame: DesktopLayoutEngine.normalize(frame, in: target.visibleFrame)
        )
        store.add(item)
    }

    func createStarterInboxBox() {
        let starterPath = FilePathNormalization.normalized(DesktopBoxStore.defaultStarterInboxURL.path)
        if var existing = store.items.first(where: { $0.backingPath == starterPath }) {
            if existing.isHidden {
                existing.isHidden = false
                store.update(existing, immediate: true)
            }
            return
        }
        let target = screenContaining(point: NSEvent.mouseLocation)
        _ = try? store.createStarterInboxBox(
            displayUUID: target.uuid, visibleFrame: target.visibleFrame, gap: snapGap, edgeMargin: edgeMargin
        )
    }

    func addTodoBox() { addFeatureBox(kind: .todo) }

    /// One-time starter widgets so a fresh Desktop page is useful immediately.
    private func seedDefaultWidgetsIfNeeded() {
        let defaults = UserDefaults.standard
        guard DesktopCanvasConfig.shouldSeedDefaults(defaults: defaults, hasExistingItems: !store.items.isEmpty) else { return }
        defaults.set(true, forKey: DesktopCanvasConfig.seededDefaultsKey)
        for kind in DesktopCanvasConfig.defaultSeedKinds { addFeatureBox(kind: kind) }
    }

    /// One instance per feature kind; re-adding unhides the existing box instead of stacking duplicates.
    func addFeatureBox(kind: DesktopWidgetKind) {
        guard kind != .folder else { return }
        if var existing = store.items.first(where: { $0.kind == kind }) {
            if existing.isHidden {
                existing.isHidden = false
                store.update(existing, immediate: true)
            }
            return
        }
        let title: String
        let size: CGSize
        switch kind {
        case .todo: title = String(localized: "To-Do"); size = CGSize(width: 260, height: 300)
        case .quickCapture: title = String(localized: "Quick Capture"); size = CGSize(width: 260, height: 240)
        case .glance: title = String(localized: "Glance"); size = CGSize(width: 240, height: 200)
        case .weather: title = String(localized: "Weather"); size = CGSize(width: 260, height: 200)
        case .music: title = String(localized: "Vinyl Music"); size = CGSize(width: 260, height: 280)
        case .search: title = String(localized: "Search"); size = CGSize(width: 320, height: 96)
        case .wordOfTheDay: title = String(localized: "Word of the Day"); size = CGSize(width: 300, height: 200)
        case .yearProgress: title = String(localized: "Year Progress"); size = CGSize(width: 240, height: 190)
        case .keepAwake: title = String(localized: "Keep Awake"); size = CGSize(width: 240, height: 150)
        case .habitStreak: title = String(localized: "Habit Streak"); size = CGSize(width: 240, height: 200)
        case .storageGlance: title = String(localized: "Storage"); size = CGSize(width: 240, height: 190)
        case .pinnedNote: title = String(localized: "Pinned Note"); size = CGSize(width: 260, height: 220)
        case .quickPasteClipboard: title = String(localized: "Quick-Paste Clipboard"); size = CGSize(width: 260, height: 230)
        case .folder: return
        }
        let target = screenContaining(point: NSEvent.mouseLocation)
        let siblings = store.items.filter { !$0.isHidden }.map(\.frame)
        var frame = DesktopLayoutEngine.initialPlacement(
            existing: siblings, visibleFrame: target.visibleFrame, gap: snapGap, edgeMargin: edgeMargin
        )
        frame.size = size
        store.add(DesktopWidgetItem(
            kind: kind,
            title: title,
            displayUUID: target.uuid,
            frame: frame,
            normalizedFrame: DesktopLayoutEngine.normalize(frame, in: target.visibleFrame),
            capsuleMode: defaultCapsuleMode
        ))
    }

    /// New-widget default from Settings › Capsule Mode.
    private var defaultCapsuleMode: DesktopCapsuleMode {
        UserDefaults.standard.string(forKey: DesktopCanvasConfig.defaultCapsuleModeKey) == "capsule" ? .capsule : .expanded
    }

    func createManagedBox() {
        let boxID = UUID()
        guard let url = try? DesktopManagedStorage.createManagedBoxDirectory(for: boxID) else { return }
        let target = screenContaining(point: NSEvent.mouseLocation)
        let siblings = store.items.filter { !$0.isHidden }.map(\.frame)
        let frame = DesktopLayoutEngine.initialPlacement(
            existing: siblings, visibleFrame: target.visibleFrame, gap: snapGap, edgeMargin: edgeMargin
        )
        let item = DesktopWidgetItem(
            id: boxID,
            kind: .folder,
            title: String(localized: "Managed Box"),
            backingPath: url.path,
            isManagedFolder: true,
            displayUUID: target.uuid,
            frame: frame,
            normalizedFrame: DesktopLayoutEngine.normalize(frame, in: target.visibleFrame)
        )
        store.add(item)
    }

    func convertToManagedBox(id: UUID) -> String? {
        guard var item = store.item(for: id), !item.isManagedFolder, let path = item.backingPath else { return nil }
        do {
            let report = try DesktopManagedStorage.migrateToManagedStorage(
                from: URL(fileURLWithPath: path, isDirectory: true),
                boxID: id,
                moveSourceToTrashAfterVerify: false
            )
            item.backingPath = report.destinationURL.path
            item.isManagedFolder = true
            store.update(item, immediate: true)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func exportManagedBox(id: UUID) -> String? {
        guard var item = store.item(for: id), item.isManagedFolder, let path = item.backingPath else { return nil }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Export")
        guard panel.runModal() == .OK, let destDir = panel.url else { return nil }
        do {
            let report = try DesktopManagedStorage.exportManagedBox(
                from: URL(fileURLWithPath: path, isDirectory: true),
                to: destDir
            )
            item.backingPath = report.destinationURL.path
            item.isManagedFolder = false
            store.update(item, immediate: true)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func presentAutoOrganizeSheet() {
        let controller = autoOrganizeWindowController ?? DesktopAutoOrganizeWindowController()
        autoOrganizeWindowController = controller
        controller.present(
            onApply: { [weak self] plan, createBoxes in
                guard let self else { throw CocoaError(.userCancelled) }
                return try self.applyAutoOrganizePlan(plan, createBoxes: createBoxes)
            },
            onUndo: { [weak self] in
                self?.undoLastAutoOrganize() ?? 0
            }
        )
    }

    func applyAutoOrganizePlan(
        _ plan: DesktopOrganizePlan,
        createBoxes: Bool
    ) throws -> DesktopOrganizeUndoRecord {
        let record = try DesktopAutoOrganizeExecutor.apply(plan)
        if createBoxes {
            for bucket in plan.buckets where !bucket.items.isEmpty {
                addFolderBox(at: bucket.targetDirectory)
            }
        }
        return record
    }

    func undoLastAutoOrganize() -> Int {
        guard let record = DesktopAutoOrganizeExecutor.loadLastUndoRecord() else { return 0 }
        let result = DesktopAutoOrganizeExecutor.undo(record)
        return result.restoredCount
    }

    func toggleWidgetHidden(id: UUID) {
        guard let anchor = store.item(for: id) else { return }
        let nextHidden = !anchor.isHidden
        let next = store.items.map { item -> DesktopWidgetItem in
            var copy = item
            if copy.id == id || (anchor.tabGroupID != nil && copy.tabGroupID == anchor.tabGroupID) {
                copy.isHidden = nextHidden
            }
            return copy
        }
        store.replaceAll(next, immediate: true)
    }

    func removeWidget(id: UUID) {
        store.remove(id: id)
        pruneUnusedDesktopAssets()
    }

    func applyPanoramaToAllBoxes() {
        let next = store.items.map { item -> DesktopWidgetItem in
            var copy = item
            copy.appearance.background = .panorama
            return copy
        }
        store.replaceAll(next, immediate: true)
    }

    /// Collapses every visible widget to compact capsule mode.
    func collapseAllToCapsule() {
        let next = store.items.map { item -> DesktopWidgetItem in
            var copy = item
            if copy.capsuleMode == .expanded { copy.capsuleMode = .capsule }
            return copy
        }
        store.replaceAll(next, immediate: true)
    }

    /// Restores every widget from capsule/docked to full expanded mode.
    func expandAllFromCapsule() {
        let next = store.items.map { item -> DesktopWidgetItem in
            var copy = item
            copy.capsuleMode = .expanded
            return copy
        }
        store.replaceAll(next, immediate: true)
    }

    /// Sets capsule mode for a single widget by ID.
    func setCapsuleMode(_ mode: DesktopCapsuleMode, for id: UUID) {
        guard var item = store.item(for: id) else { return }
        item.capsuleMode = mode
        store.update(item, immediate: true)
    }

    func pruneUnusedDesktopAssets() {
        var refs: Set<String> = []
        for item in store.items {
            if case .customImage(let path) = item.appearance.iconBadge, !path.isEmpty {
                refs.insert(path)
            }
            if case .image(let path, _, _) = item.appearance.background, !path.isEmpty {
                refs.insert(path)
            }
        }
        if let currentPanorama = DesktopCanvasThemeState.load().panoramaImagePath, !currentPanorama.isEmpty {
            refs.insert(currentPanorama)
        }
        DesktopAssetStore.pruneUnusedAssets(referencedPaths: refs)
    }

    func revealWidgetInFinder(id: UUID) {
        guard let path = store.item(for: id)?.backingPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: - Panel Sync & Reflow

    private func syncPanels() {
        let groups = DesktopTabGroupEngine.panelGroups(from: store.items)
        let liveKeys = Set(groups.map(\.panelKey))
        for (key, controller) in controllers where !liveKeys.contains(key) {
            controller.tearDown()
            controllers.removeValue(forKey: key)
        }

        let themeStyle = settingsStore.themeMaterial
        let themeTuning = settingsStore.themeTuning
        let usesGlass = DockGlassPresentation.shouldAttemptTaskbarComposite
        let allSpaces = showOnAllSpaces

        for group in groups {
            let panelKey = group.panelKey
            let target = targetScreen(for: group.activeItem)
            let targets = groups
                .filter { $0.panelKey != panelKey }
                .map { ($0.activeItem.id, $0.activeItem.title) }

            if let existing = controllers[panelKey] {
                existing.update(
                    group: group, mergeTargets: targets, visibility: revealState.visibility,
                    themeStyle: themeStyle, themeTuning: themeTuning,
                    usesLiquidGlass: usesGlass, canvasTheme: canvasTheme,
                    canvasBounds: target.screenFrame, visibleFrame: target.visibleFrame, showOnAllSpaces: allSpaces
                )
            } else {
                let callbacks = DesktopWidgetPanelCallbacks(
                    onUpdateItem: { [weak self] updated in self?.store.update(updated, immediate: false) },
                    onRemoveBox: { [weak self] in
                        guard let id = self?.controllers[panelKey]?.activeWidgetID else { return }
                        self?.removeWidget(id: id)
                    },
                    onSelectTab: { [weak self] tabID in
                        guard let self else { return }
                        self.store.replaceAll(DesktopTabGroupEngine.selectTab(id: tabID, in: self.store.items), immediate: true)
                    },
                    onCycleTab: { [weak self] delta in
                        guard let self else { return }
                        self.store.replaceAll(DesktopTabGroupEngine.cycleTab(groupID: panelKey, delta: delta, in: self.store.items), immediate: true)
                    },
                    onDetachTab: { [weak self] tabID in
                        guard let self, let anchor = self.store.item(for: tabID) else { return }
                        let target = self.targetScreen(for: anchor)
                        let detached = DesktopTabGroupEngine.detachTab(
                            id: tabID, in: self.store.items,
                            visibleFrame: target.visibleFrame, edgeMargin: self.edgeMargin
                        )
                        self.store.replaceAll(detached, immediate: true)
                    },
                    onMergeInto: { [weak self] targetID in
                        guard let self, let activeID = self.controllers[panelKey]?.activeWidgetID else { return }
                        let merged = DesktopTabGroupEngine.merge(movingID: activeID, into: targetID, in: self.store.items)
                        self.store.replaceAll(merged, immediate: true)
                    },
                    onAcquireLock: { [weak self] lock in self?.revealState.acquireLock(lock) },
                    onReleaseLock: { [weak self] lock in self?.handleLockReleased(lock) },
                    onDragStarted: { [weak self] in self?.snapshotOriginFrames() },
                    onDragChanged: { [weak self] d, ctrl in self?.handleDrag(panelKey: panelKey, delta: d, controlHeld: ctrl, commit: false) },
                    onDragEnded: { [weak self] d, ctrl in self?.handleDrag(panelKey: panelKey, delta: d, controlHeld: ctrl, commit: true) },
                    onResizeStarted: { [weak self] in self?.snapshotResizeOrigin(panelKey: panelKey) },
                    onResizeChanged: { [weak self] h, d in self?.handleResize(panelKey: panelKey, handle: h, delta: d, commit: false) },
                    onResizeEnded: { [weak self] h, d in self?.handleResize(panelKey: panelKey, handle: h, delta: d, commit: true) }
                )
                let created = DesktopWidgetPanelController(
                    group: group, mergeTargets: targets, themeStyle: themeStyle, themeTuning: themeTuning,
                    usesLiquidGlass: usesGlass, canvasTheme: canvasTheme,
                    canvasBounds: target.screenFrame, visibleFrame: target.visibleFrame,
                    showOnAllSpaces: allSpaces, callbacks: callbacks
                )
                controllers[panelKey] = created
                created.applyVisibility(revealState.visibility, isWidgetHidden: group.activeItem.isHidden)
            }
        }
    }

    private func reflowForDisplayChange() {
        var next = DesktopTabGroupEngine.reconcile(store.items)
        for group in DesktopTabGroupEngine.panelGroups(from: next) {
            let item = group.activeItem
            let target = targetScreen(for: item)
            let updatedFrame = item.normalizedFrame.map {
                DesktopLayoutEngine.denormalize($0, in: target.visibleFrame, edgeMargin: edgeMargin)
            } ?? DesktopLayoutEngine.clamp(item.frame, in: target.visibleFrame, edgeMargin: edgeMargin)
            let norm = item.normalizedFrame ?? DesktopLayoutEngine.normalize(updatedFrame, in: target.visibleFrame)
            next = DesktopTabGroupEngine.syncGroupGeometry(
                for: item.id, frame: updatedFrame, normalizedFrame: norm, displayUUID: target.uuid, in: next
            )
        }
        store.replaceAll(next, immediate: false)
    }

    // MARK: - Multi-Display Topology Memory

    /// Connected displays in `NSScreen.screens` order (the first is the menu-bar display).
    func connectedDisplays() -> [DesktopConnectedDisplay] {
        let primaryUUID = NSScreen.screens.first.flatMap { DisplayIdentity.uuidString(for: $0) }
        return NSScreen.screens.compactMap { screen in
            guard let uuid = DisplayIdentity.uuidString(for: screen) else { return nil }
            return DesktopConnectedDisplay(
                uuid: uuid,
                title: screen.localizedName,
                isPrimary: uuid == primaryUUID,
                screenFrame: screen.frame,
                visibleFrame: screen.visibleFrame
            )
        }
    }

    func identifyScreens() {
        ScreenIdentifyOverlayController.shared.present()
    }

    /// Settings › Displays › Pin Layout: remembers the current arrangement under its signature.
    func pinCurrentLayout() {
        let displays = currentTopologyDisplays()
        guard !displays.isEmpty else { return }
        recordTopologyArchive(displays: displays)
    }

    func setDisplayBinding(for id: UUID, followMain: Bool) {
        guard var item = store.item(for: id) else { return }
        let onScreenUUID = resolvedDisplayUUID(forWidget: id)
        item.followMainDisplay = followMain
        if !followMain {
            item.displayUUID = onScreenUUID ?? item.displayUUID ?? targetScreen(for: item).uuid
        }
        store.update(item, immediate: true)
    }

    func resolvedDisplayUUID(forWidget id: UUID) -> String? {
        guard let item = store.item(for: id) else { return nil }
        return resolvedDisplayUUID(for: item, in: currentTopologyDisplays())
    }

    func setDefaultDisplay(_ uuid: String?) {
        if let uuid, !uuid.isEmpty {
            UserDefaults.standard.set(uuid, forKey: DesktopTopologyConfig.defaultDisplayUUIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: DesktopTopologyConfig.defaultDisplayUUIDKey)
        }
        reflowForDisplayChange()
    }

    /// Undoable proportional move-all: every widget from the other displays lands on `uuid`,
    /// keeping its relative position and size.
    @discardableResult
    func moveAllWidgets(toDisplay uuid: String) -> Bool {
        let displays = currentTopologyDisplays()
        guard let target = displays.first(where: { $0.uuid == uuid }) else { return false }
        let visible = store.items.filter { !$0.isHidden }
        let groups = Dictionary(grouping: visible) { item in
            resolvedDisplayUUID(for: item, in: displays) ?? target.uuid
        }
        var plans: [MoveAllWidgetsUndoPlan] = []
        for (sourceUUID, items) in groups where sourceUUID != uuid {
            guard let source = displays.first(where: { $0.uuid == sourceUUID }) else { continue }
            plans.append(DesktopMoveAllPlanner.plan(
                items: items,
                sourceDisplay: source,
                targetDisplay: target,
                edgeMargin: edgeMargin
            ))
        }
        guard !plans.isEmpty else { return false }
        let plan = DesktopMoveAllPlanner.combined(plans, targetDisplayUUID: uuid)
        moveAllUndoPlan = plan
        store.replaceAll(plan.applying(store.items), immediate: true)
        return true
    }

    var canUndoMoveAll: Bool { moveAllUndoPlan != nil }

    @discardableResult
    func undoMoveAllWidgets() -> Bool {
        guard let plan = moveAllUndoPlan else { return false }
        store.replaceAll(plan.applying(store.items, forward: false), immediate: true)
        moveAllUndoPlan = nil
        return true
    }

    private func handleTopologyChange() {
        let current = currentTopologyDisplays()
        guard !current.isEmpty else {
            reflowForDisplayChange()
            return
        }
        let signature = DisplayTopologySignature.make(current.map(\.uuid))
        let previous = lastTopologyDisplays
        lastTopologyDisplays = current
        guard signature != lastTopologySignature else {
            reflowForDisplayChange()
            return
        }
        lastTopologySignature = signature

        // Remember the arrangement we are leaving at the exact geometry it had.
        if !previous.isEmpty {
            recordTopologyArchive(displays: previous)
        }

        pendingDisconnectWork?.cancel()
        pendingDisconnectWork = nil

        guard !previous.isEmpty else {
            applyInitialArrangement(current: current, signature: signature)
            recordTopologyArchive(displays: current)
            reflowForDisplayChange()
            return
        }

        let previousUUIDs = Set(previous.map(\.uuid))
        let currentUUIDs = Set(current.map(\.uuid))
        let removed = previous.filter { !currentUUIDs.contains($0.uuid) }
        let added = currentUUIDs.subtracting(previousUUIDs)

        if removed.isEmpty {
            if !added.isEmpty {
                restoreReconnected(added, current: current)
            }
            reflowForDisplayChange()
        } else {
            scheduleDisconnect(removed: removed, current: current)
        }
    }

    /// A topology this Mac has not seen: exact archive match first, otherwise seed the most similar
    /// remembered arrangement onto the closest connected display.
    private func applyInitialArrangement(current: [TopologyDisplay], signature: String) {
        if let entry = topologyArchive.entry(forSignature: signature) {
            let plan = DisplayDisconnectPlanner.restorePlan(
                reconnectedUUIDs: Set(current.map(\.uuid)),
                widgets: topologyWidgets(for: current),
                placements: entry.placements
            )
            applyTopologyPlan(plan, displays: current)
            return
        }
        guard let best = topologyArchive.bestEntry(matching: current) else { return }
        let plan = DisplayDisconnectPlanner.seedPlan(
            entry: best,
            current: current,
            widgets: topologyWidgets(for: current)
        )
        applyTopologyPlan(plan, displays: current)
    }

    private func scheduleDisconnect(removed: [TopologyDisplay], current: [TopologyDisplay]) {
        let grace = DesktopTopologyConfig.graceSeconds()
        guard grace > 0 else {
            applyDisconnect(removed: removed, current: current)
            reflowForDisplayChange()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingDisconnectWork = nil
            let live = self.currentTopologyDisplays()
            self.applyDisconnect(removed: removed, current: live.isEmpty ? current : live)
            self.reflowForDisplayChange()
        }
        pendingDisconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + grace, execute: work)
    }

    private func applyDisconnect(removed: [TopologyDisplay], current: [TopologyDisplay]) {
        guard !current.isEmpty else { return }
        let plan = DisplayDisconnectPlanner.disconnectPlan(
            disconnected: removed,
            current: current,
            widgets: topologyWidgets(for: current),
            action: DesktopTopologyConfig.disconnectAction()
        )
        applyTopologyPlan(plan, displays: current)
    }

    private func restoreReconnected(_ added: Set<String>, current: [TopologyDisplay]) {
        let signature = DisplayTopologySignature.make(current.map(\.uuid))
        let archived = topologyArchive.placements(forSignature: signature)
        let placements = archived.isEmpty
            ? (topologyArchive.bestEntry(matching: current)?.placements ?? [:])
            : archived
        let plan = DisplayDisconnectPlanner.restorePlan(
            reconnectedUUIDs: added,
            widgets: topologyWidgets(for: current),
            placements: placements
        )
        applyTopologyPlan(plan, displays: current)
    }

    private func recordTopologyArchive(displays: [TopologyDisplay]) {
        guard !displays.isEmpty else { return }
        topologyArchive.record(
            signature: DisplayTopologySignature.make(displays.map(\.uuid)),
            displays: displays,
            placements: DisplayDisconnectPlanner.placements(from: topologyWidgets(for: displays))
        )
    }

    private func applyTopologyPlan(_ plan: DisplayTopologyPlan, displays: [TopologyDisplay]) {
        guard !plan.isEmpty else { return }
        var next = store.items
        for index in next.indices {
            guard let move = plan.moves[next[index].id],
                  let display = displays.first(where: { $0.uuid == move.displayUUID })
            else { continue }
            next[index].displayUUID = move.displayUUID
            next[index].followMainDisplay = false
            next[index].capsuleMode = move.capsuleMode
            next[index].normalizedFrame = move.normalizedFrame
            next[index].frame = DesktopLayoutEngine.denormalize(
                move.normalizedFrame,
                in: display.visibleFrame.cgRect,
                edgeMargin: edgeMargin
            )
        }
        store.replaceAll(next, immediate: true)
    }

    private func currentTopologyDisplays() -> [TopologyDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let uuid = DisplayIdentity.uuidString(for: screen) else { return nil }
            return TopologyDisplay(
                uuid: uuid,
                screenFrame: screen.frame,
                visibleFrame: screen.visibleFrame
            )
        }
    }

    /// Planner snapshots resolve a widget's home even when that display just disappeared, so the
    /// disconnect planner can see which screen it came from.
    private func topologyWidgets(for displays: [TopologyDisplay]) -> [DesktopTopologyWidget] {
        let byUUID = Dictionary(uniqueKeysWithValues: displays.map { ($0.uuid, $0) })
        let fallbackVisible = displays.first?.visibleFrame.cgRect
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return store.items.map { item in
            let home: String?
            if !item.followMainDisplay, let uuid = item.displayUUID {
                home = uuid
            } else {
                home = displayContaining(frame: item.frame, in: displays)
                    ?? DesktopTopologyConfig.defaultDisplayUUID()
                    ?? displays.first?.uuid
            }
            let visible = home.flatMap { byUUID[$0] }?.visibleFrame.cgRect ?? fallbackVisible
            return DesktopTopologyWidget(
                item: item,
                resolvedDisplayUUID: home,
                visibleFrame: visible
            )
        }
    }

    private func resolvedDisplayUUID(for item: DesktopWidgetItem, in displays: [TopologyDisplay]) -> String? {
        if !item.followMainDisplay, let uuid = item.displayUUID,
           displays.contains(where: { $0.uuid == uuid }) {
            return uuid
        }
        return displayContaining(frame: item.frame, in: displays)
            ?? DesktopTopologyConfig.defaultDisplayUUID()
            ?? displays.first?.uuid
    }

    private func displayContaining(frame: CGRect, in displays: [TopologyDisplay]) -> String? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return displays.first { $0.screenFrame.cgRect.contains(center) }?.uuid
    }

    // MARK: - Drag & Resize

    private func snapshotOriginFrames() {
        let groups = DesktopTabGroupEngine.panelGroups(from: store.items)
        dragOriginFrames = Dictionary(
            uniqueKeysWithValues: groups.map { ($0.panelKey, controllers[$0.panelKey]?.currentFrame ?? $0.activeItem.frame) }
        )
    }

    private func snapshotResizeOrigin(panelKey: UUID) {
        let groups = DesktopTabGroupEngine.panelGroups(from: store.items)
        resizeOriginFrame = controllers[panelKey]?.currentFrame
            ?? groups.first(where: { $0.panelKey == panelKey })?.activeItem.frame
    }

    private func handleDrag(panelKey: UUID, delta: CGSize, controlHeld: Bool, commit: Bool) {
        noteDesktopInteraction()
        let groups = DesktopTabGroupEngine.panelGroups(from: store.items)
        guard let group = groups.first(where: { $0.panelKey == panelKey }) else { return }

        if controlHeld {
            let target = targetScreen(for: group.activeItem)
            let moved = DesktopLayoutEngine.boundedGroupMove(
                frames: visibleOriginFrames(sameDisplayAs: group.activeItem, groups: groups), delta: delta,
                visibleFrame: target.visibleFrame, edgeMargin: edgeMargin
            )
            for (movedKey, rect) in moved { controllers[movedKey]?.applyLiveFrame(rect, canvasBounds: target.screenFrame) }
            if commit {
                var next = store.items
                for (movedKey, rect) in moved {
                    guard let movedGroup = groups.first(where: { $0.panelKey == movedKey }) else { continue }
                    let norm = DesktopLayoutEngine.normalize(rect, in: target.visibleFrame)
                    next = DesktopTabGroupEngine.syncGroupGeometry(
                        for: movedGroup.activeItem.id, frame: rect, normalizedFrame: norm, displayUUID: target.uuid, in: next
                    )
                }
                store.replaceAll(next, immediate: true)
                dragOriginFrames.removeAll()
            }
            return
        }

        guard let origin = dragOriginFrames[panelKey] else { return }
        let candidate = origin.offsetBy(dx: delta.width, dy: delta.height)
        let target = screenContaining(point: CGPoint(x: candidate.midX, y: candidate.midY))
        let snapped = DesktopLayoutEngine.snapMove(
            candidate: candidate, others: otherFrames(excludingPanelKey: panelKey, displayUUID: target.uuid, groups: groups),
            visibleFrame: target.visibleFrame, gap: snapGap, edgeMargin: edgeMargin
        )
        controllers[panelKey]?.applyLiveFrame(snapped.frame, canvasBounds: target.screenFrame)
        if commit {
            if NSEvent.modifierFlags.contains(.option) {
                let mouse = NSEvent.mouseLocation
                let dropCenter = CGPoint(x: snapped.frame.midX, y: snapped.frame.midY)
                if let (_, targetCtrl) = controllers.first(where: { key, ctrl in
                    key != panelKey && (ctrl.contains(screenPoint: mouse) || ctrl.contains(screenPoint: dropCenter))
                }) {
                    let merged = DesktopTabGroupEngine.merge(
                        movingID: group.activeItem.id, into: targetCtrl.activeWidgetID, in: store.items
                    )
                    store.replaceAll(merged, immediate: true)
                    dragOriginFrames.removeAll()
                    return
                }
            }
            let norm = DesktopLayoutEngine.normalize(snapped.frame, in: target.visibleFrame)
            let next = DesktopTabGroupEngine.syncGroupGeometry(
                for: group.activeItem.id, frame: snapped.frame, normalizedFrame: norm, displayUUID: target.uuid, in: store.items
            )
            store.replaceAll(next, immediate: true)
            dragOriginFrames.removeAll()
        }
    }

    private func handleResize(panelKey: UUID, handle: DesktopResizeHandle, delta: CGSize, commit: Bool) {
        noteDesktopInteraction()
        let groups = DesktopTabGroupEngine.panelGroups(from: store.items)
        guard let origin = resizeOriginFrame,
              let group = groups.first(where: { $0.panelKey == panelKey })
        else { return }
        let target = targetScreen(for: group.activeItem)
        let snapped = DesktopLayoutEngine.snapResize(
            origin: origin, handle: handle, delta: delta,
            others: otherFrames(excludingPanelKey: panelKey, displayUUID: target.uuid, groups: groups),
            visibleFrame: target.visibleFrame, gap: snapGap, edgeMargin: edgeMargin
        )
        controllers[panelKey]?.applyLiveFrame(snapped.frame, canvasBounds: target.screenFrame)
        if commit {
            let norm = DesktopLayoutEngine.normalize(snapped.frame, in: target.visibleFrame)
            let next = DesktopTabGroupEngine.syncGroupGeometry(
                for: group.activeItem.id, frame: snapped.frame, normalizedFrame: norm, displayUUID: target.uuid, in: store.items
            )
            store.replaceAll(next, immediate: true)
            resizeOriginFrame = nil
        }
    }

    // MARK: - Monitors & Helpers

    private func observeDefaultNotification(_ name: Notification.Name, handler: @escaping @MainActor () -> Void) {
        defaultObservers.append(
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler() }
            }
        )
    }

    private func applyCurrentVisibility() {
        for group in DesktopTabGroupEngine.panelGroups(from: store.items) {
            controllers[group.panelKey]?.applyVisibility(revealState.visibility, isWidgetHidden: group.activeItem.isHidden)
        }
        revealState.visibility == .quickRevealed ? installQuickRevealMonitors() : removeQuickRevealMonitors()
    }

    private func handleLockReleased(_ lock: DesktopInteractionLock) {
        if revealState.releaseLock(lock) { applyCurrentVisibility() }
    }

    private func installQuickRevealMonitors() {
        guard quickRevealKeyMonitor == nil else { return }
        quickRevealKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event }
            let wasRevealed = self.revealState.visibility == .quickRevealed
            self.requestDismissQuickReveal(reason: .escapeKey)
            return (wasRevealed && self.revealState.visibility != .quickRevealed) ? nil : event
        }
        let handleClick: () -> Void = { [weak self] in
            guard let self else { return }
            let pt = NSEvent.mouseLocation
            if self.controllers.values.contains(where: { $0.contains(screenPoint: pt) }) { return }
            if let ql = QLPreviewPanel.shared(), ql.isVisible, ql.frame.contains(pt) { return }
            self.requestDismissQuickReveal(reason: .outsideClick)
        }
        quickRevealGlobalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            Task { @MainActor in handleClick() }
        }
        quickRevealLocalClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            handleClick()
            return event
        }
    }

    private func removeQuickRevealMonitors() {
        if let m = quickRevealKeyMonitor { NSEvent.removeMonitor(m) }
        if let m = quickRevealGlobalClickMonitor { NSEvent.removeMonitor(m) }
        if let m = quickRevealLocalClickMonitor { NSEvent.removeMonitor(m) }
        quickRevealKeyMonitor = nil
        quickRevealGlobalClickMonitor = nil
        quickRevealLocalClickMonitor = nil
    }

    private func scheduleDefaultsChanged() {
        defaultsCoalesceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.defaultsCoalesceWork = nil
            self?.handleDefaultsChanged()
        }
        defaultsCoalesceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func handleDefaultsChanged() {
        var needsPanelSync = false
        if doubleClickDesktop != lastDoubleClickEnabled {
            lastDoubleClickEnabled = doubleClickDesktop
            syncBlankDesktopMonitor()
        }
        if showOnAllSpaces != lastShowOnAllSpaces {
            lastShowOnAllSpaces = showOnAllSpaces
            needsPanelSync = true
        }
        let nextTheme = DesktopCanvasThemeState.load()
        if nextTheme != canvasTheme {
            canvasTheme = nextTheme
            needsPanelSync = true
        }
        if needsPanelSync {
            syncPanels()
        }
        if snapGap != lastSnapGap || edgeMargin != lastEdgeMargin {
            lastSnapGap = snapGap
            lastEdgeMargin = edgeMargin
            reflowForDisplayChange()
        }
    }

    private func syncBlankDesktopMonitor() {
        if doubleClickDesktop {
            if blankDesktopMonitor == nil {
                blankDesktopMonitor = BlankDesktopClickMonitor { [weak self] in self?.toggleHideAll() }
            }
            blankDesktopMonitor?.start()
        } else {
            blankDesktopMonitor?.stop()
            blankDesktopMonitor = nil
        }
    }

    private var snapGap: CGFloat {
        let raw = UserDefaults.standard.object(forKey: DesktopCanvasConfig.snapGapKey) as? Double
            ?? DesktopCanvasConfig.defaultSnapGap
        return CGFloat(DesktopCanvasConfig.clampedSnapGap(raw))
    }

    private var edgeMargin: CGFloat {
        let raw = UserDefaults.standard.object(forKey: DesktopCanvasConfig.edgeMarginKey) as? Double
            ?? DesktopCanvasConfig.defaultEdgeMargin
        return CGFloat(DesktopCanvasConfig.clampedEdgeMargin(raw))
    }

    private var showOnAllSpaces: Bool {
        UserDefaults.standard.object(forKey: DesktopCanvasConfig.showOnAllSpacesKey) as? Bool ?? true
    }

    private var doubleClickDesktop: Bool {
        UserDefaults.standard.bool(forKey: DesktopCanvasConfig.doubleClickDesktopKey)
    }

    private func fallbackPrimaryScreen() -> (uuid: String?, visibleFrame: CGRect, screenFrame: CGRect) {
        let primary = NSScreen.screens.first
        let fallback = CGRect(x: 0, y: 0, width: 1440, height: 900)
        return (
            primary.flatMap { DisplayIdentity.uuidString(for: $0) },
            primary?.visibleFrame ?? fallback,
            primary?.frame ?? fallback
        )
    }

    private func targetScreen(for item: DesktopWidgetItem) -> (uuid: String?, visibleFrame: CGRect, screenFrame: CGRect) {
        var byUUID: [String: (visibleFrame: CGRect, screenFrame: CGRect)] = [:]
        for screen in NSScreen.screens {
            if let uuid = DisplayIdentity.uuidString(for: screen) {
                byUUID[uuid] = (screen.visibleFrame, screen.frame)
            }
        }
        if let resolved = DesktopLayoutEngine.resolveDisplay(
            for: item,
            table: displayTopologyStore.table,
            defaultDisplayUUID: DesktopTopologyConfig.defaultDisplayUUID()
        ),
           let pair = byUUID[resolved.uuid] {
            return (resolved.uuid, pair.visibleFrame, pair.screenFrame)
        }
        return fallbackPrimaryScreen()
    }

    private func screenContaining(point: CGPoint) -> (uuid: String?, visibleFrame: CGRect, screenFrame: CGRect) {
        for screen in NSScreen.screens where screen.frame.contains(point) {
            return (DisplayIdentity.uuidString(for: screen), screen.visibleFrame, screen.frame)
        }
        return fallbackPrimaryScreen()
    }

    private func otherFrames(
        excludingPanelKey panelKey: UUID,
        displayUUID: String?,
        groups: [DesktopPanelGroup]
    ) -> [CGRect] {
        groups.compactMap { group in
            guard group.panelKey != panelKey, !group.activeItem.isHidden else { return nil }
            let targetUUID = targetScreen(for: group.activeItem).uuid
            guard displayUUID == nil || targetUUID == displayUUID else { return nil }
            return controllers[group.panelKey]?.currentFrame ?? group.activeItem.frame
        }
    }

    private func visibleOriginFrames(
        sameDisplayAs anchor: DesktopWidgetItem,
        groups: [DesktopPanelGroup]
    ) -> [UUID: CGRect] {
        let anchorUUID = targetScreen(for: anchor).uuid
        var map: [UUID: CGRect] = [:]
        for group in groups where !group.activeItem.isHidden {
            if anchorUUID == nil || targetScreen(for: group.activeItem).uuid == anchorUUID {
                map[group.panelKey] = dragOriginFrames[group.panelKey]
                    ?? controllers[group.panelKey]?.currentFrame
                    ?? group.activeItem.frame
            }
        }
        return map
    }
}
