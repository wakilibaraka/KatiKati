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
    /// The plate's arrow, kept on the capsule by the coordinator (also signals live drawer visibility).
    @ObservedObject var arrow: StackPopupArrowModel
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
    @EnvironmentObject var settingsStore: AppSettingsStore
    var onOpenSettings: () -> Void = {}

    private enum ActivityTab: String, CaseIterable {
        case backgroundApps
        case processesRAM
    }

    @ObservedObject private var backgroundStore = BackgroundAppsStore.shared
    @AppStorage(BackgroundAppsStore.showSystemHelpersKey) private var showSystemHelpers = false
    @ObservedObject private var memoryOverlay = MemoryOverlayController.shared
    @StateObject private var processMonitor = ActivityProcessMonitor()
    @State private var selectedTab: ActivityTab = .backgroundApps

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
        let bgWidgets = settingsStore.surfaceWidgets.attachments(for: .backgroundAppsPopup)
        let extraWidgetHeight = DockWidgetConfigStore.popupSectionExtraHeight(for: bgWidgets)
        let deckWidth: CGFloat = DockWidgetConfigStore.defaultStackWidth
        let minPlateWidth = max(CGFloat(344), bgWidgets.isEmpty ? 0 : deckWidth + 28)

        let plate: StackPlateMetrics
        let layout: StackGridLayout.Result
        let introView: AnyView?

        if selectedTab == .processesRAM {
            let rows = min(6, max(4, limits.fitRowsWithNote))
            plate = StackPlateMetrics(
                cell: StackCellMetrics(cellSize: CGSize(width: 316, height: 44), iconSize: 22, iconTop: 6,
                                       labelGap: 0, labelSize: 13, labelWidth: 250, labelHeight: 18, truncatesLabelTail: true),
                sidePadding: 14, scrollingTrailingPadding: 24, scrollerGutter: 14,
                headerHeight: 34, titleCenterY: 19, hasSeparator: true, gridTop: 38, bottomPadding: 12, scrollsToBottomEdge: false
            )
            layout = StackGridLayout.Result(columns: 1, visibleRows: rows, scrolls: false)
            introView = arrow.isDrawerVisible ? AnyView(ProcessesRAMListView(processMonitor: processMonitor)) : nil
        } else if ids.isEmpty {
            plate = StackPlateMetrics(
                cell: StackCellMetrics(cellSize: CGSize(width: 316, height: 56), iconSize: 28, iconTop: 10,
                                       labelGap: 0, labelSize: 13, labelWidth: 280, labelHeight: 18, truncatesLabelTail: true),
                sidePadding: 14, scrollingTrailingPadding: 24, scrollerGutter: 14,
                headerHeight: 34, titleCenterY: 19, hasSeparator: true, gridTop: 38, bottomPadding: 12, scrollsToBottomEdge: false
            )
            layout = StackGridLayout.Result(columns: 1, visibleRows: 1, scrolls: false)
            introView = AnyView(
                Text("No apps are running in the background")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        } else {
            plate = StackPlateMetrics(
                cell: .backgroundApp, sidePadding: 14, scrollingTrailingPadding: 24, scrollerGutter: 14,
                headerHeight: 34, titleCenterY: 19, hasSeparator: true, gridTop: 38, bottomPadding: 12, scrollsToBottomEdge: false
            )
            layout = DrawerGridShape.backgroundApps(count: ids.count, limits: limits)
            introView = nil
        }

        return StackPopupChrome(title: String(localized: "Background & Activity"),
                                note: "",
                                layout: layout,
                                plate: plate,
                                usesLiquidGlass: usesLiquidGlass,
                                arrow: arrow,
                                onPanelSizeChange: onPanelSizeChange,
                                gridAnimation: .easeInOut(duration: DrawerAnimation.duration),
                                gridAnimationKey: ids + bgWidgets.map(\.id) + [selectedTab.rawValue],
                                intro: introView,
                                noteAccessory: AnyView(activityTabSwitcher),
                                headerAccessory: AnyView(DockSurfacePinMenuButton(surface: .backgroundAppsPopup, settingsStore: settingsStore)),
                                bottomAccessory: bgWidgets.isEmpty
                                    ? nil
                                    : AnyView(DockSurfacePinnedDeck(
                                        surface: .backgroundAppsPopup,
                                        usesLiquidGlass: usesLiquidGlass,
                                        width: deckWidth,
                                        settingsStore: settingsStore,
                                        onOpenSettings: onOpenSettings
                                    )),
                                bottomAccessoryHeight: extraWidgetHeight,
                                bottomAccessoryMinWidth: minPlateWidth) {
            if selectedTab == .backgroundApps && !ids.isEmpty {
                ForEach(ids, id: \.self) { backgroundChip($0).memoryPill($0, overlay: memoryOverlay) }
            }
        }
        .onHover { MemoryOverlayController.shared.pointer(inside: $0) }
        .onAppear { syncProcessMonitor() }
        .onDisappear { processMonitor.stop() }
        .onChange(of: arrow.isDrawerVisible) { _, _ in syncProcessMonitor() }
        .onChange(of: selectedTab) { _, _ in syncProcessMonitor() }
        // **面板打开没有入场动画**（owner 2026-09-04，理由见 `Docs/27`）。
    }

    private var activityTabSwitcher: some View {
        HStack(spacing: 4) {
            tabPill(.backgroundApps, title: String(localized: "Background Apps"))
            tabPill(.processesRAM, title: String(localized: "Processes & RAM"))
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    private func tabPill(_ tab: ActivityTab, title: String) -> some View {
        let active = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            Text(verbatim: title)
                .font(.system(size: 11, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? Color.white : Color.white.opacity(0.68))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(active ? Color.white.opacity(0.18) : Color.clear))
        }
        .buttonStyle(.plain)
    }

    private func syncProcessMonitor() {
        if arrow.isDrawerVisible && selectedTab == .processesRAM {
            processMonitor.start { Set(backgroundMembers) }
        } else {
            processMonitor.stop()
        }
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
                     scale: 0.7,
                     layout: .backgroundApp,
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
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var badgeStore: BadgeStore
    var onOpenSettings: () -> Void = {}

    var body: some View {
        DrawerView(limits: limits,
                   arrow: arrow,
                   onPanelSizeChange: onPanelSizeChange,
                   usesLiquidGlass: usesLiquidGlass,
                   isDrawerOpen: isDrawerOpen,
                   onPrimaryAction: onPrimaryAction,
                   onOpenSettings: onOpenSettings)
            .environmentObject(runtime).environmentObject(drawerStore).environmentObject(messagingStore)
            .environmentObject(drawerOrderStore).environmentObject(dragController)
            .environmentObject(keptAppStore).environmentObject(runningApplicationStore)
            .environmentObject(appMembershipController)
            .environmentObject(settingsStore)
            .environment(\.dockBadgesByBundleID, badgeStore.badgesByBundleID)
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

/// Live per-app & background-process RAM inspector shown strictly while the `Processes & RAM` tab is open.
private struct ProcessesRAMListView: View {
    @ObservedObject var processMonitor: ActivityProcessMonitor
    @StateObject private var systemMonitor = SystemMonitorController()

    var body: some View {
        let metrics = SystemGaugeMetrics.compute(
            usedMemory: systemMonitor.snapshot.memory.used,
            totalMemory: systemMonitor.snapshot.memory.total,
            cpuUsage: systemMonitor.snapshot.cpu
        )
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(verbatim: "RAM \(metrics.ramPercentage)% · CPU \(Int(round(metrics.cpuPressure * 100)))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.86))
                Spacer()
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                } label: {
                    Text("Activity Monitor")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
            if !processMonitor.hasSampled {
                Text("Sampling processes…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 4) {
                        ForEach(processMonitor.entries) { entry in
                            processRow(entry)
                        }
                    }
                    .padding(.trailing, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { systemMonitor.acquire() }
        .onDisappear { systemMonitor.release() }
    }

    private func processRow(_ entry: ProcessMemory.ProcessEntry) -> some View {
        HStack(spacing: 7) {
            Group {
                if let bundleID = entry.bundleID {
                    Image(nsImage: AppIconResolver.icon(for: bundleID))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 18, height: 18)

            Text(verbatim: entry.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)

            if entry.isBackgroundApp {
                Text("Background")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
            }

            Spacer(minLength: 4)
            MemoryPill(bytes: entry.bytes)

            if let bundleID = entry.bundleID {
                Button {
                    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help(Text("Quit"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}
