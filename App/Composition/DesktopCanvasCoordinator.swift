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

    private var lastDoubleClickEnabled = false
    private var lastShowOnAllSpaces = true
    private var lastSnapGap: CGFloat = CGFloat(DesktopCanvasConfig.defaultSnapGap)
    private var lastEdgeMargin: CGFloat = CGFloat(DesktopCanvasConfig.defaultEdgeMargin)

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

        reflowForDisplayChange()
        syncBlankDesktopMonitor()
        syncPanels()
    }

    func tearDown() {
        flushNow()
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

    func toggleWidgetHidden(id: UUID) {
        guard var item = store.item(for: id) else { return }
        item.isHidden.toggle()
        store.update(item, immediate: true)
    }

    func removeWidget(id: UUID) { store.remove(id: id) }

    func revealWidgetInFinder(id: UUID) {
        guard let path = store.item(for: id)?.backingPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: - Panel Sync & Reflow

    private func syncPanels() {
        let liveIDs = Set(store.items.map(\.id))
        for (id, controller) in controllers where !liveIDs.contains(id) {
            controller.tearDown()
            controllers.removeValue(forKey: id)
        }

        let themeStyle = settingsStore.themeMaterial
        let themeTuning = settingsStore.themeTuning
        let usesGlass = DockGlassPresentation.shouldAttemptTaskbarComposite
        let allSpaces = showOnAllSpaces

        for item in store.items {
            if let existing = controllers[item.id] {
                existing.update(
                    item: item, visibility: revealState.visibility, themeStyle: themeStyle,
                    themeTuning: themeTuning, usesLiquidGlass: usesGlass, showOnAllSpaces: allSpaces
                )
            } else {
                let id = item.id
                let callbacks = DesktopWidgetPanelCallbacks(
                    onUpdateItem: { [weak self] updated in self?.store.update(updated, immediate: false) },
                    onRemoveBox: { [weak self] in self?.store.remove(id: id) },
                    onAcquireLock: { [weak self] lock in self?.revealState.acquireLock(lock) },
                    onReleaseLock: { [weak self] lock in self?.handleLockReleased(lock) },
                    onDragStarted: { [weak self] in self?.snapshotOriginFrames() },
                    onDragChanged: { [weak self] d, ctrl in self?.handleDrag(id: id, delta: d, controlHeld: ctrl, commit: false) },
                    onDragEnded: { [weak self] d, ctrl in self?.handleDrag(id: id, delta: d, controlHeld: ctrl, commit: true) },
                    onResizeStarted: { [weak self] in self?.snapshotResizeOrigin(id: id) },
                    onResizeChanged: { [weak self] h, d in self?.handleResize(id: id, handle: h, delta: d, commit: false) },
                    onResizeEnded: { [weak self] h, d in self?.handleResize(id: id, handle: h, delta: d, commit: true) }
                )
                let created = DesktopWidgetPanelController(
                    item: item, themeStyle: themeStyle, themeTuning: themeTuning,
                    usesLiquidGlass: usesGlass, showOnAllSpaces: allSpaces, callbacks: callbacks
                )
                controllers[id] = created
                created.applyVisibility(revealState.visibility, isWidgetHidden: item.isHidden)
            }
        }
    }

    private func reflowForDisplayChange() {
        var newFrames: [UUID: CGRect] = [:]
        var newNorms: [UUID: NormalizedWidgetRect] = [:]
        for item in store.items {
            let target = targetScreen(for: item)
            let updatedFrame = item.normalizedFrame.map {
                DesktopLayoutEngine.denormalize($0, in: target.visibleFrame, edgeMargin: edgeMargin)
            } ?? DesktopLayoutEngine.clamp(item.frame, in: target.visibleFrame, edgeMargin: edgeMargin)
            newFrames[item.id] = updatedFrame
            newNorms[item.id] = item.normalizedFrame ?? DesktopLayoutEngine.normalize(updatedFrame, in: target.visibleFrame)
        }
        store.updateFrames(newFrames, normalized: newNorms, immediate: false)
    }

    // MARK: - Drag & Resize

    private func snapshotOriginFrames() {
        dragOriginFrames = Dictionary(
            uniqueKeysWithValues: store.items.map { ($0.id, controllers[$0.id]?.currentFrame ?? $0.frame) }
        )
    }

    private func snapshotResizeOrigin(id: UUID) {
        resizeOriginFrame = controllers[id]?.currentFrame ?? store.item(for: id)?.frame
    }

    private func handleDrag(id: UUID, delta: CGSize, controlHeld: Bool, commit: Bool) {
        if controlHeld {
            guard let item = store.item(for: id) else { return }
            let target = targetScreen(for: item)
            let moved = DesktopLayoutEngine.boundedGroupMove(
                frames: visibleOriginFrames(sameDisplayAs: item), delta: delta,
                visibleFrame: target.visibleFrame, edgeMargin: edgeMargin
            )
            for (movedID, rect) in moved { controllers[movedID]?.applyLiveFrame(rect) }
            if commit {
                let norms = moved.mapValues { DesktopLayoutEngine.normalize($0, in: target.visibleFrame) }
                store.updateFrames(moved, normalized: norms, immediate: true)
                dragOriginFrames.removeAll()
            }
            return
        }

        guard let origin = dragOriginFrames[id], var item = store.item(for: id) else { return }
        let candidate = origin.offsetBy(dx: delta.width, dy: delta.height)
        let target = screenContaining(point: CGPoint(x: candidate.midX, y: candidate.midY))
        let snapped = DesktopLayoutEngine.snapMove(
            candidate: candidate, others: otherFrames(excluding: id, displayUUID: target.uuid),
            visibleFrame: target.visibleFrame, gap: snapGap, edgeMargin: edgeMargin
        )
        controllers[id]?.applyLiveFrame(snapped.frame)
        if commit {
            item.frame = snapped.frame
            if let uuid = target.uuid { item.displayUUID = uuid }
            item.normalizedFrame = DesktopLayoutEngine.normalize(snapped.frame, in: target.visibleFrame)
            store.update(item, immediate: true)
            dragOriginFrames.removeAll()
        }
    }

    private func handleResize(id: UUID, handle: DesktopResizeHandle, delta: CGSize, commit: Bool) {
        guard let origin = resizeOriginFrame, var item = store.item(for: id) else { return }
        let target = targetScreen(for: item)
        let snapped = DesktopLayoutEngine.snapResize(
            origin: origin, handle: handle, delta: delta,
            others: otherFrames(excluding: id, displayUUID: target.uuid),
            visibleFrame: target.visibleFrame, gap: snapGap, edgeMargin: edgeMargin
        )
        controllers[id]?.applyLiveFrame(snapped.frame)
        if commit {
            item.frame = snapped.frame
            item.normalizedFrame = DesktopLayoutEngine.normalize(snapped.frame, in: target.visibleFrame)
            store.update(item, immediate: true)
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
        for item in store.items {
            controllers[item.id]?.applyVisibility(revealState.visibility, isWidgetHidden: item.isHidden)
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
        if doubleClickDesktop != lastDoubleClickEnabled {
            lastDoubleClickEnabled = doubleClickDesktop
            syncBlankDesktopMonitor()
        }
        if showOnAllSpaces != lastShowOnAllSpaces {
            lastShowOnAllSpaces = showOnAllSpaces
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

    private func fallbackPrimaryScreen() -> (uuid: String?, visibleFrame: CGRect) {
        let primary = NSScreen.screens.first
        return (primary.flatMap { DisplayIdentity.uuidString(for: $0) },
                primary?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900))
    }

    private func targetScreen(for item: DesktopWidgetItem) -> (uuid: String?, visibleFrame: CGRect) {
        var byUUID: [String: CGRect] = [:]
        for screen in NSScreen.screens {
            if let uuid = DisplayIdentity.uuidString(for: screen) { byUUID[uuid] = screen.visibleFrame }
        }
        if let resolved = DesktopLayoutEngine.resolveDisplay(for: item, table: displayTopologyStore.table),
           let frame = byUUID[resolved.uuid] {
            return (resolved.uuid, frame)
        }
        return fallbackPrimaryScreen()
    }

    private func screenContaining(point: CGPoint) -> (uuid: String?, visibleFrame: CGRect) {
        for screen in NSScreen.screens where screen.frame.contains(point) {
            return (DisplayIdentity.uuidString(for: screen), screen.visibleFrame)
        }
        return fallbackPrimaryScreen()
    }

    private func otherFrames(excluding id: UUID, displayUUID: String?) -> [CGRect] {
        store.items.compactMap { item in
            guard item.id != id, !item.isHidden else { return nil }
            let targetUUID = targetScreen(for: item).uuid
            guard displayUUID == nil || targetUUID == displayUUID else { return nil }
            return controllers[item.id]?.currentFrame ?? item.frame
        }
    }

    private func visibleOriginFrames(sameDisplayAs anchor: DesktopWidgetItem) -> [UUID: CGRect] {
        let anchorUUID = targetScreen(for: anchor).uuid
        var map: [UUID: CGRect] = [:]
        for item in store.items where !item.isHidden {
            if anchorUUID == nil || targetScreen(for: item).uuid == anchorUUID {
                map[item.id] = dragOriginFrames[item.id] ?? controllers[item.id]?.currentFrame ?? item.frame
            }
        }
        return map
    }
}
