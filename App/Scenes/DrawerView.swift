import AppKit
import os
import SwiftUI

/// The capsule's panel: **Background Apps only** (owner 2026-10-27). Stashed apps, files and folders
/// moved to the drawer pop, its own dock icon in the strip (`PopChip` / `PopGridPopupView`), so the two
/// never share a surface again.
///
/// Cells are running apps with no window to switch to (`BackgroundAppsStore`). They are not placements:
/// nothing here drags, reorders or converts a strip card, and a strip card dragged over this panel
/// stays a strip drag (the stash target is the pop chip — `PanelCoordinator.dragDropZones`).
struct DrawerView: View {
    /// Rows and columns the grid may take above the capsule on this screen; past them it scrolls
    /// inside the plate. The coordinator swaps the root view when they change.
    let limits: StackGridLayout.Limits
    /// The plate's arrow, kept on the capsule by the coordinator.
    let arrow: StackPopupArrowModel
    /// The plate's size changed: the coordinator re-lays out the drawer window. No default —
    /// without it the window stops following its content.
    let onPanelSizeChange: (CGSize) -> Void
    /// 底板走不走原生 Liquid Glass。**显式传入、无默认值**（同 `scale` / `hoverStyle`）——
    /// 每个面板都是独立的 hosting 根视图，漏传就会出现「这个面板是玻璃、旁边那个还是
    /// 毛玻璃」这种一眼可见的不一致。
    let usesLiquidGlass: Bool
    /// Whether this panel is open now. Kept for the coordinator's root-view contract; with no drag
    /// handling left here nothing reads it yet.
    let isDrawerOpen: () -> Bool
    /// 点击 app 图标执行「唤出」或「启动」后回调。由 PanelCoordinator 注入，用于关闭面板。
    var onPrimaryAction: () -> Void = {}

    @EnvironmentObject var runtime: AppRuntime
    @EnvironmentObject var drawerStore: DrawerStore
    @EnvironmentObject var messagingStore: MessagingAppStore
    @EnvironmentObject var keptAppStore: KeptAppStore
    @EnvironmentObject var runningApplicationStore: RunningApplicationStore
    @EnvironmentObject var appMembershipController: AppMembershipController

    @ObservedObject private var backgroundStore = BackgroundAppsStore.shared
    @AppStorage(BackgroundAppsStore.showSystemHelpersKey) private var showSystemHelpers = false
    @ObservedObject private var memoryOverlay = MemoryOverlayController.shared

    /// Phase 20a: running apps with no window to switch to. Auto-populated; apps in the drawer pop
    /// stay out (they have their own home).
    private var backgroundMembers: [String] {
        backgroundStore.backgroundIDs(
            windowBacked: windowBackedIDs,
            kept: Set(keptAppStore.bundleIDs),
            messaging: Set(messagingStore.bundleIDs),
            stashed: Set(drawerStore.bundleIDs),
            showSystemHelpers: showSystemHelpers)
    }

    /// 有真窗口的 app。
    private var windowBackedIDs: Set<String> {
        Set(StripItem.items(from: runtime.snapshot).filter { !$0.isAppLevelFallback }.compactMap(\.bundleIdentifier))
    }

    /// 只有访达格子读得到真值（`performDefaultTap` 的访达分支才用）。非访达恒 `false` 是有意的。
    private func finderHasRealWindow(_ id: String) -> Bool {
        guard FinderTaskbarPolicy.isFinder(id) else { return false }
        return windowBackedIDs.contains(id)
    }

    /// 隐藏判定：同 bundle 所有进程都 hidden 才算 hidden。
    private func isHiddenInSnapshot(_ id: String) -> Bool { runningApplicationStore.isHidden(id) }

    // MARK: - Body

    var body: some View {
        let ids = backgroundMembers
        let shape = DrawerGridShape.resolve(settledCount: ids.count, actualCount: ids.count, limits: limits)
        return StackPopupChrome(title: String(localized: "Background Apps"),
                                note: shape.showsHint ? String(localized: "No apps are running in the background") : nil,
                                layout: shape.layout,
                                plate: .drawer,
                                usesLiquidGlass: usesLiquidGlass,
                                arrow: arrow,
                                onPanelSizeChange: onPanelSizeChange,
                                gridAnimation: .easeInOut(duration: DrawerAnimation.duration),
                                gridAnimationKey: ids) {
            ForEach(ids, id: \.self) { backgroundChip($0).memoryPill($0, overlay: memoryOverlay) }
        }
        .onHover { MemoryOverlayController.shared.pointer(inside: $0) }
        // **面板打开没有入场动画**（owner 2026-09-04，理由见 `Docs/27`）。
    }

    // MARK: - Cells

