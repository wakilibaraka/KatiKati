import AppKit
import QuickLookUI
import SwiftUI

struct DesktopWidgetPanelCallbacks {
    var onUpdateItem: (DesktopWidgetItem) -> Void
    var onRemoveBox: () -> Void
    var onSelectTab: (UUID) -> Void
    var onCycleTab: (Int) -> Void
    var onDetachTab: (UUID) -> Void
    var onMergeInto: (UUID) -> Void
    var onAcquireLock: (DesktopInteractionLock) -> Void
    var onReleaseLock: (DesktopInteractionLock) -> Void
    var onDragStarted: () -> Void
    var onDragChanged: (CGSize, Bool) -> Void
    var onDragEnded: (CGSize, Bool) -> Void
    var onResizeStarted: () -> Void
    var onResizeChanged: (DesktopResizeHandle, CGSize) -> Void
    var onResizeEnded: (DesktopResizeHandle, CGSize) -> Void
}

@MainActor
private final class DesktopWidgetHostState: ObservableObject {
    @Published var item: DesktopWidgetItem
    @Published var groupTabs: [DesktopWidgetItem]
    @Published var mergeTargets: [(id: UUID, title: String)]
    @Published var themeStyle: DockThemeStyle
    @Published var themeTuning: ThemeTuning
    @Published var usesLiquidGlass: Bool
    @Published var canvasTheme: DesktopCanvasThemeState
    @Published var canvasBounds: CGRect
    @Published var visibleFrame: CGRect
    @Published var isDropHighlighted = false
    @Published var createNewFolderTrigger = 0
    @Published var isTemporarilyExpanded = false
    @Published var activeLocks: Set<DesktopInteractionLock> = []

    init(
        group: DesktopPanelGroup,
        mergeTargets: [(id: UUID, title: String)],
        themeStyle: DockThemeStyle,
        themeTuning: ThemeTuning,
        usesLiquidGlass: Bool,
        canvasTheme: DesktopCanvasThemeState,
        canvasBounds: CGRect,
        visibleFrame: CGRect = .zero
    ) {
        self.item = group.activeItem
        self.groupTabs = group.tabs
        self.mergeTargets = mergeTargets
        self.themeStyle = themeStyle
        self.themeTuning = themeTuning
        self.usesLiquidGlass = usesLiquidGlass
        self.canvasTheme = canvasTheme
        self.canvasBounds = canvasBounds
        self.visibleFrame = visibleFrame
    }
}

private struct DesktopWidgetRootView: View {
    @ObservedObject var hostState: DesktopWidgetHostState
    let folderModelProvider: (DesktopWidgetItem) -> DesktopFolderBoxModel
    let callbacks: DesktopWidgetPanelCallbacks
    let onQuickLook: ([URL]) -> Void
    let onRevealInFinder: () -> Void
    let onExpandCapsule: () -> Void
    let onCollapseCapsule: () -> Void
    let onHoverChanged: (Bool) -> Void

    private var activeModel: DesktopFolderBoxModel {
        folderModelProvider(hostState.item)
    }

    private var itemCount: Int? {
        guard hostState.item.kind == .folder else { return nil }
        if case .loaded(let entries) = activeModel.loadState { return entries.count }
        return nil
    }

