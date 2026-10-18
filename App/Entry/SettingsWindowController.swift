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
    private var hasPresented = false
    /// The selected section; persisted by `SettingsTabState`, so a relaunch reopens on it.
    private let tabState = SettingsTabState()
    private static let frameAutosaveName = "KatiKatiSettings"

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
        let host = NSHostingView(
            rootView: SettingsWindowView(
                store: store,
                coordinator: coordinator,
                tabState: tabState,
                onShowWelcomeGuide: onShowWelcomeGuide
            )
        )
        // The sidebar draws under the titlebar; the hosting view's safe area keeps content clear of it.
        window.contentView = host
        hostingView = host
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
        window.contentView = NSView()
        hostingView = nil
    }

    /// Opens on `tab`: switches in place if the window is up, otherwise primes the shared state.
    func selectBeforePresenting(_ tab: SettingsTab) {
        tabState.selected = tab
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0, y: 0,
                width: SettingsMetrics.idealWindowWidth, height: SettingsMetrics.idealWindowHeight
            ),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentMinSize = NSSize(width: SettingsMetrics.minWindowWidth, height: SettingsMetrics.minWindowHeight)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // Free resize with a remembered frame, like System Settings. The first launch uses the
        // ideal size; `repairPlacement` pulls a frame saved on a vanished display back on-screen.
        if !window.setFrameUsingName(Self.frameAutosaveName) { window.center() }
        window.setFrameAutosaveName(Self.frameAutosaveName)
        window.level = .normal
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        return window
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
