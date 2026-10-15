import AppKit
import Combine
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let store: AppSettingsStore
    private let coordinator: SettingsCoordinator
    /// 「通用」页那颗「重新打开新手引导」按钮。闭包注入：引导窗归 `AppDelegate` 开
    /// （必须直通 `showWelcomeWindow()`，见那边的注释）。
    private let onShowWelcomeGuide: () -> Void
    private var window: NSWindow?
    private var hostingView: NSHostingView<SettingsWindowView>?
    private var sessionSubscriptions: Set<AnyCancellable> = []
    private var closedFrame: NSRect?
    private var hasPresented = false
    /// 所选标签（2026-08-24 分页）。controller 持有唯一一份 = 会话内记忆；
    /// 量高探针必须共享它，否则量的是别的页。有意不跨重启持久化。
    private let tabState = SettingsTabState()

    init(
        store: AppSettingsStore,
        coordinator: SettingsCoordinator,
        onShowWelcomeGuide: @escaping () -> Void
    ) {
        self.store = store
        self.coordinator = coordinator
        self.onShowWelcomeGuide = onShowWelcomeGuide
    }

    func present() {
        let window = window ?? makeWindow()
        if let closedFrame {
            window.setFrame(closedFrame, display: false)
            self.closedFrame = nil
        }
        let host = NSHostingView(
            rootView: SettingsWindowView(
                store: store,
                coordinator: coordinator,
                tabState: tabState,
                onShowWelcomeGuide: onShowWelcomeGuide
            )
        )
        window.contentView = host
        hostingView = host
        // 重开时把标题与工具栏选中态对齐会话记忆（便宜的保险，防将来有闭窗改选中的路径）。
        window.title = tabState.selected.title
        window.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(tabState.selected.rawValue)

        sessionSubscriptions.removeAll()

        resizeToFitKeepingTopEdge()
        repairPlacement(isFirstPresentation: !hasPresented)
        hasPresented = true
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// 外部收尾入口（权限丢失挂起）。`close()` 会触发 `windowWillClose`，清理走那一条路。
    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window, notification.object as? NSWindow === window else { return }
        closedFrame = window.frame
        sessionSubscriptions.removeAll()
        window.contentView = NSView()
        hostingView = nil
        // tabState 有意不重置：重开回到同一标签。
    }

    // MARK: 标签页

    /// 防 NSToolbar 自动校验把图标项置灰（我们的十个标签恒可点）。
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool { true }

    @objc private func selectToolbarTab(_ sender: NSToolbarItem) {
        guard let tab = SettingsTab(rawValue: sender.itemIdentifier.rawValue) else { return }
        select(tab: tab)
    }

    /// Opens on `tab`: switches in place if the window is up, otherwise primes the shared
    /// tab state so `present()` measures the right page.
    func selectBeforePresenting(_ tab: SettingsTab) {
        if window?.isVisible == true {
            select(tab: tab)
        } else {
            tabState.selected = tab
            window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(tab.rawValue)
            window?.title = tab.title
        }
    }

    private func select(tab: SettingsTab) {
        // 点已选中的标签早退，不空放一遍高度动画。
        guard tabState.selected != tab else { return }
        // **先改再量**：量高探针共享这份 tabState，改完它量到的才是新页。
        tabState.selected = tab
        window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(tab.rawValue)
        window?.title = tab.title
        resizeToFitKeepingTopEdge(animated: true)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsWindowView.contentWidth, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        // 标题跟随所选标签（偏好设置惯例）；原静态标题的本地化 key 已随之删除。
        window.title = tabState.selected.title
        window.toolbarStyle = .preference
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        // 不落 NSToolbar Configuration 偏好键——与「不开 frame autosave」同族。
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(tabState.selected.rawValue)
        window.level = .normal
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        return window
    }

    /// `animated` 只有切页路径传 true（顶边左边固定、底边动画到新页高度）。
    /// `present()` 与授权 sink 走默认 false——与一页式时代的行为一致。
    private func resizeToFitKeepingTopEdge(animated: Bool = false) {
        guard let window else { return }
        // The probe must carry the same fixed width as the real window (`SettingsWindowView` puts
        // `.frame(width:)` outside its ScrollView). `fittingSize` proposes no width, so without it
        // every wrapping note measures single-line and the window comes up short by one line per
        // note that wraps — invisible in English, 30–45pt of clipped content in German and French.
        let probe = NSHostingView(
            rootView: SettingsWindowContent(
                store: store,
                coordinator: coordinator,
                tabState: tabState,
                onShowWelcomeGuide: onShowWelcomeGuide
            )
            .frame(width: SettingsWindowView.contentWidth)
        )
        probe.setFrameSize(NSSize(width: SettingsWindowView.contentWidth, height: 0))
        probe.layoutSubtreeIfNeeded()
        let naturalHeight = probe.fittingSize.height
        let visibleHeight = preferredScreen()?.visibleFrame.height ?? 900
        // 下限 160：320 是一页式的地板，分页后最矮的「高级」页自然高不到它，硬撑会留一段空白。
        let contentHeight = max(160, min(naturalHeight, visibleHeight - 80))
        let oldTop = window.frame.maxY
        guard animated else {
            window.setContentSize(NSSize(width: SettingsWindowView.contentWidth, height: contentHeight))
            if hasPresented {
                window.setFrameOrigin(NSPoint(x: window.frame.minX, y: oldTop - window.frame.height))
                repairPlacement(isFirstPresentation: false)
            }
            return
        }
        // 切页动画：必须用**实例**的 frameRect(forContentRect:)——它含标题栏 + 工具栏高度，
        // 类方法不含，会让窗口每切一页长高一个工具栏。修位在动画**前**做：
        // 动画进行中读 window.frame 是插值，动画后再修会按半路的帧去钳。
        let contentRect = NSRect(x: 0, y: 0, width: SettingsWindowView.contentWidth, height: contentHeight)
        var target = window.frameRect(forContentRect: contentRect)
        target.origin.x = window.frame.minX
        target.origin.y = oldTop - target.height
        let titlebarHeight = max(1, window.frame.height - window.contentLayoutRect.height)
        let repaired = AccessoryWindowPresentation.repairedFrame(
            windowFrame: target,
            titlebarHeight: titlebarHeight,
            visibleFrames: NSScreen.screens.map(\.visibleFrame),
            preferredVisibleFrame: preferredScreen()?.visibleFrame,
            isFirstPresentation: false
        )
        window.setFrame(repaired ?? target, display: true, animate: true)
    }

    private func repairPlacement(isFirstPresentation: Bool) {
        guard let window else { return }
        let screens = NSScreen.screens
        let visibleFrames = screens.map(\.visibleFrame)
        let preferred = preferredScreen()?.visibleFrame
        let titlebarHeight = max(1, window.frame.height - window.contentLayoutRect.height)
        guard let repaired = AccessoryWindowPresentation.repairedFrame(
            windowFrame: window.frame,
            titlebarHeight: titlebarHeight,
            visibleFrames: visibleFrames,
            preferredVisibleFrame: preferred,
            isFirstPresentation: isFirstPresentation
        ) else { return }
        window.setFrame(repaired, display: false)
    }

    private func preferredScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? window?.screen ?? NSScreen.main
    }
}