    var body: some View {
        if hostState.item.capsuleMode != .expanded && !hostState.isTemporarilyExpanded {
            DesktopCapsuleView(
                item: hostState.item,
                canvasTheme: hostState.canvasTheme,
                itemCount: itemCount,
                usesLiquidGlass: hostState.usesLiquidGlass,
                onUpdateItem: callbacks.onUpdateItem,
                onExpandTriggered: onExpandCapsule,
                onRemoveBox: callbacks.onRemoveBox,
                onAcquireLock: callbacks.onAcquireLock,
                onReleaseLock: callbacks.onReleaseLock,
                onDragStarted: callbacks.onDragStarted,
                onDragChanged: callbacks.onDragChanged,
                onDragEnded: callbacks.onDragEnded
            )
            .environment(\.dockThemeStyle, hostState.themeStyle)
            .environment(\.themeTuning, hostState.themeTuning)
        } else {
            let model = activeModel
            DesktopWidgetChromeView(
                item: hostState.item,
                canvasTheme: hostState.canvasTheme,
                canvasBounds: hostState.canvasBounds,
                groupTabs: hostState.groupTabs,
                mergeTargets: hostState.mergeTargets,
                itemCount: itemCount,
                usesLiquidGlass: hostState.usesLiquidGlass,
                isDropHighlighted: hostState.isDropHighlighted,
                onUpdateItem: callbacks.onUpdateItem,
                onSelectTab: callbacks.onSelectTab,
                onCycleTab: callbacks.onCycleTab,
                onDetachTab: callbacks.onDetachTab,
                onMergeInto: callbacks.onMergeInto,
                onNewFolder: { hostState.createNewFolderTrigger += 1 },
                onRevealInFinder: onRevealInFinder,
                onRemoveBox: callbacks.onRemoveBox,
                onAcquireLock: callbacks.onAcquireLock,
                onReleaseLock: callbacks.onReleaseLock,
                onDragStarted: callbacks.onDragStarted,
                onDragChanged: callbacks.onDragChanged,
                onDragEnded: callbacks.onDragEnded,
                onResizeStarted: callbacks.onResizeStarted,
                onResizeChanged: callbacks.onResizeChanged,
                onResizeEnded: callbacks.onResizeEnded,
                onHoverChanged: onHoverChanged,
                onCollapseCapsule: onCollapseCapsule
            ) {
                Group {
                switch hostState.item.kind {
                case .todo:
                    DesktopTodoBoxView(
                        tasks: ProductivityServices.shared.tasks,
                        onAcquireLock: callbacks.onAcquireLock,
                        onReleaseLock: callbacks.onReleaseLock
                    )
                case .quickCapture:
                    DesktopQuickCaptureBoxView(
                        store: DesktopQuickCaptureStore.shared,
                        onAcquireLock: callbacks.onAcquireLock,
                        onReleaseLock: callbacks.onReleaseLock
                    )
                case .glance:
                    DesktopGlanceBoxView()
                case .weather:
                    if let weather = AppDelegate.shared?.weatherService {
                        DesktopWeatherBoxView(service: weather)
                    }
                case .music:
                    DesktopVinylBoxView(service: DesktopWidgetServices.nowPlaying)
                case .search:
                    DesktopSearchPillView()
                default:
                    DesktopFolderBoxView(
                        item: hostState.item,
                        model: model,
                        onUpdateItem: callbacks.onUpdateItem,
                        onQuickLook: onQuickLook,
                        onAcquireLock: callbacks.onAcquireLock,
                        onReleaseLock: callbacks.onReleaseLock,
                        onDropTargetedChanged: { hostState.isDropHighlighted = $0 },
                        createNewFolderTrigger: $hostState.createNewFolderTrigger
                    )
                }
            }
            .id(hostState.item.id)
        }
        .environment(\.dockThemeStyle, hostState.themeStyle)
        .environment(\.themeTuning, hostState.themeTuning)
        }
    }
}