    private func membershipItems(for id: String) -> [LauncherMembershipItem] {
        LauncherMembershipItem.items(
            surface: .drawer,
            bundleID: id,
            isKept: keptAppStore.contains(id),
            isMessaging: messagingStore.contains(id),
            controller: appMembershipController
        )
    }

    /// Background-app cell: the drawer's stack-cell chip, no drag (these are not placements), plus
    /// Open / Hide / Quit / Force Quit / Ignore in its menu.
    private func backgroundChip(_ id: String) -> some View {
        LauncherChip(bundleID: id,
                     isRunning: true,
                     isHidden: isHiddenInSnapshot(id),
                     finderHasRealWindow: finderHasRealWindow(id),
                     isLaunching: runtime.launchingBundleIDs.contains(id),
                     // 76pt icon = 1.9 × the bar's 40pt slot (`StackCellMetrics.drawer.iconSize`).
                     scale: 1.9,
                     layout: .stackCell,
                     railTile: false,
                     // 面板固定安静档（owner 2026-08-17：悬停微微放大，不冒名字）。
                     hoverStyle: .quiet,
                     hoverInput: .selfTracked,
                     windowEntriesProvider: {
                         WindowListMenuPlan.entries(
                             snapshot: runtime.snapshot,
                             bundleID: id,
                             fallbackTitle: AppDisplayNameResolver.displayName(for: id)
                         )
                     },
                     onActivateWindow: { runtime.activate(windowID: $0) },
                     membershipItems: membershipItems(for: id) + [
                        LauncherMembershipItem(label: String(localized: "Open")) {
                            NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.activate(options: [.activateAllWindows])
                        },
                        LauncherMembershipItem(label: String(localized: "Hide")) {
                            NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.hide() }
                        },
                        LauncherMembershipItem(label: String(localized: "Quit")) {
                            NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.terminate() }
                        },
                        LauncherMembershipItem(label: String(localized: "Force Quit")) {
                            NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.forceTerminate() }
                        },
                        LauncherMembershipItem(label: String(localized: "Ignore")) { backgroundStore.ignore(id) }
                     ],
                     slotHidden: false,
                     hoverSuppressed: false,
                     onLaunch: { runtime.beginLaunch(id) },
                     onPrimaryAction: onPrimaryAction)
    }
}

/// 面板宿主的根视图：`DrawerView` + 它的环境对象。
///
/// 存在的唯一理由是给 `PanelCoordinator` 一个**可命名**的宿主类型 `NSHostingView<DrawerRootView>`：
/// 宿主只建一次、之后每次打开只换 `rootView`（2026-09-04，抽屉弹开掉帧的修法），而
/// `DrawerView(...).environmentObject(...)` 链出来的是写不出名字的 `ModifiedContent<…>`。
struct DrawerRootView: View {
    let limits: StackGridLayout.Limits
    let arrow: StackPopupArrowModel
    let onPanelSizeChange: (CGSize) -> Void
    let usesLiquidGlass: Bool
    let isDrawerOpen: () -> Bool
    let onPrimaryAction: () -> Void
    let runtime: AppRuntime
    let drawerStore: DrawerStore
    let messagingStore: MessagingAppStore
    let drawerOrderStore: DrawerOrderStore
    let dragController: DragController
    let keptAppStore: KeptAppStore
    let runningApplicationStore: RunningApplicationStore
    let appMembershipController: AppMembershipController
    /// 4c: the panel's pinned theme style. Observed (not a plain value) so a theme change
    /// re-runs this body and re-injects it into the whole subtree.
    @ObservedObject var settingsStore: AppSettingsStore

    var body: some View {
        DrawerView(limits: limits,
                   arrow: arrow,
                   onPanelSizeChange: onPanelSizeChange,
                   usesLiquidGlass: usesLiquidGlass,
                   isDrawerOpen: isDrawerOpen,
                   onPrimaryAction: onPrimaryAction)
            .environmentObject(runtime).environmentObject(drawerStore).environmentObject(messagingStore)
            .environmentObject(drawerOrderStore).environmentObject(dragController)
            .environmentObject(keptAppStore).environmentObject(runningApplicationStore)
            .environmentObject(appMembershipController)
            .environment(\.dockThemeStyle, settingsStore.themeMaterial)
            .environment(\.themeTuning, settingsStore.themeTuning)
            .environment(\.iconSet, settingsStore.iconSet)
    }
}

private extension View {
    /// Hold-Control memory pill over a cell (Phase 20b).
    func memoryPill(_ bundleID: String, overlay: MemoryOverlayController) -> some View {
        self.overlay(alignment: .top) {
            if overlay.controlHeld, let bytes = overlay.memory[bundleID] { MemoryPill(bytes: bytes).offset(y: 4) }
        }
    }
}
