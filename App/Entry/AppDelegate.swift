import AppKit
import Combine
import QuartzCore
import SwiftUI
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// With `@NSApplicationDelegateAdaptor`, `NSApp.delegate` is SwiftUI's wrapper, not this class — so
    /// `NSApp.delegate as? AppDelegate` is nil. Anything that needs to call back into the delegate
    /// (notch gear, Settings › Restore Dock, edge-bar settings chip) goes through this instead.
    static private(set) weak var shared: AppDelegate?

    /// Window titles for the guide windows follow the localized bundle name (`InfoPlist.xcstrings`).
    static var localizedDisplayName: String {
        (Bundle.main.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
            ?? (Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? "KatiKati"
    }

    /// Must be the **first** stored property: every other store writes defaults inside its own
    /// init, so a snapshot taken one step later can no longer tell a prior install apart.
    private let installLineage = InstallLineage.capture()
    private let inventoryLog = WindowInventoryAnomalyLog()
    /// 在场屏幕表的唯一来源：窗口清单（归属键）与任务条投影（多屏 ④ 按屏过滤）都读它。
    let displayTopologyStore = DisplayTopologyStore(initialSnapshot: DisplayIdentity.topologySnapshot())
    private(set) lazy var runtime = AppRuntime(
        inventoryLog: inventoryLog,
        displayTableProvider: { [displayTopologyStore] in displayTopologyStore.table },
        isAccessibilityTrusted: { [weak self] in self?.cachedAccessibilityTrusted ?? false }
    )
    let drawerStore = DrawerStore()
    let messagingStore = MessagingAppStore()
    let badgeStore = BadgeStore()
    let weatherService = WeatherService()

    let keptAppStore = KeptAppStore()
    lazy var stripOrderStore = StripOrderStore(
        keptIDsProvider: { [keptAppStore] in Set(keptAppStore.bundleIDs) },
        stableKeptOrderProvider: { [keptAppStore, messagingStore] in
            keptAppStore.bundleIDs.filter { !messagingStore.contains($0) }
        },
        inventoryLog: inventoryLog
    )
    let drawerOrderStore = DrawerOrderStore()
    let settingsStore = AppSettingsStore()
    let pinnedFolderStore = PinnedFolderStore()
    let shelfStore = ShelfStore()
    let runningApplicationStore = RunningApplicationStore()
    private(set) lazy var appMembershipController = AppMembershipController(
        keptAppStore: keptAppStore,
        drawerStore: drawerStore,
        messagingStore: messagingStore
    )
    /// lazy：sortOrderProvider 要引用 pinnedFolderStore（封面跟随该文件夹当前排序的第一个文件）。
    private(set) lazy var folderCoverStore = PinnedFolderCoverStore(
        sortOrderProvider: { [pinnedFolderStore] path in pinnedFolderStore.sortOrder(for: path) },
        isUnopenedSeed: { [pinnedFolderStore] path in pinnedFolderStore.isUnopenedSeed(path) }
    )
    private var panelCoordinator: TaskbarScreenOrchestrator?
    private var windowLiftAvoidanceController: WindowLiftAvoidanceController?
    private lazy var launchAtLoginService = LaunchAtLoginService()
    private lazy var nativeDockPreferencesService = NativeDockPreferencesService()
    private let updateService = SparkleUpdateService()
    private lazy var settingsCoordinator = SettingsCoordinator(
        store: settingsStore,
        launchAtLoginService: launchAtLoginService,
        nativeDockPreferencesService: nativeDockPreferencesService,
        updateService: updateService,
        // 改键的真实注册入口。临时副本没有 monitor（也进不了设置窗口），兜底报失败。
        hotKeyRegistrar: { [weak self] shortcut in
            self?.edgeToggleHotKey?.update(shortcut: shortcut) ?? .monitorUnavailable
        }
    )
    private lazy var settingsWindowController = SettingsWindowController(
        store: settingsStore,
        coordinator: settingsCoordinator,
        // 直通 showWelcomeWindow()，不走 presentWelcomeGuideIfNeeded()——那条对
        // hasSeenWelcome 已置位的存量用户永远静默跳过，而存量用户正是这个入口的全部受众。
        // 入口 2026-09-01 从状态栏菜单搬进设置卡「通用」页（owner 拍板）；直通这一点不变。
        onShowWelcomeGuide: { [weak self] in self?.showWelcomeWindow() }
    )
    /// 常驻切换全局快捷键。回调只切设置（经 settingsStore），不经过 panelCoordinator——
    /// 后者在权限引导完成前是 nil，settingsStore 从 AppDelegate 构造起即存在。
    private var edgeToggleHotKey: GlobalHotKeyMonitor?
    private lazy var menuBarSystem = MenuBarSystemItem()
    private lazy var windowSwitcher = WindowSwitcherController(runtime: runtime)
    private(set) lazy var layoutRestore = WindowLayoutRestoreController(runtime: runtime, displayTable: { [displayTopologyStore] in displayTopologyStore.table })
    private let shortcutService = ShortcutService()
    private let hyperkeyService = HyperkeyService()
    private var hyperkeySubscription: AnyCancellable?
    /// Created only while Settings → Shortcuts → Pinch is on.
    private var pinchMonitor: MultitouchPinchMonitor?
    private var pinchSubscription: AnyCancellable?
    private let shortcutToast = ShortcutToastPresenter()
    /// Phase 8b-4B: the Live Island's app-wide event feed. A **single** instance on purpose — each
    /// island has its own rendering feed, so per-island detection would fire the same toast N times
    /// on a multi-display setup (see `LiveEventCenter`'s header).
    private let liveEventCenter = LiveEventCenter()
    /// Phase 8b-7: the notch skin of the Live Island. Built lazily — only while the setting is on.
    private let notchPanel = NotchPanelController()
    /// Phase 8e menu utilities. The cleaner polls only while its setting is on.
    private let linkCleaner = LinkCleanerService()
    private var linkCleanerSubscription: AnyCancellable?
    private lazy var colorPicker = ColorPickerService(toast: shortcutToast)
    private var notchSubscription: AnyCancellable?
    private var notchSkinSubscription: AnyCancellable?
    private lazy var dragShakeWatcher = DragShakeWatcher(shelf: shelfStore)
    private var shelfShakeSubscription: AnyCancellable?
    private var shortcutSubscription: AnyCancellable?
    private let screenTimeAlerts = ScreenTimeAlertPresenter()
    /// Phase 16g: the Control Center side panel (wifi deck button + the Quick Settings shortcut).
    private lazy var controlCenterPanel: ControlCenterPanelController = {
        let panel = ControlCenterPanelController()
        panel.widgets = { [weak self] in
            (self?.settingsStore.controlCenterWidgets ?? TileKind.controlCenterDefault)
                .filter(TileKind.controlCenterDefault.contains)
        }
        panel.toggleOrder = { [weak self] in self?.settingsStore.controlCenterToggles ?? QuickToggleID.defaultOrder }
        panel.panelSize = { [weak self] in self?.settingsStore.controlCenterSize ?? .default }
        panel.panelAnchor = { [weak self] in self?.settingsStore.controlCenterAnchor ?? .default }
        panel.panelAnimation = { [weak self] in self?.settingsStore.controlCenterAnimation ?? .default }
        panel.bottomReserve = { [weak self] in
            guard let store = self?.settingsStore, store.stripPlacementMap.global == .bottom else { return 0 }
            return Double(store.dockPanelHeight.points + store.bottomGap + 8)
        }
        panel.onSettings = { [weak self] in self?.openSettings(nil) }
        panel.onLauncher = { [weak self] in self?.launcherPanel.toggle() }
        panel.onCapture = { ScreenshotCommand.run() }
        panel.onDrawer = { [weak self] in self?.panelCoordinator?.toggleDrawer() }
        panel.onQuit = { NSApp.terminate(nil) }
        return panel
    }()
    /// Shown from the edge deck's wifi button (`AppDelegate.shared?.toggleControlCenter()`).
    func toggleControlCenter() { controlCenterPanel.toggle() }
    /// Shown from the radial dial / command bar (`AppDelegate.shared?.toggleShelf()`).
    func toggleShelf() { panelCoordinator?.toggleShelf() }
    private func applyPinch(_ on: Bool) {
        guard on else { pinchMonitor?.stop(); pinchMonitor = nil; return }
        guard pinchMonitor == nil else { return }
        let monitor = MultitouchPinchMonitor()
        monitor.onPinch = { [weak self] in self?.launcherPanel.toggle() }
        if monitor.start() { pinchMonitor = monitor }
    }

    private lazy var launcherPanel: LauncherPanelController = {
        let panel = LauncherPanelController()
        panel.searchPosition = { [weak self] in self?.settingsStore.launcherSearchPosition ?? .top }
        panel.scrollDirection = { [weak self] in self?.settingsStore.launcherScrollDirection ?? .horizontal }
        panel.look = { [weak self] in (self?.settingsStore.launcherTheme ?? .system, self?.settingsStore.launcherTint ?? .none) }
        panel.keptApps = { [weak self] in self?.keptAppStore.bundleIDs ?? [] }
        panel.bottomBarReserve = { [weak self] in
            guard let store = self?.settingsStore, store.stripPlacementMap.global == .bottom else { return 0 }
            return Double(store.dockPanelHeight.points + store.bottomGap + 8)
        }
        panel.sideBarReserve = { [weak self] in
            guard let store = self?.settingsStore else { return (0, 0) }
            let reserve = Double(store.dockPanelHeight.points + store.bottomGap + 8)
            switch store.stripPlacementMap.global {
            case .bottom: return (0, 0)
            case .left: return (reserve, 0)
            case .right: return (0, reserve)
            }
        }
        return panel
    }()
    /// Phase 27: the ⌘Space command bar, kept separate from the full-screen launcher.
    private(set) lazy var commandBarPanel = CommandBarPanelController()
    /// Phase 31: the colourful interactive radial dial / pie menu.
    private(set) lazy var radialDialPanel = RadialDialPanelController.shared
    /// Phase 23: the define/translate card for the current selection.
    private lazy var translatePanel = TranslatePanelController()
    private var terminationTask: Task<Void, Never>?
    private var terminationSignalSources: [DispatchSourceSignal] = []
    private var debugWindow: NSWindow?
    /// 只在 `DOCK_HOVER_TRACE=1` 时存在，见 `startMainLoopStallProbeIfTracing`。
    private var mainLoopStallProbe: Timer?
    private var permissionWindow: NSWindow?
    private var permissionHostingView: NSHostingView<PermissionOnboardingWindowContent>?
    private var welcomeWindow: NSWindow?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var messagingAutoRegisterSubscription: AnyCancellable?
    private var badgeContextSubscription: AnyCancellable?
    private var windowLiftSettingSubscription: AnyCancellable?
    private var trashSettingSubscription: AnyCancellable?
    /// 全局反转鼠标滚轮。active tap 需要辅助功能授权，所以挂在任务条运行期
    ///（startTaskbarRuntime 建、suspend/终止拆），与全屏 tap 同一生命周期语义。
    private var scrollReverserMonitor: ScrollReverserMonitor?
    private var scrollReverserSettingSubscription: AnyCancellable?
    /// Lives for the whole process: the guide windows need the appearance too, so it is never
    /// cancelled with the taskbar's subscriptions.
    private var appearanceSubscription: AnyCancellable?
    private let permissionService = PermissionService()
    private var installLocation: AppInstallLocation = .other
    private var permissionCoordinator: PermissionRecoveryCoordinator?
    private var permissionWatchdogTimer: Timer?
    private var permissionWatchdogGate = PermissionWatchdogGate()
    private let permissionProbeQueue = DispatchQueue(label: "com.caye.macosdockcc.v2.permission-probe", qos: .utility)
    private var cachedAccessibilityTrusted = false
    private var hasStartedApp = false
    /// Launched without the Accessibility grant: the bar, launcher and Control Center still run, the status menu asks for the
    /// permission, and the app relaunches itself once the grant lands (window management needs a fresh process).
    private var isLimitedMode = false
    private var limitedModeTimer: Timer?
    private var skipsPermissionGate: Bool { isLimitedMode || DebugSwitch.devSkipPermissions.isEnabled() }
    private let permissionLogger = Logger(subsystem: "com.caye.macosdockcc.v2", category: "permissions")
    private lazy var statusMenuController = StatusMenuController(
        store: settingsStore,
        settingsCoordinator: settingsCoordinator,
        isAccessibilityTrusted: { [weak self] in self?.cachedAccessibilityTrusted ?? false },
        onShowDebugConsole: { [weak self] in self?.showDebugConsole() },
        onExportDebugSnapshot: { [weak self] in self?.exportDebugSnapshot() },
        onShowSettings: { [weak self] in self?.openSettings(nil) },
        onPickColor: { [weak self] in self?.colorPicker.pick() },
        recentlyClosed: {
            let store = RecentlyClosedStore.shared
            return store.restorable().map { entry in
                let icon = NSWorkspace.shared.icon(forFile: entry.url.path)
                icon.size = NSSize(width: 16, height: 16)
                return StatusMenuController.RecentlyClosedEntry(
                    title: AppDisplayNameResolver.displayName(for: entry.id), icon: icon,
                    restore: { [weak store] in store?.restore(entry.url) })
            }
        },
        onShowLayoutSettings: { [weak self] in self?.openSettings(selecting: .appearance) },
        onMenuVisibilityChanged: { [weak self] isOpen in
            self?.panelCoordinator?.setTaskbarMenuOpen(isOpen)
        },
        onRequestAccessibility: { [weak self] in self?.requestAccessibilityFromMenu() },
        onQuit: { NSApp.terminate(nil) },
        hotKeyGlyphs: { [weak self] in
            self?.edgeToggleHotKey?.shortcut.displayGlyphs
                ?? GlobalHotKeyShortcut.edgeAutoHideMode.displayGlyphs
        },
        isToggleHotKeyRegistered: { [weak self] in self?.edgeToggleHotKey?.isRegistered ?? false },
        connectedScreens: { DisplayIdentity.connectedScreenOptions() }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        WallpaperEngine.shared.configure(settings: settingsStore, weather: weatherService)
        ContextPresetController.shared.configure(settings: settingsStore)
        WeatherPanelHost.service = weatherService
        // 行缓冲 stdout：从命令行/后台启动时，print() 输出到文件默认是块缓冲，
        // 日志要攒满缓冲区才落盘。改成行缓冲后每条 print 立即写出，便于实时读日志。
        setvbuf(stdout, nil, _IOLBF, 0)
        installTerminationSignalHandlers()

        startMainLoopStallProbeIfTracing()
        StackPopupSnapshotProbe.runIfRequested()

        // Install lineage was captured before any store was constructed.
        let isFreshInstall = installLineage == .pristine
        // 全新安装把最大化避让播种为开；老用户维持关（它会改写别人应用的窗口尺寸，
        // 不能靠一次升级静默打开）。理由见 `AppSettingsStore.seedWindowLiftEnabledForFreshInstall`。
        if isFreshInstall {
            settingsStore.seedWindowLiftEnabledForFreshInstall(lineage: installLineage)
            settingsStore.armTaskbarPerDisplaySeedForFreshInstall(lineage: installLineage)
            pinnedFolderStore.seedDownloadsForFreshInstall(lineage: installLineage)
            keptAppStore.seedDefaultAppsForFreshInstall(lineage: installLineage) {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
            }
        }

        // The appearance setting is applied here and only here (`nil` = follow macOS). The frosted
        // material and Liquid Glass follow the **window's** `effectiveAppearance`, and SwiftUI's
        // `colorScheme` — which picks the `DockThemeTokens` column — comes from the same place, so
        // text and plate flip together. Do not set `appearance` on an individual panel or hosting
        // view: every window leaves it unset and inherits this one, including those created later
        // on demand (drawer, bubble, drag carrier) and the menus. The stack popups pin `darkAqua`
        // on their glass view alone (`stack-popup.md`).
        //
        // It stays ahead of the three launch branches (relocation guide, permission guide, normal
        // start) so each one's first window opens in the right appearance. `@Published` emits the
        // current value on subscription, which is what applies it at launch.
        appearanceSubscription = settingsStore.$appearanceMode
            .sink { NSApp.appearance = $0.nsAppearance }

        // 位置分类必须排在接管其他实例和注册热键**之前**。
        // 挂载磁盘映像双击运行时，那份临时副本一旦执行 terminateOtherInstances()，
        // 就会把用户正在用的 /Applications 实例杀掉，自己却只显示一个搬家引导；
        // 抢注了全局热键还会让正常实例的 ⌥⇧⌘D 失灵。
        let location = AppInstallLocation(
            bundleURL: Bundle.main.bundleURL,
            isReadOnlyVolume: { [permissionService] in permissionService.isReadOnlyVolume($0) }
        )
        installLocation = location
        let trusted = permissionService.hasRequiredPermissions()
        cachedAccessibilityTrusted = trusted
        isLimitedMode = !trusted && !location.isTransient
        logPermissionLaunch(installLocation: location, isTrusted: trusted)

        if !location.isTransient {
            terminateOtherInstances()

            // 先注册热键再建状态菜单：菜单构建时要读注册状态决定是否显示快捷键提示。
            // Carbon 热键不依赖辅助功能权限，不用等权限引导分支。
            // 用户自定义过就用存的组合；坏数据在 store 读入时已回落 nil（= 默认 ⌥⇧⌘D）。
            let shortcut = settingsStore.edgeToggleShortcut.map(GlobalHotKeyShortcut.init(stored:))
                ?? .edgeAutoHideMode
            let hotKey = GlobalHotKeyMonitor(shortcut: shortcut) { [weak self] in
                self?.settingsStore.toggleEdgeAutoHideMode()
            }
            edgeToggleHotKey = hotKey
            let hotKeyStatus = hotKey.start()
            if hotKeyStatus != .registered {
                Logger(subsystem: "com.caye.macosdockcc.v2", category: "hotkey")
                    .warning("常驻切换全局快捷键注册失败：\(String(describing: hotKeyStatus), privacy: .public)，本次启动不重试")
            }

            shortcutService.onAction = { [weak self] action in
                guard let self else { return }
                switch action {
                case .launcher: self.launcherPanel.toggle()
                case .commandBar: self.commandBarPanel.toggle()
                case .translate: self.translatePanel.toggleSelection()
                case .pinboard: self.controlCenterPanel.toggle()
                case .quickSettings: self.controlCenterPanel.toggle()
                case .drawer: self.panelCoordinator?.toggleDrawer()
                case .notchTools: self.notchPanel.toggleTools()
                case .weather: WidgetPanelController.weather.toggle()
                case .clock: WidgetPanelController.calendar.toggle()
                case .keepAwake:
                    let engine = QuickToggleEngine.shared
                    engine.setKeepAwake(!engine.keepAwakeOn)
                    self.shortcutToast.show(engine.keepAwakeOn ? String(localized: "Keep Awake On") : String(localized: "Keep Awake Off"),
                                            symbol: "cup.and.saucer.fill")
                case .toggleTiling:
                    TilingEngine.shared.setEnabled(!TilingEngine.shared.isEnabled)
                case .cycleTilingLayout:
                    TilingEngine.shared.cycleLayout()
                case .tilingFocusNext:
                    TilingEngine.shared.focusNext()
                case .tilingFocusPrevious:
                    TilingEngine.shared.focusPrevious()
                case .tilingSwapNext:
                    TilingEngine.shared.swapNext()
                case .tilingSwapPrevious:
                    TilingEngine.shared.swapPrevious()
                case .radialDial:
                    self.radialDialPanel.toggle()
                default:
                    // Phase 26a: snap-zone hotkeys — any action with a SnapPosition calls the service.
                    if let position = action.snapPosition {
                        WindowSnapService.apply(position)
                    }
                }
            }
            hyperkeyService.onAction = shortcutService.onAction
            hyperkeySubscription = settingsStore.$shortcutBindings
                .combineLatest(settingsStore.$hyperkeyEnabled)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] bindings, enabled in
                    var map: [UInt16: ShortcutAction] = [:]
                    for (action, trigger) in bindings { if case let .hyper(code) = trigger { map[code] = action } }
                    self?.hyperkeyService.configure(enabled: enabled, bindings: map)
                }
            shortcutSubscription = settingsStore.$shortcutBindings
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.shortcutService.apply($0) }
            pinchSubscription = settingsStore.$launcherPinch
                .receive(on: DispatchQueue.main)
                .sink { [weak self] on in self?.applyPinch(on) }
            KeyGuardService.shared.refresh()
            NotificationMoveService.shared.refresh()
            DailyHelpersService.shared.deliver = { [weak self] in self?.liveEventCenter.deliver($0, now: Date()) }
            DailyHelpersService.shared.start()

            let screenTime = ProductivityServices.shared.screenTime
            screenTime.onLimitAction = { [weak self, weak screenTime] id, name, action in
                guard let screenTime else { return }
                self?.screenTimeAlerts.show(bundleID: id, name: name, action: action, controller: screenTime)
            }
            screenTime.startIfEnabled()

            // Phase 8b-4B: start the Live Island's event feed last, once everything it watches is
            // live, so the seed snapshot is the real state — no phantom "events" from launch order.
            liveEventCenter.isSurfaceEnabled = { [weak self] surface in
                switch surface {
                case .dock: return self?.settingsStore.dockIslandEnabled ?? true
                case .notch: return (self?.settingsStore.notchIslandEnabled ?? false) && (self?.notchPanel.isUsable ?? false)
                }
            }
            linkCleanerSubscription = settingsStore.$linkCleanerEnabled
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] on in self?.linkCleaner.setEnabled(on) }
            shelfShakeSubscription = settingsStore.$shelfShakeEnabled
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] on in self?.dragShakeWatcher.setEnabled(on) }
            notchSkinSubscription = settingsStore.$notchSkin
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] skin in self?.notchPanel.skin = skin }
            notchPanel.onOpenSettings = { [weak self] in self?.openSettings(nil) }
            notchPanel.theme = { [weak self] in self?.settingsStore.nowPlayingTheme ?? .auto }
            liveEventCenter.register(sink: notchPanel, for: .notch)
            notchSubscription = settingsStore.$notchIslandEnabled
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] on in self?.notchPanel.setEnabled(on) }
            liveEventCenter.osBannersEnabled = { [weak self] in self?.settingsStore.liveEventOSBanners ?? false }
            liveEventCenter.route = { [weak self] in self?.settingsStore.liveEventRoute ?? .automatic }
            liveEventCenter.start()
            ProductivityServices.shared.clipboard.onRecorded = { [weak self] text in
                guard UserDefaults.standard.bool(forKey: ClipboardMonitor.notchToastKey),
                      ClipboardToastPolicy.shouldToast(text) else { return }
                self?.liveEventCenter.deliver(.clipboardCopied(preview: ClipboardHistory.previewLine(text)), now: Date())
            }
            DownloadsMonitor.shared.onFinished = { [weak self] name in
                self?.liveEventCenter.deliver(.downloadFinished(name: name), now: Date())
            }
            RecentlyClosedStore.shared.start()

            _ = statusMenuController

            // 自动更新只在正常安装的副本上跑。挂载在 DMG 里的临时副本更新自己毫无意义
            // ——它卸载就没了——和上面不给它注册全局热键、不向系统申请权限是同一条理由。
            updateService.start()
        }

        let coordinator = PermissionRecoveryCoordinator(
            handler: self,
            permissionService: permissionService,
            installLocation: location
        )
        permissionCoordinator = coordinator
        // DOCK_DEV_SKIP_PERMISSIONS=1 (dev-only): follow the machine's trusted path so
        // `startApp` runs and panels render with no AX grant — the untrusted path would fire
        // `requestSystemPrompt` + onboarding (the prompt this switch exists to skip). Watchdog,
        // guide and suspension effects stay guarded below, so no revocation episode can follow.
        coordinator.launched(trusted: trusted || skipsPermissionGate)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // 用户从系统设置切回来时立刻复检，不用等下一次轮询。
        permissionCoordinator?.applicationDidBecomeActive()
        if !installLocation.isTransient {
            Task { @MainActor [weak self] in
                _ = await self?.settingsCoordinator.refreshLaunchAtLoginState()
            }
        }
    }

    private func logPermissionLaunch(installLocation: AppInstallLocation, isTrusted: Bool) {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        permissionLogger.info("""
            permission launch version=\(version, privacy: .public) \
            build=\(build, privacy: .public) \
            location=\(installLocation.rawValue, privacy: .public) \
            trusted=\(isTrusted, privacy: .public) \
            bundlePath=\(Bundle.main.bundleURL.path, privacy: .private(mask: .hash))
            """)
    }

    /// 同一个 bundle id 的另一份包（`/Applications` 正式包 vs 构建目录里的开发包）可以
    /// 同时运行，屏幕上就会出现两条一模一样的任务条，测到的是哪个版本谁也说不清——
    /// 2026-07-21 因此把一个其实没验证过的修复判成「不行」并整个回退。
    ///
    /// 采取「后启动的接管」：新实例踢掉旧实例。反过来（新的自己退出）会挡住开发时的
    /// 验证构建，也和 `Scripts/build_and_run.sh` 先 pkill 再启动的既有行为矛盾。
    /// 用礼貌的 `terminate()` 而不是强杀，让旧实例的 `stopAndRestore` 把被抬起的窗口
    /// 还原回去；只有它迟迟不退时才强制结束，避免"两个任务条"这个原始症状复发。
    private func terminateOtherInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID && !$0.isTerminated }
        guard !others.isEmpty else { return }

        let logger = Logger(subsystem: "com.caye.macosdockcc.v2", category: "instance")
        for app in others {
            logger.warning("""
                发现另一个钨极实例，终止它：pid=\(app.processIdentifier, privacy: .public) \
                path=\(app.bundleURL?.path ?? "(unknown)", privacy: .public)
                """)
            app.terminate()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            for app in others where !app.isTerminated {
                logger.error("旧实例 pid=\(app.processIdentifier, privacy: .public) 3 秒内未退出，强制结束")
                app.forceTerminate()
            }
        }
    }

    /// SIGTERM / SIGINT 默认直接杀进程，绕过 `applicationShouldTerminate`，被抬起的窗口就留在原地
    /// （5b 演练实测）。改成走礼貌退出，让 `stopAndRestore` 先把窗口还回去。
    private func installTerminationSignalHandlers() {
        guard terminationSignalSources.isEmpty else { return }
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            // 不能直接在这个 GCD 块里调 terminate：它会在主队列块里嵌套跑事件循环，
            // 而 `stopAndRestore` 的 Task 也要靠主队列推进——两边互等，永远退不出去（演练实测）。
            // 用 runloop 定时器触发，才和 AppleEvent 退出走同一条路径。
            source.setEventHandler {
                NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0, inModes: [.common])
            }
            source.resume()
            terminationSignalSources.append(source)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // 收尾等待（stopAndRestore）期间事件循环还在跑：先切断热键输入，避免设置被继续切换，
        // 并让协调器取消在飞的恢复任务——光设阶段拦不住已经进了 await 的 Task，
        // 那会在退出之后还去拉起一个新实例。
        edgeToggleHotKey?.stop()
        // 滚轮 tap 同理先拆：进程退出前多活一秒，全系统的滚动就多经手一秒。
        scrollReverserMonitor?.stop()
        scrollReverserMonitor = nil
        permissionCoordinator?.terminationRequested()

        guard let controller = windowLiftAvoidanceController else { return .terminateNow }
        // 没有权限时 AX 写不动窗口，等 stopAndRestore 只是白等。
        guard permissionService.hasRequiredPermissions() else { return .terminateNow }
        guard terminationTask == nil else { return .terminateLater }

        terminationTask = Task { @MainActor [weak self] in
            await controller.stopAndRestore()
            self?.terminationTask = nil
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Give the system Dock back as the user had it before KatiKati hid it (next launch re-hides it).
        nativeDockPreferencesService.restoreOriginal()
        WallpaperEngine.shared.restoreForQuit()
        SystemResizeCursor.shared.reset()   // never leave the ▲▼ or a hidden pointer behind us
        SystemCursorHider.shared.show()
        trashSettingSubscription = nil
        TrashStateStore.shared.stop()
        edgeToggleHotKey?.stop()
        scrollReverserMonitor?.stop()
        scrollReverserMonitor = nil
        DocumentUsageStore.shared.stop()
        permissionCoordinator?.terminationRequested()
        windowLiftAvoidanceController?.stop()
        // 私有空间进程一死 WindowServer 自会回收，这里只是不留垃圾空间。
        panelCoordinator?.overlaySpaceHost?.tearDown()
        runtime.stop()
    }

    // MARK: - 首次运行欢迎引导

    /// 首次运行的一次性引导：建议把系统 Dock 收起来。
    ///
    /// 只在 `startTaskbarRuntime()` 末尾调一次，也就是「权限已授、面板已建、任务条真的在跑」
    /// 的那一刻。临时副本（DMG 里双击运行的那份）永远走不到这里——它在
    /// `PermissionRecoveryMachine` 里只有 `showGuide` 一条效果——这是对的，那份副本
    /// 卸载就没了，不该教它配置系统。
    private func presentWelcomeGuideIfNeeded() {
        // 先用不需要 I/O 的两个条件挡一道，省掉绝大多数启动的那次异步读。
        guard !settingsStore.hasSeenWelcome else { return }

        let canWrite = nativeDockPreferencesService.isAvailable
        guard canWrite else {
            _ = WelcomeGuideDecision.evaluate(
                hasSeenWelcome: false,
                canWriteDockPreferences: false,
                dockAutohideEnabled: nil
            )
            settingsStore.setHasSeenWelcome(true)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let state = await self.nativeDockPreferencesService.currentAutohideState()
            // 这一轮 await 期间用户可能已经从别处看过/改过了，所以重新读一遍标记。
            switch WelcomeGuideDecision.evaluate(
                hasSeenWelcome: self.settingsStore.hasSeenWelcome,
                canWriteDockPreferences: true,
                dockAutohideEnabled: state?.enabled
            ) {
            case .present:
                self.showWelcomeWindow()
            case .skipAndMarkSeen:
                self.settingsStore.setHasSeenWelcome(true)
            case .skipWithoutMarking:
                break
            }
        }
    }

    private func showWelcomeWindow() {
        if let welcomeWindow {
            welcomeWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let layoutContext = WelcomeGuideLayoutContext(
            initialMode: settingsStore.barLayoutMode,
            inputs: settingsStore.layoutThumbnailInputs,
            onPick: { [weak self] mode in self?.settingsStore.setBarLayoutMode(mode) },
            initialStyleID: settingsStore.currentDockStyle?.id,
            onPickStyle: { [weak self] style in
                self?.settingsStore.applyDockStyle(style, screenWidth: NSScreen.main?.frame.width ?? 1440)
            },
            initialTheme: settingsStore.themeMaterial,
            onPickTheme: { [weak self] theme in self?.settingsStore.setThemeMaterial(theme) },
            notchEnabled: settingsStore.notchIslandEnabled,
            notchSkin: settingsStore.notchSkin,
            onNotchToggle: { [weak self] on in self?.settingsStore.setNotchIslandEnabled(on) }
        )
        let content = WelcomeGuideWindowContent(
            layout: layoutContext,
            onApply: { [weak self] selection in self?.applyWelcomeSelection(selection) },
            onDismiss: { [weak self] in self?.dismissWelcomeGuide() }
        )
        let hosting = NSHostingView(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: WelcomeGuideView.contentWidth, height: 320),
            // 和权限引导不同，这一扇**可关**：权限没授时 app 根本不能用，那扇窗关掉没有意义；
            // 这一扇只是个建议，用户有权直接叉掉（叉掉等同「以后再说」，见 windowWillClose）。
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = Self.localizedDisplayName
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.delegate = self
        welcomeWindow = window

        // 高度量法同权限引导：根视图外面套了 ScrollView，得用一次性探针量不加滚动时的自然高度。
        let probe = NSHostingView(rootView: WelcomeGuideView(layout: layoutContext, onApply: { _ in }, onDismiss: {}))
        probe.setFrameSize(NSSize(width: WelcomeGuideView.contentWidth, height: 0))
        probe.layoutSubtreeIfNeeded()
        let available = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        window.setContentSize(NSSize(
            width: WelcomeGuideView.contentWidth,
            height: max(200, min(probe.fittingSize.height, available - 80))
        ))

        window.center()
        window.makeKeyAndOrderFront(nil)
        // 钨极此刻是 accessory app，不主动 activate 的话这扇窗会被压在前台应用后面，
        // 和 2026-07-29 那次「检查更新看起来失效」是同一个坑。
        // 注意**不要**顺手改成 .regular——那会让程序坞里冒出一个钨极图标，
        // 正好和这扇窗要讲的事情自相矛盾。
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 「应用推荐设置」：按用户勾了哪几条写系统 Dock 偏好。隐藏那一档是自动隐藏 + 不唤醒
    /// （owner 2026-08-20 定的推荐档位）。
    ///
    /// 走 `applyNativeDock(recommendations:)` 这个唯一写入口，四象限回读和镜像同步都是白拿的；
    /// 别在这里另起一条 defaults 写入。三条合成一次 `killall Dock`，屏幕只闪一次。
    private func applyWelcomeSelection(_ selection: WelcomeGuideSelection) {
        settingsStore.setHasSeenWelcome(true)
        closeWelcomeWindow()

        let recommendations = selection.recommendations(hideDelay: AppSettingsStore.neverWakeDelay)
        // 一条都没勾时按钮本就置灰，这是兜底：什么都不写，也就不该重启 Dock 让屏幕白闪一下。
        guard !recommendations.isEmpty else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await self.settingsCoordinator.applyNativeDock(
                recommendations: recommendations
            )
            guard let error = outcome.error else { return }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Couldn’t Change Dock Settings")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: String(localized: "OK"))
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    /// 「以后再说」，以及直接叉掉窗口。**照样记成已看过**——不再骚扰；
    /// 想改的人走状态栏菜单里那条系统 Dock 滑杆。
    private func dismissWelcomeGuide() {
        settingsStore.setHasSeenWelcome(true)
        closeWelcomeWindow()
    }

    private func closeWelcomeWindow() {
        guard let window = welcomeWindow else { return }
        welcomeWindow = nil
        window.delegate = nil
        window.orderOut(nil)
        window.close()
    }

    /// 引导窗口。文案长度随状态变化很大（排障区展开时几乎翻倍），
    /// 所以宽度固定、高度跟着内容走，并以当前屏幕可视高度封顶。
    private func showPermissionWindow() {
        guard let coordinator = permissionCoordinator else { return }
        if let permissionWindow {
            resizePermissionWindowToFit()
            permissionWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingView(rootView: PermissionOnboardingWindowContent(coordinator: coordinator))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: PermissionOnboardingView.contentWidth, height: 260),
            styleMask: [.titled, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = Self.localizedDisplayName
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        permissionWindow = window
        permissionHostingView = hosting
        resizePermissionWindowToFit()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func resizePermissionWindowToFit() {
        guard let window = permissionWindow, let coordinator = permissionCoordinator else { return }

        // 用一次性探针量「不加滚动时的自然高度」：真正的根视图外面套了 ScrollView，
        // 它自己的 fittingSize 量不出内容有多高。
        let probe = NSHostingView(rootView: PermissionOnboardingView(coordinator: coordinator))
        probe.setFrameSize(NSSize(width: PermissionOnboardingView.contentWidth, height: 0))
        probe.layoutSubtreeIfNeeded()
        let natural = probe.fittingSize.height

        let available = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        let height = max(200, min(natural, available - 80))
        let size = NSSize(width: PermissionOnboardingView.contentWidth, height: height)
        guard window.contentView?.frame.size != size else { return }

        let before = window.frame
        window.setContentSize(size)
        // 保持视觉中心不动，别让窗口在文案变长时往下窜。
        let after = window.frame
        window.setFrameOrigin(NSPoint(
            x: before.midX - after.width / 2,
            y: before.midY - after.height / 2
        ))
    }

    private func closePermissionWindow() {
        permissionWindow?.orderOut(nil)
        permissionWindow?.close()
        permissionWindow = nil
        permissionHostingView = nil
    }

    private func startTaskbarRuntime() {
        appMembershipController.reconcileInvalidMemberships()
        runningApplicationStore.start()
        runtime.start()
        windowSwitcher.start()
        layoutRestore.start()
        TilingEngine.shared.start(snapshotStream: runtime.$snapshot)
        menuBarSystem.start()

        // Auto tier of the messaging list: register an app only when it both matches the
        // whitelist / social-networking category **and** currently has an identifiable main
        // window, then seed kept on first registration (default-keep). Kept no longer excludes
        // messaging, so there is no kept filter.
        //
        // The window snapshot is combined in because the capability gate needs titles — the
        // process store alone cannot tell whether the zone can represent the app. Registration
        // is once-and-for-all (see `MessagingAppStore.autoRegister`), so the "identifiable right
        // now" reading is only ever consumed for apps not yet in the list; existing members are
        // never re-tested and therefore never flap out of the zone.
        messagingAutoRegisterSubscription = runningApplicationStore.$runningBundleIDs
            .combineLatest(runtime.$snapshot)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running, snapshot in
                guard let self else { return }
                let identifiable = MessagingZoneAdmission.mainWindowIdentifiableBundleIDs(
                    windows: StripItem.items(from: snapshot).map {
                        .init(bundleID: $0.bundleIdentifier ?? "",
                              title: $0.title,
                              isAppLevelFallback: $0.isAppLevelFallback)
                    },
                    titleMatchesAppName: { title, bundleID in
                        AppDisplayNameResolver.titleMatchesAppName(title, bundleID: bundleID)
                    }
                )
                self.appMembershipController.autoRegisterMessaging(
                    runningBundleIDs: running,
                    mainWindowIdentifiableBundleIDs: identifiable
                )
            }

        // 角标读取范围 = 消息应用**身份** ∩ 在跑 − 抽屉（2026-08-23 起不再要求在消息区里：
        // 信息 / Slack 这类进不了区的单窗口应用，红点画在它们常规区的卡上）。名单或在跑集合
        // 一变就推给 BadgeStore：可读集为空时它每 tick 零 AX 流量；集合变化触发重走 Dock 树，
        // 「消息应用刚启动、新磁贴上出角标」靠这条在 ~1s 内补上。订阅先于 badgeStore.start()，
        // 首次读取前上下文已就位（@Published 订阅即发当前值）。
        // `isMessagingApp` 回读 store：这里有 receive(on:) 异步派发，发布早已完成，读到的是新值。
        badgeContextSubscription = Publishers.CombineLatest3(
            messagingStore.$bundleIDs,
            drawerStore.$bundleIDs,
            runningApplicationStore.$runningBundleIDs
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, drawer, running in
            guard let self else { return }
            self.badgeStore.updateMessagingContext(
                visibleMessagingIDs: AppMembershipProjection.badgeEligibleIDs(
                    isMessagingApp: { self.messagingStore.isMessagingApp($0) },
                    drawerIDs: drawer,
                    runningIDs: running
                ),
                runningBundleIDs: running
            )
        }

        let coordinator = TaskbarScreenOrchestrator(
            runtime: runtime,
            drawerStore: drawerStore,
            messagingStore: messagingStore,
            badgeStore: badgeStore,
            weatherService: weatherService,
            stripOrderStore: stripOrderStore,
            drawerOrderStore: drawerOrderStore,
            settingsStore: settingsStore,
            pinnedFolderStore: pinnedFolderStore,
            folderCoverStore: folderCoverStore,
            shelfStore: shelfStore,
            keptAppStore: keptAppStore,
            runningApplicationStore: runningApplicationStore,
            appMembershipController: appMembershipController,
            displayTopologyStore: displayTopologyStore
        )
        panelCoordinator = coordinator
        runtime.onToggleDrawer = { [weak coordinator] in coordinator?.toggleDrawer() }
        runtime.onToggleLauncher = { [weak self] in self?.launcherPanel.toggle() }
        runtime.onToggleControlCenter = { [weak self] in self?.controlCenterPanel.toggle() }
        runtime.onToggleKeepAwake = {
            let engine = QuickToggleEngine.shared
            engine.setKeepAwake(!engine.keepAwakeOn)
            return engine.keepAwakeOn
        }
        runtime.isKeepAwakeOn = { QuickToggleEngine.shared.keepAwakeOn }
        // Menu height slider ↔ every bar's grip-drag transaction. Weak: the orchestrator is
        // dropped on permission loss.
        settingsCoordinator.taskbarHeightSessionHandler = { [weak coordinator] editing in
            coordinator?.setSettingsHeightSessionActive(editing)
        }
        settingsCoordinator.taskbarHeightUpdateHandler = { [weak coordinator] in
            coordinator?.commitSettingsPanelHeight()
        }
        coordinator.onAddFolder = { [weak self] in self?.presentAddPinnedFolderPanel() }
        // 右键任务条 / 胶囊弹钨极菜单。走到这里说明已授权且不是临时副本，
        // 状态栏菜单必然已经建好（`applicationDidFinishLaunching` 的非临时分支），
        // 不存在"凭空造出一个状态栏图标"的问题。
        coordinator.onRequestTaskbarMenu = { [weak self] event, view in
            self?.statusMenuController.popUpFromTaskbar(with: event, in: view)
        }
        coordinator.start()
        let windowLiftAvoidanceController = WindowLiftAvoidanceController(host: coordinator)
        self.windowLiftAvoidanceController = windowLiftAvoidanceController
        // 避让默认关，起步先把持久化的开关状态灌进去；start() 自己认这个标志位，
        // 没勾选时它直接空转返回，两个定时器（空闲 1 Hz / 会话期 5 Hz 的全局扫描，
        // 以及 20 Hz tracked probe）都不会起来。
        windowLiftAvoidanceController.setEnabledBySetting(settingsStore.windowLiftEnabled)
        windowLiftAvoidanceController.start()
        // sink 用闭包参数里的新值：@Published 在赋值完成前发布，此刻回读 store 是旧值。
        // 走 self?.windowLiftAvoidanceController 而不是强捕获控制器——权限恢复路径会把它置 nil。
        windowLiftSettingSubscription = settingsStore.$windowLiftEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.windowLiftAvoidanceController?.setEnabledBySetting(enabled)
            }
        // 最常用文件的计数账本：目录监视 + 激活重采样都挂在任务条运行期。
        DocumentUsageStore.shared.start()
        TrashStateStore.shared.setEnabled(settingsStore.showTrash)
        TrashStateStore.shared.start(revealOpenedWindow: TrashStateStore.revealTrashWindow(runtime: runtime))
        trashSettingSubscription = settingsStore.$showTrash
            .removeDuplicates()
            .sink { enabled in TrashStateStore.shared.setEnabled(enabled) }
        // 反转滚轮同款接线。sink 用闭包参数里的新值，不回读 store（@Published 在赋值前发布）。
        applyScrollReverser(enabled: settingsStore.scrollReverserEnabled)
        scrollReverserSettingSubscription = settingsStore.$scrollReverserEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.applyScrollReverser(enabled: enabled)
            }
        badgeStore.start()
        // 任务条真的起来了才谈得上「建议怎么配」。放在这里而不是启动那一刻，是因为
        // 用户得先看见任务条长什么样，那句「它俩都在屏幕底边会互相遮挡」才有所指。
        presentWelcomeGuideIfNeeded()
        nativeDockPreferencesService.reapplyDesiredIfNeeded()
        // 探针结论（2026-07-06,阶段0探针3）：访达窗口 AX 属性表虽列有 AXDocument 但恒无值
        // （kAXErrorNoValue），AXProxy/AXTitleUIElement 也只有文件夹名无路径——「拖任务条访达
        // 窗口图标固定文件夹」不可行,已按预案砍掉,拖入固定区只走真实文件 URL（系统拖放）。
    }

    /// Settings › Restore Dock: show the system Dock again and stop re-hiding it at launch.
    func restoreNativeDock() {
        if !nativeDockPreferencesService.restoreOriginal(forget: true) {
            try? nativeDockPreferencesService.apply(delay: AppSettingsStore.neverHideDelay)
        }
        settingsStore.setNativeDockAutoHideDelay(AppSettingsStore.neverHideDelay)
    }

    /// 文件夹 chip / 中转格右键的「添加固定文件夹…」入口。
    /// accessory app 必须先 activate，否则 NSOpenPanel 不上前台。
    func presentAddPinnedFolderPanel() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Pin")
        panel.message = String(localized: "Choose a folder to pin to the taskbar")
        if panel.runModal() == .OK {
            for url in panel.urls { pinnedFolderStore.add(url.path) }
        }
    }

    /// 设置窗口的存在前提是「任务条正常在跑」。
    ///
    /// 临时副本、还没授权、以及权限丢失后的恢复态，此刻用户唯一该做的事都是处理引导窗口——
    /// 这时再开一个完整设置面，只会盖在引导窗口上，而且里面的开关全都作用于一条根本没起来的
    /// 任务条（少数派用户 2026-08-03 反馈的正是这个自相矛盾的画面）。所以一律改为把引导窗口置前。
    @objc func openSettings(_ sender: Any?) {
        guard !installLocation.isTransient,
              hasStartedApp,
              // Dev skip: without a grant the guide would hijack Settings (where the theme /
              // appearance UI lives) — the whole point of running permission-free.
              permissionService.hasRequiredPermissions() || skipsPermissionGate else {
            showPermissionWindow()
            return
        }
        settingsWindowController.present()
    }

    /// Settings opened on a given tab (status menu › Layout › Layout Settings…).
    func openSettings(selecting tab: SettingsTab) {
        settingsWindowController.selectBeforePresenting(tab)
        openSettings(nil)
    }

    func exportDebugSnapshot() {
        runtime.exportDebugSnapshot()
    }

    func showDebugConsole() {
        if let existing = debugWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "任务条调试台"
        window.contentView = NSHostingView(
            rootView: DebugConsoleView()
                .environmentObject(runtime)
                .environmentObject(runtime.debugState)
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        debugWindow = window
    }

    /// 主线程卡顿探针：只在 `DOCK_HOVER_TRACE=1` 时才装（`HoverTrace.isEnabled` 是常量，
    /// 关闭时这个计时器根本不创建，日常一分钱开销都没有）。
    ///
    /// 8ms 一次、跑在 `.common`——**必须是 `.common`**，否则菜单/拖拽期间它自己先停了，
    /// 而那正是最想量的时段。
    private func startMainLoopStallProbeIfTracing() {
        guard HoverTrace.isEnabled else { return }
        // 计时器回调是 Sendable 闭包，不能直接改捕获的 var；装进一个只在主线程用的盒子。
        let clock = StallProbeClock(expected: CACurrentMediaTime() + 0.008)
        let timer = Timer(timeInterval: 0.008, repeats: true) { _ in
            let now = CACurrentMediaTime()
            HoverTrace.mainLoopStall(lateMs: (now - clock.expected) * 1000)
            clock.expected = now + 0.008
        }
        RunLoop.main.add(timer, forMode: .common)
        mainLoopStallProbe = timer
    }

}

// MARK: - 权限状态机的副作用执行

extension AppDelegate: PermissionEffectHandler {
    func startApp() {
        guard !hasStartedApp else { return }
        hasStartedApp = true
        startTaskbarRuntime()
        if isLimitedMode { startLimitedModePolling() }
    }

    /// Checks for the grant every 3 s (a cheap trust query) and relaunches into full mode as soon as it lands.
    private func startLimitedModePolling() {
        limitedModeTimer?.invalidate()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.permissionService.hasRequiredPermissions() else { return }
                self.limitedModeTimer?.invalidate()
                self.limitedModeTimer = nil
                self.relaunchIntoFullMode()
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        limitedModeTimer = timer
    }

    private func relaunchIntoFullMode() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        // The new instance terminates the other instances itself at launch; quit as a fallback if it failed to start.
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, error in
            if error != nil { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { NSApp.terminate(nil) }
        }
    }

    /// Status-menu entry in limited mode: registers the app in the Accessibility list (the menu item itself opens the pane).
    private func requestAccessibilityFromMenu() {
        permissionService.requestAccessibilityPermission()
    }

    func setActivationPolicy(_ policy: PermissionActivationPolicy) {
        switch policy {
        case .accessory:
            NSApp.setActivationPolicy(.accessory)
        case .regular:
            // 没有权限时任务条不会创建任何面板，保持 accessory 会让用户只能看到一个
            // 不一定明显的状态栏图标；先用普通应用策略把引导窗口带到前台。
            NSApp.setActivationPolicy(.regular)
        }
    }

    func showGuideWindow() {
        guard !skipsPermissionGate else { return }
        showPermissionWindow()
    }
    func updateGuideWindow() { resizePermissionWindowToFit() }
    func closeGuideWindow() { closePermissionWindow() }

    func openAccessibilitySettings() {
        guard let url = AccessibilitySettingsLink.url else { return }
        NSWorkspace.shared.open(url)
    }

    func openApplicationsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
    }

    func releaseHotKey() { edgeToggleHotKey?.stop() }

    func registerHotKey() { _ = edgeToggleHotKey?.start() }

    /// 反转滚轮的唯一开合入口：开 = 建 monitor + 起 tap，关 = 拆干净。
    /// `settingEnabled` 由调用方传（订阅的新值或起步时的 store 值），不在这里回读 store——
    /// @Published 在赋值完成前发布，sink 里回读拿到的是旧值（仓库惯例）。
    private func applyScrollReverser(enabled settingEnabled: Bool) {
        let enabled = ScrollReverserDecision.isEnabled(
            settingEnabled: settingEnabled,
            environment: ProcessInfo.processInfo.environment
        )
        if enabled {
            guard scrollReverserMonitor == nil else { return }
            let monitor = ScrollReverserMonitor()
            scrollReverserMonitor = monitor
            monitor.start()
        } else {
            scrollReverserMonitor?.stop()
            scrollReverserMonitor = nil
        }
    }

    func terminateSelf() { NSApp.terminate(nil) }

    // MARK: 运行期恢复

    /// 5 秒一采样。防抖判定在纯 `PermissionLossDetector` 里，这里只负责喂数据。
    /// 注意这**不是**窗口快照的保护机制——那个由 `WindowLiftAvoidanceController`
    /// 自己在轮询里自检；有会话/待还原状态时仍是 0.2 秒，空闲无快照时才降到 1 秒。
    func startWatchdog() {
        // Dev skip / limited mode: no 5s AX sampling → no trustVerdict events → no revocation episode
        // can suspend the panels we just started without a grant.
        guard !skipsPermissionGate else { return }
        stopWatchdog()
        permissionWatchdogGate.start()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.schedulePermissionProbe()
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        permissionWatchdogTimer = timer
    }

    func stopWatchdog() {
        permissionWatchdogTimer?.invalidate()
        permissionWatchdogTimer = nil
        permissionWatchdogGate.stop()
    }

    private func schedulePermissionProbe() {
        guard let generation = permissionWatchdogGate.beginProbe() else { return }
        let permissionService = permissionService
        permissionProbeQueue.async { [weak self] in
            let trusted = permissionService.hasRequiredPermissions()
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.permissionWatchdogGate.completeProbe(generation: generation) else { return }
                self.cachedAccessibilityTrusted = trusted
                self.permissionCoordinator?.sampleTrust(trusted)
            }
        }
    }

    func freezeLiftSnapshots() {
        windowLiftAvoidanceController?.beginPermissionUncertainty()
    }

    func unfreezeLiftSnapshots() {
        windowLiftAvoidanceController?.endPermissionUncertainty()
    }

    func suspendPanelsAndStores() {
        guard !skipsPermissionGate else { return }
        trashSettingSubscription = nil
        TrashStateStore.shared.stop()
        // 设置窗口也要一起收：权限一丢任务条整条被拆掉，留着一扇改任务条外观的窗
        // 既没有意义，也会挡住紧接着弹出的恢复引导。
        settingsWindowController.close()
        // 欢迎引导同理，而且更刺眼：任务条已经没了，屏幕上还留着一扇教你怎么配置它的窗。
        closeWelcomeWindow()
        messagingAutoRegisterSubscription?.cancel()
        messagingAutoRegisterSubscription = nil
        badgeContextSubscription?.cancel()
        badgeContextSubscription = nil
        runtime.onToggleDrawer = nil
        runtime.onToggleLauncher = nil
        runtime.onToggleControlCenter = nil
        runtime.onToggleKeepAwake = nil
        runtime.isKeepAwakeOn = nil
        pinchSubscription?.cancel()
        pinchSubscription = nil
        pinchMonitor?.stop()
        pinchMonitor = nil
        shortcutSubscription?.cancel()
        shortcutSubscription = nil
        shortcutService.tearDown()
        hyperkeyService.tearDown()
        KeyGuardService.shared.tearDown()
        NotificationMoveService.shared.tearDown()
        TilingEngine.shared.stop()
        radialDialPanel.tearDown()
        scrollReverserSettingSubscription?.cancel()
        scrollReverserSettingSubscription = nil
        scrollReverserMonitor?.stop()
        scrollReverserMonitor = nil
        DocumentUsageStore.shared.stop()
        panelCoordinator?.suspendAndRelease()
        panelCoordinator = nil
        badgeStore.stop()
        runtime.stop()
        runningApplicationStore.stop()
    }

    /// 权限刚回来，AX 才写得动窗口——整条恢复链把还原推迟到这一刻就是为了这个。
    func restoreLiftedWindows(episode: UInt64) async {
        await windowLiftAvoidanceController?.restoreAndStopForPermissionRecovery()
        windowLiftAvoidanceController = nil
    }

    func launchNewInstance(episode: UInt64) async -> Result<Void, Error> {
        let configuration = NSWorkspace.OpenConfiguration()
        // 这里制造第二个实例是**故意**的：新实例的 terminateOtherInstances() 会来收掉本实例。
        // 和「build_and_run.sh 里禁用 open -n」那条护栏不是一回事——那条禁的是构建脚本
        // 不等旧进程退出就凭空多开一份，制造出两条一模一样的任务条。
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        let url = Bundle.main.bundleURL

        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                // 这个 completion 在并发队列上回调。这里只 resume，
                // 后续动状态机 / 热键 / 界面的活儿都在协调器的 @MainActor Task 里做。
                if let error {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success(()))
                }
            }
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    /// 用户直接叉掉欢迎引导，等同「以后再说」——**照样要记成已看过**，
    /// 否则叉一次、下次启动又弹一次。
    ///
    /// 程序主动关窗那条路（`closeWelcomeWindow()`）不会走到这里：它先把 `welcomeWindow`
    /// 置 nil、把 delegate 摘掉，然后才 `close()`。所以这个回调只代表「用户自己关的」，
    /// 不会和 `applyWelcomeSelection(_:)` / `dismissWelcomeGuide()` 重复标记。
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === welcomeWindow else { return }
        welcomeWindow = nil
        window.delegate = nil
        settingsStore.setHasSeenWelcome(true)
    }
}

/// 主循环卡顿探针的时钟（只在主线程的定时器回调里读写；`@unchecked` 因为 Timer 闭包要求 Sendable）。
private final class StallProbeClock: @unchecked Sendable {
    var expected: CFTimeInterval
    init(expected: CFTimeInterval) { self.expected = expected }
}

private extension AppearanceMode {
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}