private extension NSImage {
    /// Draw centered in a fixed box instead of returning self, so every toolbar glyph occupies the
    /// same rect regardless of its optical width. A drawing handler keeps it resolution-independent
    /// (a `lockFocus` bitmap would be drawn at 1× and look soft on a Retina display).
    func centered(in size: NSSize) -> NSImage {
        let glyph = self
        let box = NSImage(size: size, flipped: false) { rect in
            glyph.draw(
                at: NSPoint(x: rect.midX - glyph.size.width / 2, y: rect.midY - glyph.size.height / 2),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }
        box.isTemplate = isTemplate
        return box
    }
}

extension SettingsWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    /// 漏掉这一条，标签点了会响应但**永不高亮**——AppKit 只给 selectable 集里的项画选中态。
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let tab = SettingsTab(rawValue: itemIdentifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.title
        item.paletteLabel = tab.title
        // SF Symbols vary in optical size — measured at point size 15: 18–22 pt wide, 17–21 pt tall —
        // so untamed images make the tab strip look ragged. Draw every symbol into one box that
        // contains the widest and tallest of the set (`wrench.and.screwdriver`, 22×21), so the icons
        // line up in one column and their labels share a baseline.
        let iconSize = NSSize(width: 22, height: 22)
        item.image = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: tab.title)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))?
            .centered(in: iconSize)
        item.target = self
        item.action = #selector(selectToolbarTab(_:))
        return item
    }
}
