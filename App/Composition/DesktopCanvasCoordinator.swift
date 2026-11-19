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

    init(
        store: DesktopBoxStore? = nil,
        settingsStore: AppSettingsStore,
        displayTopologyStore: DisplayTopologyStore
    ) {
        self.store = store ?? DesktopBoxStore()
        self.settingsStore = settingsStore
        self.displayTopologyStore = displayTopologyStore
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
            .sink { [weak self] _ in self?.reflowForDisplayChange() }
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
            self?.handleDefaultsChanged()
        }
        workspaceWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.reflowForDisplayChange() } }

        DesktopManagedStorage.cleanupOrphanedStagingDirectories()
        reflowForDisplayChange()
        syncBlankDesktopMonitor()
        syncPanels()
    }

    func tearDown() {
        flushNow()
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
        guard revealState.toggleQuickReveal(now: ProcessInfo.processInfo.systemUptime) else { return }
        applyCurrentVisibility()
    }

    func toggleHideAll() {
        guard revealState.toggleHiddenAll(now: ProcessInfo.processInfo.systemUptime) else { return }
        applyCurrentVisibility()
    }

    func requestDismissQuickReveal(reason: DesktopDismissReason) {
        guard revealState.requestDismissQuickReveal(reason: reason) else { return }
        applyCurrentVisibility()
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

    func addTodoBox() {
        if var existing = store.items.first(where: { $0.kind == .todo }) {
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
        store.add(DesktopWidgetItem(
            kind: .todo,
            title: String(localized: "To-Do"),
            displayUUID: target.uuid,
            frame: frame,
            normalizedFrame: DesktopLayoutEngine.normalize(frame, in: target.visibleFrame)
        ))
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
                    canvasBounds: target.screenFrame, showOnAllSpaces: allSpaces
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
                    canvasBounds: target.screenFrame, showOnAllSpaces: allSpaces, callbacks: callbacks
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
        if let resolved = DesktopLayoutEngine.resolveDisplay(for: item, table: displayTopologyStore.table),
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