private final class DesktopWidgetPanel: NonConstrainingPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosts one desktop-layer `NSPanel` for a `DesktopPanelGroup` (supporting tabs, Quick Reveal, and QuickLook).
@MainActor
final class DesktopWidgetPanelController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let desktopLayerLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

    let panelKey: UUID
    private let panel: DesktopWidgetPanel
    private let hostState: DesktopWidgetHostState
    private var tabModels: [UUID: DesktopFolderBoxModel] = [:]
    private let callbacks: DesktopWidgetPanelCallbacks

    private var activeLocks: Set<DesktopInteractionLock> = []
    private var collapseTask: Task<Void, Never>?
    private var quickLookURLs: [URL] = []
    private var keyMonitor: Any?
    private var wrappedCallbacks: DesktopWidgetPanelCallbacks?
    /// Released while hidden under Resource Saver, then rebuilt on the next show.
    private var hostingView: NSView?

    init(
        group: DesktopPanelGroup,
        mergeTargets: [(id: UUID, title: String)],
        themeStyle: DockThemeStyle,
        themeTuning: ThemeTuning,
        usesLiquidGlass: Bool,
        canvasTheme: DesktopCanvasThemeState,
        canvasBounds: CGRect,
        visibleFrame: CGRect = .zero,
        showOnAllSpaces: Bool,
        callbacks: DesktopWidgetPanelCallbacks
    ) {
        self.panelKey = group.panelKey
        self.callbacks = callbacks
        let state = DesktopWidgetHostState(
            group: group,
            mergeTargets: mergeTargets,
            themeStyle: themeStyle,
            themeTuning: themeTuning,
            usesLiquidGlass: usesLiquidGlass,
            canvasTheme: canvasTheme,
            canvasBounds: canvasBounds,
            visibleFrame: visibleFrame
        )
        self.hostState = state

        let visible = (visibleFrame.isEmpty || visibleFrame.height < 100) ? group.activeItem.frame : visibleFrame
        let initialFrame: CGRect
        if group.activeItem.capsuleMode == .expanded {
            initialFrame = group.activeItem.frame
        } else if case .edgeDocked(let edge) = group.activeItem.capsuleMode {
            let ratio = group.activeItem.edgePositionRatio(for: edge, in: visible)
            initialFrame = DesktopCapsuleLayout.dockedFrame(edge: edge, positionRatio: ratio, visibleFrame: visible)
        } else {
            initialFrame = DesktopCapsuleLayout.capsuleFrame(for: group.activeItem.frame, visibleFrame: visible)
        }

        let outerFrame = Self.outerPanelFrame(for: initialFrame)
        let panel = DesktopWidgetPanel(
            contentRect: outerFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.becomesKeyOnlyIfNeeded = true
        panel.isFloatingPanel = false
        panel.level = Self.desktopLayerLevel
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = Self.collectionBehavior(showOnAllSpaces: showOnAllSpaces)
        self.panel = panel
        super.init()

        syncModels(for: group.tabs)
        let wrappedCallbacks = DesktopWidgetPanelCallbacks(
            onUpdateItem: callbacks.onUpdateItem,
            onRemoveBox: callbacks.onRemoveBox,
            onSelectTab: callbacks.onSelectTab,
            onCycleTab: callbacks.onCycleTab,
            onDetachTab: callbacks.onDetachTab,
            onMergeInto: callbacks.onMergeInto,
            onAcquireLock: { [weak self] lock in
                guard let self else { return }
                self.activeLocks.insert(lock)
                self.hostState.activeLocks = self.activeLocks
                self.collapseTask?.cancel()
                self.callbacks.onAcquireLock(lock)
            },
            onReleaseLock: { [weak self] lock in
                guard let self else { return }
                self.activeLocks.remove(lock)
                self.hostState.activeLocks = self.activeLocks
                self.callbacks.onReleaseLock(lock)
                if self.hostState.item.capsuleMode != .expanded, self.hostState.isTemporarilyExpanded {
                    self.scheduleCollapse()
                }
            },
            onDragStarted: callbacks.onDragStarted,
            onDragChanged: callbacks.onDragChanged,
            onDragEnded: callbacks.onDragEnded,
            onResizeStarted: callbacks.onResizeStarted,
            onResizeChanged: callbacks.onResizeChanged,
            onResizeEnded: callbacks.onResizeEnded
        )
        self.wrappedCallbacks = wrappedCallbacks
        installSurface(with: wrappedCallbacks)
        installKeyMonitor()
    }

    private func installSurface(with wrappedCallbacks: DesktopWidgetPanelCallbacks) {
        guard hostingView == nil else { return }
        self.wrappedCallbacks = wrappedCallbacks
        let root = DesktopWidgetRootView(
            hostState: hostState,
            folderModelProvider: { [weak self] item in
                self?.model(for: item) ?? DesktopFolderBoxModel(
                    backingPath: item.backingPath ?? NSHomeDirectory(),
                    sortMode: item.sortMode,
                    manualOrder: item.manualOrder
                )
            },
            callbacks: wrappedCallbacks,
            onQuickLook: { [weak self] urls in self?.toggleQuickLook(for: urls) },
            onRevealInFinder: { [weak self] in
                guard let path = self?.hostState.item.backingPath else { return }
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            },
            onExpandCapsule: { [weak self] in self?.expandCapsule() },
            onCollapseCapsule: { [weak self] in self?.collapseCapsule() },
            onHoverChanged: { [weak self] isHovered in
                if isHovered {
                    self?.collapseTask?.cancel()
                    self?.collapseTask = nil
                } else {
                    self?.scheduleCollapse()
                }
            }
        )
        let host = FirstMouseHostingView(rootView: root)
        hostingView = host
        panel.contentView = host
    }

    private func ensureSurface() {
        if hostingView == nil, let wrappedCallbacks {
            installSurface(with: wrappedCallbacks)
        }
    }

    private func releaseSurfaceIfAllowed() {
        guard DesktopPerformanceStore.shared.settings.releasesHiddenSurfaces else { return }
        hostingView = nil
        panel.contentView = nil
    }

    var windowNumber: Int { panel.windowNumber }
    var currentFrame: CGRect {
        effectiveWidgetFrame(for: hostState.item, isExpanded: hostState.isTemporarilyExpanded)
    }
    var activeWidgetID: UUID { hostState.item.id }

    func update(
        group: DesktopPanelGroup,
        mergeTargets: [(id: UUID, title: String)],
        visibility: DesktopCanvasVisibility,
        themeStyle: DockThemeStyle,
        themeTuning: ThemeTuning,
        usesLiquidGlass: Bool,
        canvasTheme: DesktopCanvasThemeState,
        canvasBounds: CGRect,
        visibleFrame: CGRect = .zero,
        showOnAllSpaces: Bool
    ) {
        syncModels(for: group.tabs)
        hostState.item = group.activeItem
        hostState.groupTabs = group.tabs
        hostState.mergeTargets = mergeTargets
        hostState.themeStyle = themeStyle
        hostState.themeTuning = themeTuning
        hostState.usesLiquidGlass = usesLiquidGlass
        hostState.canvasTheme = canvasTheme
        hostState.canvasBounds = canvasBounds
        if !visibleFrame.isEmpty { hostState.visibleFrame = visibleFrame }

        let targetFrame = effectiveWidgetFrame(for: group.activeItem, isExpanded: hostState.isTemporarilyExpanded)
        let targetOuter = Self.outerPanelFrame(for: targetFrame)
        if panel.frame != targetOuter {
            panel.setFrame(targetOuter, display: true)
        }
        let targetBehavior = Self.collectionBehavior(showOnAllSpaces: showOnAllSpaces)
        if panel.collectionBehavior != targetBehavior {
            panel.collectionBehavior = targetBehavior
        }

        applyVisibility(visibility, isWidgetHidden: group.activeItem.isHidden)
    }

    func applyLiveFrame(_ frame: CGRect, canvasBounds: CGRect? = nil) {
        var next = hostState.item
        next.frame = frame
        hostState.item = next
        if let canvasBounds { hostState.canvasBounds = canvasBounds }
        let outer = Self.outerPanelFrame(for: frame)
        if panel.frame != outer {
            panel.setFrame(outer, display: true)
        }
    }

    func applyVisibility(_ visibility: DesktopCanvasVisibility, isWidgetHidden: Bool) {
        if isWidgetHidden || visibility == .hiddenAll {
            if panel.isVisible { panel.orderOut(nil) }
            releaseSurfaceIfAllowed()
            return
        }
        ensureSurface()
        switch visibility {
        case .desktopLayer:
            panel.isFloatingPanel = false
            if panel.level != Self.desktopLayerLevel { panel.level = Self.desktopLayerLevel }
            if !panel.isVisible { panel.orderFront(nil) }
        case .quickRevealed:
            if panel.level != .floating { panel.level = .floating }
            if !panel.isVisible { panel.orderFront(nil) }
            else { panel.orderFrontRegardless() }
        case .hiddenAll:
            if panel.isVisible { panel.orderOut(nil) }
            releaseSurfaceIfAllowed()
        }
    }

    func contains(screenPoint: CGPoint) -> Bool {
        let frame = effectiveWidgetFrame(for: hostState.item, isExpanded: hostState.isTemporarilyExpanded)
        return panel.isVisible && frame.contains(screenPoint)
    }

    func tearDown() {
        collapseTask?.cancel()
        collapseTask = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        for model in tabModels.values { model.stop() }
        tabModels.removeAll()
        if let ql = QLPreviewPanel.shared(), ql.isVisible, ql.dataSource === self {
            ql.orderOut(nil)
        }
        panel.orderOut(nil)
        hostingView = nil
        panel.contentView = nil
        panel.close()
    }

    // MARK: - Capsule Frame & Hover Mechanics

    private func effectiveWidgetFrame(for item: DesktopWidgetItem, isExpanded: Bool) -> CGRect {
        let visible = (hostState.visibleFrame.isEmpty || hostState.visibleFrame.height < 100)
            ? (panel.screen?.visibleFrame ?? item.frame)
            : hostState.visibleFrame
        if item.capsuleMode == .expanded || isExpanded {
            if case .edgeDocked(let edge) = item.capsuleMode {
                let ratio = item.edgePositionRatio(for: edge, in: visible)
                let cap = DesktopCapsuleLayout.dockedFrame(edge: edge, positionRatio: ratio, visibleFrame: visible)
                return DesktopCapsuleLayout.expandedFrame(from: cap, originalSize: item.frame.size, dockedEdge: edge, visibleFrame: visible)
            } else if item.capsuleMode == .capsule {
                let cap = DesktopCapsuleLayout.capsuleFrame(for: item.frame, visibleFrame: visible)
                return DesktopCapsuleLayout.expandedFrame(from: cap, originalSize: item.frame.size, dockedEdge: nil, visibleFrame: visible)
            } else {
                return item.frame
            }
        } else {
            switch item.capsuleMode {
            case .edgeDocked(let edge):
                let ratio = item.edgePositionRatio(for: edge, in: visible)
                return DesktopCapsuleLayout.dockedFrame(edge: edge, positionRatio: ratio, visibleFrame: visible)
            case .capsule:
                return DesktopCapsuleLayout.capsuleFrame(for: item.frame, visibleFrame: visible)
            case .expanded:
                return item.frame
            }
        }
    }

    private func animateToOuterFrame(_ outer: CGRect) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            panel.setFrame(outer, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(outer, display: true)
            }
        }
    }

    private func expandCapsule() {
        guard hostState.item.capsuleMode != .expanded, !hostState.isTemporarilyExpanded else { return }
        collapseTask?.cancel()
        collapseTask = nil
        hostState.isTemporarilyExpanded = true
        let targetFrame = effectiveWidgetFrame(for: hostState.item, isExpanded: true)
        animateToOuterFrame(Self.outerPanelFrame(for: targetFrame))
    }

    private func scheduleCollapse() {
        guard hostState.item.capsuleMode != .expanded, hostState.isTemporarilyExpanded else { return }
        collapseTask?.cancel()
        collapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled else { return }
            let mouseLoc = NSEvent.mouseLocation
            let isHovered = self.panel.frame.contains(mouseLoc)
            if !DesktopCapsuleHoverPolicy.shouldRemainExpanded(isHovered: isHovered, activeLocks: self.activeLocks) {
                self.hostState.isTemporarilyExpanded = false
                let targetFrame = self.effectiveWidgetFrame(for: self.hostState.item, isExpanded: false)
                self.animateToOuterFrame(Self.outerPanelFrame(for: targetFrame))
            }
        }
    }

    private func collapseCapsule() {
        guard hostState.item.capsuleMode != .expanded, hostState.isTemporarilyExpanded else { return }
        collapseTask?.cancel()
        collapseTask = nil
        hostState.isTemporarilyExpanded = false
        let targetFrame = effectiveWidgetFrame(for: hostState.item, isExpanded: false)
        animateToOuterFrame(Self.outerPanelFrame(for: targetFrame))
    }

    // MARK: - Models & Key Handling

    private func syncModels(for tabs: [DesktopWidgetItem]) {
        let liveIDs = Set(tabs.map(\.id))
        for (id, model) in tabModels where !liveIDs.contains(id) {
            model.stop()
            tabModels.removeValue(forKey: id)
        }
        for tab in tabs {
            _ = model(for: tab)
        }
    }

    private func model(for item: DesktopWidgetItem) -> DesktopFolderBoxModel {
        let path = item.kind == .folder ? (item.backingPath ?? NSHomeDirectory()) : "/var/empty"
        if let existing = tabModels[item.id] {
            existing.updateConfig(backingPath: path, sortMode: item.sortMode, manualOrder: item.manualOrder)
            return existing
        }
        let tabID = item.id
        let model = DesktopFolderBoxModel(
            backingPath: path,
            sortMode: item.sortMode,
            manualOrder: item.manualOrder,
            onManualOrderUpdated: { [weak self] updatedOrder in
                guard let self else { return }
                guard var target = self.hostState.groupTabs.first(where: { $0.id == tabID }) else { return }
                target.manualOrder = updatedOrder
                self.callbacks.onUpdateItem(target)
            }
        )
        tabModels[tabID] = model
        model.start()
        return model
    }

    private func toggleQuickLook(for urls: [URL]) {
        guard !urls.isEmpty, let ql = QLPreviewPanel.shared() else { return }
        if ql.isVisible && ql.dataSource === self && quickLookURLs == urls {
            ql.orderOut(nil)
            return
        }
        quickLookURLs = urls
        ql.dataSource = self
        ql.delegate = self
        if ql.isVisible { ql.reloadData() } else { ql.makeKeyAndOrderFront(nil) }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, NSApp.keyWindow === self.panel else { return event }
            if self.panel.firstResponder is NSTextView { return event }
            if event.keyCode == 48, event.modifierFlags.contains(.control), self.hostState.groupTabs.count > 1 {
                self.callbacks.onCycleTab(event.modifierFlags.contains(.shift) ? -1 : 1)
                return nil
            }
            if event.keyCode == 49, let model = self.tabModels[self.hostState.item.id] {
                let urls = model.selectedPaths.map { URL(fileURLWithPath: $0) }
                guard !urls.isEmpty else { return event }
                self.toggleQuickLook(for: urls)
                return nil
            }
            return event
        }
    }

    // MARK: - QLPreviewPanelDataSource & Delegate

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { quickLookURLs.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated {
            guard index >= 0, index < quickLookURLs.count else { return nil }
            return quickLookURLs[index] as NSURL
        }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool { false }

    private static func outerPanelFrame(for widgetFrame: CGRect) -> CGRect {
        widgetFrame.insetBy(dx: -PanelLayoutMetrics.shadowPadding, dy: -PanelLayoutMetrics.shadowPadding)
    }

    private static func collectionBehavior(showOnAllSpaces: Bool) -> NSWindow.CollectionBehavior {
        showOnAllSpaces
            ? [.canJoinAllSpaces, .stationary, .ignoresCycle]
            : [.stationary, .ignoresCycle]
    }
}
