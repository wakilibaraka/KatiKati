import AppKit
import QuickLookUI
import SwiftUI

struct DesktopWidgetPanelCallbacks {
    var onUpdateItem: (DesktopWidgetItem) -> Void
    var onRemoveBox: () -> Void
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
    @Published var themeStyle: DockThemeStyle
    @Published var themeTuning: ThemeTuning
    @Published var usesLiquidGlass: Bool
    @Published var isDropHighlighted = false
    @Published var createNewFolderTrigger = 0

    init(
        item: DesktopWidgetItem,
        themeStyle: DockThemeStyle,
        themeTuning: ThemeTuning,
        usesLiquidGlass: Bool
    ) {
        self.item = item
        self.themeStyle = themeStyle
        self.themeTuning = themeTuning
        self.usesLiquidGlass = usesLiquidGlass
    }
}

private struct DesktopWidgetRootView: View {
    @ObservedObject var hostState: DesktopWidgetHostState
    @ObservedObject var folderModel: DesktopFolderBoxModel
    let callbacks: DesktopWidgetPanelCallbacks
    let onQuickLook: ([URL]) -> Void
    let onRevealInFinder: () -> Void

    private var itemCount: Int? {
        if case .loaded(let entries) = folderModel.loadState { return entries.count }
        return nil
    }

    var body: some View {
        DesktopWidgetChromeView(
            item: hostState.item,
            itemCount: itemCount,
            usesLiquidGlass: hostState.usesLiquidGlass,
            isDropHighlighted: hostState.isDropHighlighted,
            onUpdateItem: callbacks.onUpdateItem,
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
            onResizeEnded: callbacks.onResizeEnded
        ) {
            DesktopFolderBoxView(
                item: hostState.item,
                model: folderModel,
                onUpdateItem: callbacks.onUpdateItem,
                onQuickLook: onQuickLook,
                onAcquireLock: callbacks.onAcquireLock,
                onReleaseLock: callbacks.onReleaseLock,
                onDropTargetedChanged: { hostState.isDropHighlighted = $0 },
                createNewFolderTrigger: $hostState.createNewFolderTrigger
            )
        }
        .environment(\.dockThemeStyle, hostState.themeStyle)
        .environment(\.themeTuning, hostState.themeTuning)
    }
}

private final class DesktopWidgetPanel: NonConstrainingPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosts one desktop-layer `NSPanel` with `desktopIconWindow + 1` resting level, Quick Reveal, and QuickLook.
@MainActor
final class DesktopWidgetPanelController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let desktopLayerLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

    let widgetID: UUID
    private let panel: DesktopWidgetPanel
    private let hostState: DesktopWidgetHostState
    private let folderModel: DesktopFolderBoxModel
    private let callbacks: DesktopWidgetPanelCallbacks

    private var quickLookURLs: [URL] = []
    private var spaceKeyMonitor: Any?

    init(
        item: DesktopWidgetItem,
        themeStyle: DockThemeStyle,
        themeTuning: ThemeTuning,
        usesLiquidGlass: Bool,
        showOnAllSpaces: Bool,
        callbacks: DesktopWidgetPanelCallbacks
    ) {
        self.widgetID = item.id
        self.callbacks = callbacks
        let state = DesktopWidgetHostState(
            item: item,
            themeStyle: themeStyle,
            themeTuning: themeTuning,
            usesLiquidGlass: usesLiquidGlass
        )
        self.hostState = state
        let model = DesktopFolderBoxModel(
            backingPath: item.backingPath ?? NSHomeDirectory(),
            sortMode: item.sortMode,
            manualOrder: item.manualOrder,
            onManualOrderUpdated: { updatedOrder in
                var next = state.item
                next.manualOrder = updatedOrder
                callbacks.onUpdateItem(next)
            }
        )
        self.folderModel = model

        let outerFrame = Self.outerPanelFrame(for: item.frame)
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

        let root = DesktopWidgetRootView(
            hostState: state,
            folderModel: model,
            callbacks: callbacks,
            onQuickLook: { [weak self] urls in self?.toggleQuickLook(for: urls) },
            onRevealInFinder: { [weak self] in
                guard let path = self?.hostState.item.backingPath else { return }
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        )
        let hosting = FirstMouseHostingView(rootView: root)
        panel.contentView = hosting
        installSpaceKeyMonitor()
        model.start()
    }

    var windowNumber: Int { panel.windowNumber }
    var currentFrame: CGRect { hostState.item.frame }

    func update(
        item: DesktopWidgetItem,
        visibility: DesktopCanvasVisibility,
        themeStyle: DockThemeStyle,
        themeTuning: ThemeTuning,
        usesLiquidGlass: Bool,
        showOnAllSpaces: Bool
    ) {
        hostState.item = item
        hostState.themeStyle = themeStyle
        hostState.themeTuning = themeTuning
        hostState.usesLiquidGlass = usesLiquidGlass
        folderModel.updateConfig(
            backingPath: item.backingPath ?? NSHomeDirectory(),
            sortMode: item.sortMode,
            manualOrder: item.manualOrder
        )

        let targetOuter = Self.outerPanelFrame(for: item.frame)
        if panel.frame != targetOuter {
            panel.setFrame(targetOuter, display: true)
        }
        let targetBehavior = Self.collectionBehavior(showOnAllSpaces: showOnAllSpaces)
        if panel.collectionBehavior != targetBehavior {
            panel.collectionBehavior = targetBehavior
        }

        applyVisibility(visibility, isWidgetHidden: item.isHidden)
    }

    func applyLiveFrame(_ frame: CGRect) {
        var next = hostState.item
        next.frame = frame
        hostState.item = next
        let outer = Self.outerPanelFrame(for: frame)
        if panel.frame != outer {
            panel.setFrame(outer, display: true)
        }
    }

    func applyVisibility(_ visibility: DesktopCanvasVisibility, isWidgetHidden: Bool) {
        if isWidgetHidden || visibility == .hiddenAll {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
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
        }
    }

    func contains(screenPoint: CGPoint) -> Bool {
        panel.isVisible && hostState.item.frame.contains(screenPoint)
    }

    func tearDown() {
        if let spaceKeyMonitor { NSEvent.removeMonitor(spaceKeyMonitor) }
        spaceKeyMonitor = nil
        folderModel.stop()
        if let ql = QLPreviewPanel.shared(), ql.isVisible, ql.dataSource === self {
            ql.orderOut(nil)
        }
        panel.orderOut(nil)
        panel.close()
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

    private func installSpaceKeyMonitor() {
        spaceKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 49, NSApp.keyWindow === self.panel else { return event }
            if self.panel.firstResponder is NSTextView { return event }
            let urls = self.folderModel.selectedPaths.map { URL(fileURLWithPath: $0) }
            guard !urls.isEmpty else { return event }
            self.toggleQuickLook(for: urls)
            return nil
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
