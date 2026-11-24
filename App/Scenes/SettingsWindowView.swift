import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsWindowView: View {
    // The window's default width (it resizes freely above `minWindowWidth`). The number lives in
    // `SettingsMetrics` because a pair's half is arithmetic on it (`cardContentWidth`).
    static let contentWidth: CGFloat = SettingsMetrics.windowWidth

    /// 公开仓库主页。**只给「求 Star」用**——用户可见的「去下载」永远指向官网
    /// （2026-08-13 起 GitHub release 页不再附安装包，指过去是个空页面），
    /// 别顺手把下载入口也改到 GitHub 来。
    static let repositoryURL = URL(string: "https://github.com/wakilibaraka/KatiKati")!

    @ObservedObject var store: AppSettingsStore
    @ObservedObject var coordinator: SettingsCoordinator
    @ObservedObject var tabState: SettingsTabState
    /// 「通用」页那颗「重新打开新手引导」按钮的动作。**不给默认值**：这里没有任何测试
    /// 会检查 SwiftUI 调用点，给了默认值就等于让"漏传"编译通过（AGENTS.md 的 no-default 铁律）。
    let onShowWelcomeGuide: () -> Void
    /// Slice B: the Dock-pin importer, injected by `SettingsWindowController` and handed to the Dock Items
    /// page through the environment (that pane also compiles into the test target).
    let onImportDockPins: (() -> Int)?
    let dockProfileActions: DockProfileActions?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = SettingsIridescentPalette.resolve(style: store.themeMaterial, colorScheme: colorScheme)
        let isDark = colorScheme == .dark

        ZStack(alignment: .top) {
            // Ambient iridescent mesh backdrop reactive to the active Dock theme
            ZStack {
                RadialGradient(
                    colors: [palette.primaryAccent.opacity(isDark ? 0.14 : 0.10), .clear],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 520
                )
                RadialGradient(
                    colors: [palette.secondaryAccent.opacity(isDark ? 0.12 : 0.08), .clear],
                    center: .topTrailing,
                    startRadius: 40,
                    endRadius: 480
                )
                RadialGradient(
                    colors: [palette.tertiaryAccent.opacity(isDark ? 0.10 : 0.07), .clear],
                    center: .bottom,
                    startRadius: 60,
                    endRadius: 540
                )
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            SettingsShell(
                store: store,
                coordinator: coordinator,
                tabState: tabState,
                onShowWelcomeGuide: onShowWelcomeGuide
            )
            .ignoresSafeArea(edges: .top)
        }
        .environment(\.dockThemeStyle, store.themeMaterial)
        // DW-6: slider tracks and previews inside Settings fill from the same resolved accent stops as the bar.
        .environment(\.dockAccent, DockAccentEnvironment.resolve(spec: store.dockAccent,
                                                                 wallpaperAccent: WallpaperEngine.shared.accentHexes))
        .environment(\.importDockPins, onImportDockPins)
        .environment(\.dockProfileActions, dockProfileActions)
        .frame(minWidth: SettingsMetrics.minWindowWidth, minHeight: SettingsMetrics.minWindowHeight)
    }
}

/// A page as the shell holds it: every pane plus the padding the scroll view owes it.
struct SettingsPageColumn: View {
    @ObservedObject var store: AppSettingsStore
    @ObservedObject var coordinator: SettingsCoordinator
    @ObservedObject var tabState: SettingsTabState
    let onShowWelcomeGuide: () -> Void

    var body: some View {
        SettingsWindowContent(
            store: store,
            coordinator: coordinator,
            tabState: tabState,
            onShowWelcomeGuide: onShowWelcomeGuide
        )
        .padding(.top, 8)
        .padding(.bottom, 20)
    }
}

struct SettingsWindowContent: View {
    @ObservedObject var store: AppSettingsStore
    @ObservedObject var coordinator: SettingsCoordinator
    @ObservedObject var tabState: SettingsTabState
    let onShowWelcomeGuide: () -> Void

    @State private var presentedAlert: SettingsAlert?
    @AppStorage(SettingsGlowSchedule.defaultsKey) private var glowSchedule = SettingsGlowSchedule.clock.rawValue
    @AppStorage(StartupUIPolicy.launchHiddenKey) private var launchHidden = false
    @AppStorage(StartupUIPolicy.hideDockIconKey) private var hideDockIcon = false
    @AppStorage(MenuBarStatModel.masterEnabledKey) private var menuBarEnabled = false

    var body: some View {
        // The page margin lives here, once for all ten pages; every pane body renders cards only,
        // so no page can invent an inset of its own (`Docs/SETTINGS.md` rule 1).
        SettingsPane {
            switch tabState.selected {
            case .general: generalPane
            case .menuBar: menuBarPane
            case .appearance: SettingsAppearancePane(store: store)
            case .wallpaper: SettingsWallpaperPane(store: store, tabState: tabState)
            case .dockItems:
                SettingsLayoutPane(store: store, mode: .widgets)
                    .background(SettingsPageHeightProbe(tab: .dockItems))
            case .appIcons:
                AppIconsSettingsBlock(store: store)
            case .shelf:
                ShelfSettingsBlock(store: store)
                    .background(SettingsPageHeightProbe(tab: .shelf))
            case .barWidgets:
                SettingsLayoutPane(store: store, mode: .barWidgets)
                WidgetLookSettingsBlock(store: store)
            case .widgets:
                WidgetWingsSettingsBlock(store: store)
            case .desktop:
                DesktopSettingsBlock(store: store)
            case .weather: weatherPane
            case .music: SettingsMusicPane(store: store, tabState: tabState)
            case .notch: notchPane
            case .notifications: SettingsNotificationsPane(store: store)
            case .edgeBars: SettingsLayoutPane(store: store, mode: .edgeBars)
            case .tiling: SettingsTilingPane(store: store)
            case .windowManagement: windowManagementPane
            case .missionControl: SettingsMissionControlPane(spaces: Self.missionControlSpaces())
            case .launcher: launcherPane
            case .commandBar: commandBarPane
            case .controlCenter: controlCenterPane
            case .shortcuts: SettingsLayoutPane(store: store, mode: .shortcuts)
            case .keyboard: SettingsLayoutPane(store: store, mode: .keyboard)
            case .keyVisualizer: SettingsLayoutPane(store: store, mode: .visualizer)
            case .mouse: SettingsLayoutPane(store: store, mode: .mouse)
            case .mouseGestures: SettingsLayoutPane(store: store, mode: .gestures)
            case .quitApps: SettingsLayoutPane(store: store, mode: .quitApps)
            case .radialDial:
                SettingsLayoutPane(store: store, mode: .radialDial)
                    .background(SettingsPageHeightProbe(tab: .radialDial))
            case .aiTracking: aiTrackingPane
            case .downloads: TorrentSettingsBlock()
            case .clipboard: ClipboardSettingsPane(store: store)
            case .tools: toolsPane
            case .advanced: advancedPane
            }
        }
        .environment(\.dockThemeStyle, store.themeMaterial)
        // **不许写死宽度**：外面套着 ScrollView，刚性宽度在可视区变窄时会被居中 = 整页平移。
        // 弹性宽度下左边缘恒在 padding 处，最多重排换行。测高探针给的仍是 contentWidth 的提案。
        .alert(item: $presentedAlert) { alert in
            guard let actionTitle = alert.actionTitle, let action = alert.action else {
                return Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            return Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                primaryButton: .default(Text(actionTitle), action: action),
                secondaryButton: .cancel(Text("Later"))
            )
        }
    }

    // 分区标题行随分页取消（窗口标题承担）。页体全部是**本根视图**的计算属性——
    // 草稿 @State（presentedAlert / 订阅邮箱 / 授权码）必须留在根上，
    // 下放进页级子视图 = 切页即清空（`Docs/SETTINGS.md` 规则 1 附注同源问题）。反馈的四份草稿在 `feedbackDraft`。
    /// Every pane renders through `SettingsCard`/`SettingsRow` (`Docs/SETTINGS.md` rules 2 and 3).
    /// It used to branch on macOS 13: that path was the system grouped `Form` and the macOS 12 path
    /// hand-built its own boxes, so the same page looked different on each release and the two
    /// drifted apart (the macOS 12 copy of one row had already fixed a duplicate label the other
    /// had not). One container now serves both.
    ///
    /// 「通用」页: one box — label leading, control trailing — with the setup-guide entry under
    /// it. Rows carry no grey note; the one disclosure this page owes (scroll reversal) sits
    /// behind that row's help button.
    @ViewBuilder
    private var generalPane: some View {
        SettingsCard(Text("Startup")) {
            SettingsToggleRow(
                Text("Launch at login"),
                isOn: Binding(
                    get: { coordinator.launchAtLoginState == .on },
                    set: { enable in
                        // A denied registration is a state, not a dead row (rule 7): the only
                        // path forward is System Settings › Login Items, so open it.
                        if case .failure = coordinator.setLaunchAtLogin(enable) {
                            coordinator.openLoginItemsSettings()
                        }
                    }
                ),
                note: Text("Open KatiKati when you sign in.")
            )
            SettingsDivider()
            SettingsRowPair(
                left: { SettingsToggleRow(Text("Launch hidden at login"), isOn: $launchHidden) },
                right: {
                    SettingsToggleRow(Text("Hide Dock icon"), isOn: Binding(
                        get: { hideDockIcon },
                        set: {
                            hideDockIcon = $0
                            (NSApp.delegate as? AppDelegate)?.applyDockIconPreference()
                        }
                    ))
                }
            )
            SettingsDivider()
            autoUpdateToggle
        }
        SettingsCard {
            languagePicker
            SettingsDivider()
            // Plain stacks, not `LabeledContent`: that aligns on the text baseline, which an
            // AppKit-backed control lacks — the recorder drops below its own label.
            SettingsRow(Text("Appearance")) {
                appearanceCards
            }
            SettingsDivider()
            SettingsPickerRow(Text("Window Glow"), selection: $glowSchedule, note: Text("The colour wash behind Settings. It follows the time of day unless you pick a fixed time.")) {
                ForEach(SettingsGlowSchedule.allCases, id: \.rawValue) { $0.title.tag($0.rawValue) }
            }
            SettingsDivider()
            SettingsRow(Text("Show/hide taskbar shortcut")) {
                hotKeyControls
            }
            SettingsDivider()
            SettingsButtonRow(Text("Reset All Settings"), note: Text("Restores every default and restarts KatiKati.")) {
                presentedAlert = SettingsAlert(
                    title: String(localized: "Reset All Settings"),
                    message: String(localized: "Every setting goes back to its default and KatiKati restarts."),
                    actionTitle: String(localized: "Reset"),
                    action: {
                        if let domain = Bundle.main.bundleIdentifier {
                            UserDefaults.standard.removePersistentDomain(forName: domain)
                        }
                        Self.relaunch()
                    }
                )
            }
        }
        PermissionsSettingsBlock()
        SettingsCard(Text("About")) {
            aboutVersionRow
            SettingsDivider()
            diagnosticsRow
        }
        welcomeGuideButton
        BackupSettingsBlock()
        WebDAVSettingsCard()
    }

    @ViewBuilder
    private var menuBarPane: some View {
        MenuBarHubSettingsBlock()
        SettingsCard(Text("Menu Bar")) {
            SettingsToggleRow(
                Text("Menu bar icon"),
                isOn: $menuBarEnabled,
                note: Text("Keep a shortcut to these settings in the menu bar.")
            )
            SettingsDivider()
            ForEach(MenuBarMetric.allCases) { metric in
                metricRow(metric)
                SettingsDivider()
            }
            // DiskView's item (2026-10-26): every mounted drive with its capacity bar, rather than
            // one aggregate reading — so it is a row here, not another `MenuBarMetric`.
            SettingsToggleRow(Text("Drives"), isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: DriveMenuBarItem.enabledKey) },
                set: { UserDefaults.standard.set($0, forKey: DriveMenuBarItem.enabledKey) }
            ), note: Text("Free space of every mounted drive in the menu bar, one bar each."))
        }
    }

    /// One menu-bar metric: what it shows and whether it shows — both on the row, so the
    /// state is never implied (`Docs/SETTINGS.md` rule 7).
    private func metricRow(_ metric: MenuBarMetric) -> some View {
        MenuBarMetricRow(metric: metric)
    }

    private var aiTrackingPane: some View {
        AITrackingSettingsBlock()
    }

    // 「高级」= 需要额外能力、默认就对、基本不用碰的开关。单独一页不是为了藏，
    // 而是让常用页只留日常会调的东西；真想拒绝这个能力的人找得到（owner 2026-08-09，
    // 2026-08-24 分页时 owner 确认保留「高级」这一页）。
    //
    // Two sections, each with a header (Phase 12 A6–A7): the full-screen prediction row was a
    // headerless card of one row above these, which a page owes a title it cannot name. It is the
    // first row of **Behaviour** now — the same content, one section fewer.
    @ViewBuilder
    private var advancedPane: some View {
        BehaviourSettingsBlock(store: store)
    }

    /// 「窗口管理」页: window chips and the two window behaviours (tiling has its own page now).
    @ViewBuilder
    private var windowManagementPane: some View {
        WindowManagementSettingsPane(store: store)
            .background(SettingsPageHeightProbe(tab: .windowManagement))
    }

    /// 「天气」页: the weather widget's units, layout and warning thresholds.
    private var weatherPane: some View {
        SettingsCard(Text("Weather")) {
            WeatherSettingsBlock()
        }
    }

    /// 「启动器」页: the launcher appearance/apps and the launcher's own rows (`LauncherSettingsBlock`).
    /// Control Center now lives on its own dedicated tab (`SettingsTab.controlCenter`),
    /// and the command bar has its own page (`SettingsTab.commandBar`).
    private var launcherPane: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            SettingsLayoutPane(store: store, mode: .launcher)
            LauncherSettingsBlock()
        }
    }

    /// 「命令栏」页: the command bar's own rows (`LauncherSettingsBlock` keeps the launcher rows).
    private var commandBarPane: some View {
        CommandBarSettingsBlock(tabState: tabState)
    }

    /// 「控制中心」页: dedicated page for Control Center placement, size, widgets, and quick settings.
    @ViewBuilder
    private var controlCenterPane: some View {
        SettingsLayoutPane(store: store, mode: .controlCenter)
    }

    /// 「工具」页: commands and snippets, in the slot the About page left. Clipboard has its own page
    /// since MC-1.
    private var toolsPane: some View {
        UtilitySettingsBlock(store: store)
    }

    /// 「刘海」页: the Live Island block plus the helpers that surface in the notch.
    @ViewBuilder
    private var notchPane: some View {
        LiveIslandSettingsBlock(store: store)
        NotchHelpersSettingsBlock()
    }

    /// Copies `DiagnosticReport` to the clipboard so a user can paste it into a GitHub issue.
    /// Nothing is sent anywhere.
    private var diagnosticsRow: some View {
        SettingsRow(Text("Diagnostic Info")) {
            Button("Copy") {
                let report = DiagnosticReport.collect(appVersion: coordinator.versionTitle)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report.text, forType: .string)
                Self.presentCopiedDiagnostics(report.text)
            }
            .buttonStyle(SettingsGelButtonStyle())
        }
    }

    /// Shows what was just copied, so the user sees exactly what they are about to paste.
    /// An `NSAlert` sheet rather than `SettingsAlert`: a SwiftUI alert cannot hold a scrolling
    /// text box, and the report as a plain message makes the alert a screen tall.
    private static func presentCopiedDiagnostics(_ text: String) {
        // The scrollable-text-view factory sizes the document to its content and starts at the
        // top; a hand-built NSTextView in a scroll view opens scrolled one line down.
        let scrollView = NSTextView.scrollableTextView()
        scrollView.frame = NSRect(x: 0, y: 0, width: 420, height: 236)
        scrollView.borderType = .bezelBorder
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            textView.textContainerInset = NSSize(width: 6, height: 6)
            textView.string = text
        }

        let alert = NSAlert()
        alert.messageText = String(localized: "Diagnostic Info Copied")
        alert.informativeText = String(localized: "Paste it into a GitHub issue when you report a problem. It contains only the app, system and display details shown below — no personal information.")
        alert.accessoryView = scrollView
        alert.addButton(withTitle: String(localized: "OK"))
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    /// 界面语言（2026-08-24 加；Pass 2 加回「System」档——删键即跟随系统，机制本来就在，
    /// 见 `AppLanguageOption` 注释）。写**应用自己域**的 `AppleLanguages`，重启生效。
    /// 读现状必须走 `CFPreferencesCopyValue`（精确域）——`array(forKey:)` 和
    /// `CFPreferencesCopyAppValue` 都会继承全局域，分不清「没设过」和「显式设置」。
    /// **读取路径绝不许回写**（钉死语言的陷阱）。
    private var languagePicker: some View {
        SettingsPickerRow(
            Text("App language"),
            selection: Binding(
                get: { Self.currentLanguageChoice() },
                set: { applyLanguage($0) }
            ),
            note: Text("Applies the next time KatiKati starts.")
        ) {
            Text("System").tag(AppLanguagePickerChoice.system)
            ForEach(AppLanguageOption.allCases, id: \.self) { option in
                Text(option.displayName).tag(AppLanguagePickerChoice.option(option))
            }
        }
    }

    private static func currentLanguageChoice() -> AppLanguagePickerChoice {
        let bundleID = (Bundle.main.bundleIdentifier ?? "") as CFString
        // ⚠️ 必须 CopyValue + CurrentUser/AnyHost 精确读本域：CopyAppValue（和
        // `array(forKey:)`）会一路搜到全局域——那里永远有系统语言列表，于是「没选过」
        // 被误报成「选了系统那门语言」，System 档永远选不中（本机实测撞上）。
        let value = CFPreferencesCopyValue("AppleLanguages" as CFString, bundleID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String]
        return AppLanguagePickerChoice.current(
            appDomainValue: value,
            // 真正加载的那份 .lproj——比推断系统语言准。
            effectiveLocalization: Bundle.main.preferredLocalizations.first ?? "en"
        )
    }

    /// 选中的档**一律写键**；「System」删键（跟随系统）。只有下次启动界面语言真的会变时
    /// 才提示重启：什么都没变还要人重启是打扰。
    private func applyLanguage(_ choice: AppLanguagePickerChoice) {
        let changes = choice.changesLocalization(
            currentEffective: Bundle.main.preferredLocalizations.first ?? "en",
            systemPreferred: Locale.preferredLanguages
        )
        if let value = choice.appleLanguagesValue {
            UserDefaults.standard.set(value, forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        guard changes else { return }
        presentedAlert = SettingsAlert(
            title: String(localized: "Language"),
            message: String(localized: "The language change takes effect after KatiKati restarts."),
            actionTitle: String(localized: "Restart KatiKati"),
            action: { Self.relaunch() }
        )
    }

    /// 分离一个「睡半秒再 open」的壳进程后自退。新实例启动时旧的已退干净，
    /// `terminateOtherInstances()` 不会反杀谁。环境无需再清——本进程入口处
    /// `ProcessEnvironmentScrub.apply()` 已经清过，子进程继承的就是干净环境。
    private static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", Bundle.main.bundleURL.path]
        try? process.run()
        NSApp.terminate(nil)
    }

    /// 显隐任务条快捷键：录制框 + 自定义过才出现的「恢复默认」。行高恒定
    ///（录制态只换文案不换尺寸，按钮出现在同一行内），所以不用给
    /// `SettingsWindowController.sessionSubscriptions` 加 sink。
    @ViewBuilder
    private var hotKeyControls: some View {
        HStack(spacing: 10) {
            if store.edgeToggleShortcut != nil {
                Button("Reset to Default") { applyShortcut(nil) }
            }
            HotKeyRecorder(
                currentGlyphs: store.edgeToggleShortcut?.glyphs
                    ?? GlobalHotKeyShortcut.edgeAutoHideMode.displayGlyphs,
                onRecord: { applyShortcut($0) },
                onRejectKey: {
                    presentedAlert = SettingsAlert(
                        title: String(localized: "Can’t Use This Shortcut"),
                        message: String(localized: "This key can’t be used as the shortcut key.")
                    )
                }
            )
            .fixedSize()
        }
    }

    /// App-wide appearance (`AppearanceMode`). The third option is `System`, never `Auto`:
    /// macOS's Auto switches by time of day, this one follows whatever macOS is showing.
    private var appearanceCards: some View {
        AppearanceModeCards(selection: store.appearanceMode, onSelect: store.setAppearanceMode)
    }

    /// 全局反转鼠标滚轮。作用于整个系统而不只是任务条，所以放「通用」。
    /// 说明必须写清「只改写方向值、不记录不发送」——这是全项目唯一改写别人输入事件的功能。
    /// It sits behind the row’s ⓘ rather than under the toggle: this page shows no notes, and
    /// a hover tooltip is not reachable enough (it needs a still pointer and an active window).
    /// 重开首次引导（那扇写系统 Dock 推荐设置的窗）。2026-09-01 从状态栏菜单搬来
    /// （owner 拍板）：它是"打开另一个界面"的入口，不是随手切的开关。
    /// 放「通用」页分组框下面——框里是设置，它是入口。
    ///
    /// ⚠️ 闭包直通 `AppDelegate.showWelcomeWindow()`，**绝不能改成走
    /// `presentWelcomeGuideIfNeeded()`、也不能靠删 `hasSeenWelcome`**：那条决策函数对
    /// 「系统 Dock 已自动隐藏」的存量用户恰好会跳过并把键写回，而存量用户正是这个入口的全部受众。
    private var welcomeGuideButton: some View {
        Button("Show Setup Guide Again") { onShowWelcomeGuide() }
            .buttonStyle(SettingsGelButtonStyle())
    }

    private func applyShortcut(_ stored: StoredHotKeyShortcut?) {
        if case .failure(let error) = coordinator.applyEdgeToggleShortcut(stored) {
            presentedAlert = SettingsAlert(
                hotKeyError: error,
                attemptedGlyphs: stored?.glyphs ?? GlobalHotKeyShortcut.edgeAutoHideMode.displayGlyphs
            )
        }
    }

    private var aboutVersionRow: some View {
        SettingsRow(Text(coordinator.versionTitle ?? "")) {
            // Sparkle 自带结果界面（有新版 / 已是最新 / 查不到），所以这里不再接
            // `SettingsAlert`——原来那条「去官网手动下载」的提示随之删掉了。
            Button("Check for Updates…") {
                coordinator.checkForUpdates()
            }
            .buttonStyle(SettingsGelButtonStyle(prominent: true))
            .disabled(!coordinator.canCheckForUpdates)
        }
    }

    private var autoUpdateToggle: some View {
        // 自动检查默认是开的（`SUEnableAutomaticChecks`）。**必须给关的入口**：
        // 一个用户关不掉的后台定期联网检查，比多一个勾选项糟糕得多。
        // 真值在 Sparkle 那边，这里不做镜像。
        SettingsToggleRow(
            Text("Check for updates automatically"),
            isOn: Binding(
                get: { coordinator.automaticallyChecksForUpdates },
                set: { coordinator.automaticallyChecksForUpdates = $0 }
            )
        )
    }

    private func binding<Value>(
        get: @escaping () -> Value,
        set: @escaping (Value) -> Void
    ) -> Binding<Value> {
        Binding(get: get, set: set)
    }
}

/// The three `AppearanceMode` choices as plain cards: a symbol over the name, the chosen one
/// tinted and ringed in the accent colour.
private struct AppearanceModeCards: View {
    let selection: AppearanceMode
    let onSelect: (AppearanceMode) -> Void
    @Environment(\.dockThemeStyle) private var themeStyle
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredMode: AppearanceMode?

    var body: some View {
        let palette = SettingsIridescentPalette.resolve(style: themeStyle, colorScheme: colorScheme)
        HStack(spacing: 8) {
            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                let isSelected = mode == selection
                let isHovered = hoveredMode == mode
                Button { onSelect(mode) } label: {
                    VStack(spacing: 5) {
                        Image(systemName: Self.symbolName(for: mode))
                            .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? palette.primaryAccent : (isHovered ? Color.primary : Color.secondary))
                            .frame(height: 18)
                        Text(mode.displayName)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    }
                    .padding(.horizontal, 12)
                    .frame(minWidth: 78, minHeight: 54)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(
                                    isSelected
                                        ? AnyShapeStyle(palette.subtleSurfaceGradient)
                                        : AnyShapeStyle(Color.primary.opacity(isHovered ? 0.08 : 0.04))
                                )
                            if isSelected {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.24), .clear],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                            }
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(
                                isSelected
                                    ? AnyShapeStyle(palette.pillGradient)
                                    : AnyShapeStyle(Color.primary.opacity(isHovered ? 0.18 : 0.08)),
                                lineWidth: isSelected ? 1.75 : 1.0
                            )
                    )
                    .shadow(color: isSelected ? palette.glowColor : .clear, radius: 6, x: 0, y: 2)
                    .scaleEffect(isHovered ? 1.03 : 1.0)
                    .animation(.spring(response: 0.24, dampingFraction: 0.75), value: isHovered)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in hoveredMode = inside ? mode : (hoveredMode == mode ? nil : hoveredMode) }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private static func symbolName(for mode: AppearanceMode) -> String {
        switch mode {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

private struct SettingsAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    /// 可选的第二个按钮（如语言切换的「立即重启」）。为 nil 时只有「好」。
    let actionTitle: String?
    let action: (() -> Void)?

    init(title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    /// 改键失败 → 一句能行动的人话。拒绝理由逐条给（每条的下一步动作不同）；
    /// 注册失败只有一种真实成因（组合被别的应用独占注册）。
    init(hotKeyError: HotKeyChangeError, attemptedGlyphs: String) {
        switch hotKeyError {
        case .rejected(.missingPrimaryModifier):
            self.init(
                title: String(localized: "Can’t Use This Shortcut"),
                message: String(localized: "Use at least one of Command, Control or Option.")
            )
        case .rejected(.unreliableModifiers):
            self.init(
                title: String(localized: "Can’t Use This Shortcut"),
                message: String(localized: "Option alone or Option-Shift is unreliable on macOS 15.")
            )
        case .rejected(.reservedBySystem):
            self.init(
                title: String(localized: "Can’t Use This Shortcut"),
                message: String(localized: "This combination belongs to macOS (⌥⌘D shows/hides the Dock; Control-Option is VoiceOver’s).")
            )
        case .rejected(.forbiddenKey):
            self.init(
                title: String(localized: "Can’t Use This Shortcut"),
                message: String(localized: "Escape and Delete can’t be the key.")
            )
        case .registrationFailed:
            self.init(
                title: String(localized: "Couldn’t Register the Shortcut"),
                message: String(
                    format: String(localized: "%@ is already taken by another app. The previous shortcut stays active."),
                    attemptedGlyphs
                )
            )
        }
    }
}

// App-only half of `DiagnosticReport`: the pure struct is also compiled into the test target,
// which has neither the glass bridge nor the panels.
extension DiagnosticReport {
    /// Variants read back for the report; the Dock's own material has been seen at 2 and at 3.
    static let reportedVariants = 0 ... 6

    /// Main thread, from a user action only — the variant read-back builds throwaway windows,
    /// which must not happen inside a SwiftUI update.
    static func collect(appVersion: String?) -> DiagnosticReport {
        let workspace = NSWorkspace.shared
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return DiagnosticReport(
            appVersion: appVersion,
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            hardwareModel: hardwareModel(),
            language: Bundle.main.preferredLocalizations.first ?? "en",
            appearance: "\(isDark ? "dark" : "light") (\(NSApp.appearance == nil ? "follows system" : "fixed"))",
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
            displays: NSScreen.screens.map {
                "\(Int($0.frame.width))x\(Int($0.frame.height))@\(Int($0.backingScaleFactor))x"
            },
            glassPath: glassPath(),
            glassTint: UserDefaults.standard.object(forKey: "NSGlassTintAmount").map { "\($0)" },
            glassVariants: glassVariantReadings(),
            glassPanels: NSApp.windows
                .filter { $0 is DockLiquidGlassPanel && $0.isVisible }
                .map { window in
                    GlassReading(
                        label: "\(Int(window.frame.width))x\(Int(window.frame.height))",
                        reading: window.contentView?.layer.flatMap { TEDockGlassDescribeLayer($0) }
                    )
                }
        )
    }

    private static func glassPath() -> String {
        guard DockGlassPresentation.shouldAttemptTaskbarComposite else { return "frosted" }
        if let variant = DockGlassPresentation.activeSystemVariant { return "variant \(variant)" }
        return DockGlassPresentation.configuration.systemVariant == nil
            ? "swiftui clear (variant switched off)"
            : "swiftui clear (no variant selector)"
    }

    private static func glassVariantReadings() -> [GlassReading] {
        guard TEDockGlassSupportsSystemVariant() else { return [] }
        return reportedVariants.map { GlassReading(label: "\($0)", reading: TEDockGlassDescribeVariant($0)) }
    }

    private static func hardwareModel() -> String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}


/// Settings for the floating widget tiles (Phase 5e). Plain `@AppStorage`: the panel reads the same
/// keys every time it opens (layout) or live (palette, clock style).
struct CalendarLayoutPicker: View {
    @AppStorage(CalendarPanelLayout.storageKey) private var layout: CalendarPanelLayout = .ipad

    var body: some View {
        Picker("Widget Layout", selection: $layout) {
            Text("Tall").tag(CalendarPanelLayout.tall)
            Text("Mac").tag(CalendarPanelLayout.mac)
            Text("iPad").tag(CalendarPanelLayout.ipad)
        }
        .pickerStyle(.menu).labelsHidden()
        .onAppear { layout = WidgetPanelController.currentLayout() }
    }
}

struct CalendarPalettePicker: View {
    @AppStorage(TilePalette.storageKey) private var palette: TilePalette = .classic

    var body: some View {
        Picker("Widget Colors", selection: $palette) {
            Text("Classic").tag(TilePalette.classic)
            Text("Vivid").tag(TilePalette.vivid)
            Text("Pastel").tag(TilePalette.pastel)
            Text("Mono").tag(TilePalette.mono)
        }
        .pickerStyle(.menu).labelsHidden()
    }
}

struct CalendarClockStylePicker: View {
    @AppStorage(CalendarClockStyle.storageKey) private var style: CalendarClockStyle = .flip

    var body: some View {
        Picker("Clock Style", selection: $style) {
            Text("Flip clock").tag(CalendarClockStyle.flip)
            Text("Analog").tag(CalendarClockStyle.analog)
            Text("Date").tag(CalendarClockStyle.date)
        }
        .pickerStyle(.menu).labelsHidden()
    }
}

/// Phase 16f: glass/blur tiles in the widget pane (off = solid, the default). The row draws the
/// name and puts it on the control for VoiceOver (`WidgetLookSettingsBlock`) — a `labelsHidden`
/// toggle with no name of its own reads as an unnamed checkbox (measured live 2026-10-15).
struct GlassTilesToggle: View {
    @AppStorage(WidgetExtraPrefs.glassTilesKey) private var glassTiles = false

    var body: some View {
        Toggle(isOn: $glassTiles) { EmptyView() }
            .toggleStyle(.switch).labelsHidden()
    }
}

/// Weather widget settings (Phase 5g-G): units, animation, coexistence with the calendar stack and
/// the forecast-warning thresholds. All plain `@AppStorage` — the tiles read them live.
/// The style/animation rows moved here from the widget-look block when Weather got its own tab
/// (2026-10-20); the Weather tab wraps these rows in one card.
struct WeatherSettingsBlock: View {
    @AppStorage(WeatherUnits.temperatureKey) private var tempUnit: TemperatureUnit = .celsius
    @AppStorage(WeatherUnits.windKey) private var windUnit: WindSpeedUnit = .kmh
    /// PHN-4: water on its own unit, defaulting from the temperature unit until it is set.
    @AppStorage(WaterUnit.storageKey) private var waterUnitRaw: String = ""

    private var waterUnitSelection: Binding<WaterUnit> {
        Binding(
            get: { WaterUnit.resolved(raw: waterUnitRaw.isEmpty ? nil : waterUnitRaw, temperature: tempUnit) },
            set: { waterUnitRaw = $0.rawValue }
        )
    }
    @AppStorage(WeatherLayoutPreset.storageKey) private var weatherLayout: WeatherLayoutPreset = .fullScreen
    @AppStorage(WeatherHeroStyle.storageKey) private var heroStyle: WeatherHeroStyle = .scene
    @AppStorage("com.katikati.weather.chipPreset") private var weatherPresetRaw: String = WeatherChipPreset.modern.rawValue
    @AppStorage(WeatherPrefs.animationsKey) private var weatherAnimations = true
    @AppStorage(WeatherPrefs.onePageKey) private var weatherOnePage = true
    @State private var thresholds = WeatherPrefs.thresholds()
    @State private var carouselConfig = WeatherCarouselConfig.decode(UserDefaults.standard.data(forKey: WeatherCarouselConfig.defaultsKey)) ?? .default
    @State private var savedCities = UserDefaults.standard.data(forKey: SavedCities.storageKey)
        .flatMap { try? JSONDecoder().decode(SavedCities.self, from: $0) } ?? SavedCities()

    /// Every row is a shared variant, so a control's alignment follows its type instead of this
    /// block's opinion (`Docs/SETTINGS.md` rule 3).
    var body: some View {
        // Weather style and the animation switch, one line (rule 5): they left the Widgets tab
        // when Weather became a page of its own.
        SettingsRowPair(
            left: {
                SettingsRow(Text("Weather Style")) {
                    Picker("Weather Style", selection: $weatherPresetRaw) {
                        ForEach(WeatherChipPreset.pickerCases(current: WeatherChipPreset(rawValue: weatherPresetRaw) ?? .modern), id: \.rawValue) { preset in
                            Text(preset.title).tag(preset.rawValue)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
            },
            right: { SettingsToggleRow(Text("Weather Animations"), isOn: $weatherAnimations) }
        )
        SettingsDivider()
        // The four unit/layout pickers are two lines, not four (`Docs/SETTINGS.md` rule 5): the
        // thresholds below stay on their own lines, because a stepper needs the card's width.
        SettingsRowPair(
            left: {
                SettingsSegmentedRow(Text("Temperature Unit"), selection: $tempUnit) {
                    Text(verbatim: "°C").tag(TemperatureUnit.celsius)
                    Text(verbatim: "°F").tag(TemperatureUnit.fahrenheit)
                }
            },
            right: {
                SettingsSegmentedRow(Text("Wind Speed Unit"), selection: $windUnit) {
                    Text(verbatim: "km/h").tag(WindSpeedUnit.kmh)
                    Text(verbatim: "mph").tag(WindSpeedUnit.mph)
                    Text(verbatim: "m/s").tag(WindSpeedUnit.ms)
                }
            }
        )
        SettingsDivider()
        SettingsSegmentedRow(Text("Water Unit"), selection: waterUnitSelection) {
            Text(verbatim: "ml").tag(WaterUnit.millilitres)
            Text(verbatim: "oz").tag(WaterUnit.ounces)
        }
        SettingsDivider()
        SettingsRowPair(
            left: {
                SettingsSegmentedRow(Text("Weather Layout"), selection: $weatherLayout) {
                    Text("Glance").tag(WeatherLayoutPreset.fullScreen)
                    Text("Overview").tag(WeatherLayoutPreset.glance)
                    Text("Classic").tag(WeatherLayoutPreset.classic)
                }
            },
            right: {
                SettingsSegmentedRow(Text("Hero Style"), selection: $heroStyle) {
                    Text("Scene").tag(WeatherHeroStyle.scene)
                    Text("Classic").tag(WeatherHeroStyle.classic)
                }
            }
        )
        SettingsDivider()
        SettingsToggleRow(Text("Show Overview on one page"), isOn: $weatherOnePage)
        SettingsDivider()
        SettingsRowPair(
            left: {
                SettingsRow(Text("Carousel Page 2")) {
                    Picker("Carousel Page 2", selection: carouselSlotBinding(\.page2)) {
                        ForEach(WeatherCarouselSlotMode.allCases) { mode in
                            Text(verbatim: mode.title).tag(mode)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
            },
            right: {
                SettingsRow(Text("Carousel Page 3")) {
                    Picker("Carousel Page 3", selection: carouselSlotBinding(\.page3)) {
                        ForEach(WeatherCarouselSlotMode.allCases) { mode in
                            Text(verbatim: mode.title).tag(mode)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
            }
        )
        SettingsDivider()
        SettingsRow(Text("Pinned Weather Locations (Max 3)")) {
            HStack(spacing: 6) {
                if savedCities.cities.isEmpty {
                    Text("Add cities in Weather panel").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(savedCities.cities) { city in
                        let token = WeatherLocationSelection.city(city.id).token
                        let selected = carouselConfig.pinnedLocationTokens.contains(token)
                        Button {
                            var next = carouselConfig.pinnedLocationTokens
                            if let idx = next.firstIndex(of: token) {
                                next.remove(at: idx)
                            } else if next.count < WeatherCarouselConfig.maxPinnedLocations {
                                next.append(token)
                            }
                            carouselConfig.pinnedLocationTokens = WeatherCarouselConfig.normalizedTokens(next)
                            persistCarouselConfig()
                        } label: {
                            Text(verbatim: city.name)
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(selected ? Color.accentColor.opacity(0.24) : Color.primary.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        // "Weather Animations" moved to the Widget Appearance card (2026-10-15), where the other
        // widget-animation row already lives and where it shares a line instead of owning one.
        SettingsDivider()
        SettingsRowPair(
            left: {
                SettingsStepperRow(
                    Text("Heat Warning (Feels Like)"),
                    value: binding(\.heatFeelsLikeC),
                    in: 25...50,
                    step: 1,
                    readout: "\(Int(thresholds.heatFeelsLikeC))°C"
                )
            },
            right: {
                SettingsStepperRow(
                    Text("Wind Warning"),
                    value: binding(\.windKmh),
                    in: 20...120,
                    step: 5,
                    readout: "\(Int(thresholds.windKmh)) km/h"
                )
            }
        )
        SettingsDivider()
        SettingsStepperRow(
            Text("Snow Warning"),
            value: binding(\.snowCmPerDay),
            in: 1...30,
            step: 1,
            readout: "\(Int(thresholds.snowCmPerDay)) cm"
        )
    }

    private func binding(_ key: WritableKeyPath<WeatherThresholds, Double>) -> Binding<Double> {
        Binding(get: { thresholds[keyPath: key] }, set: { value in
            thresholds[keyPath: key] = value
            if let data = try? JSONEncoder().encode(thresholds) { UserDefaults.standard.set(data, forKey: WeatherThresholds.storageKey) }
        })
    }

    private func carouselSlotBinding(_ key: WritableKeyPath<WeatherCarouselConfig, WeatherCarouselSlotMode>) -> Binding<WeatherCarouselSlotMode> {
        Binding(get: { carouselConfig[keyPath: key] }, set: { value in
            carouselConfig[keyPath: key] = value
            persistCarouselConfig()
        })
    }

    private func persistCarouselConfig() {
        UserDefaults.standard.set(carouselConfig.encoded(), forKey: WeatherCarouselConfig.defaultsKey)
        NotificationCenter.default.post(name: .weatherCarouselConfigDidChange, object: nil)
    }
}


extension SettingsWindowContent {
    /// Mission Control's Space rows: the desktop-only Spaces of the main display, in Mission Control
    /// order, keyed by the Space ID the layout reader reports. Empty when the layout is unreadable;
    /// the pane then offers Space 1 as a naming entry.
    static func missionControlSpaces() -> [(id: String, index: Int)] {
        guard let screen = NSScreen.main ?? NSScreen.screens.first,
              let uuid = DisplayIdentity.uuidString(for: screen),
              let layout = ManagedSpaceLayoutReader.layout(forDisplayUUID: uuid) else { return [] }
        let ordered = layout.orderedSpaceIDs.filter { !layout.fullscreenSpaceIDs.contains($0) }
        return ordered.enumerated().map { (String($0.element), $0.offset + 1) }
    }
}

private struct MenuBarMetricRow: View {
    let metric: MenuBarMetric
    @AppStorage private var isEnabled: Bool
    @AppStorage private var styleRaw: String

    init(metric: MenuBarMetric) {
        self.metric = metric
        _isEnabled = AppStorage(wrappedValue: MenuBarStatModel.defaultEnabled(metric), MenuBarStatModel.enabledKey(metric))
        _styleRaw = AppStorage(wrappedValue: MenuBarStatModel.defaultStyle(for: metric).rawValue, MenuBarStatModel.styleKey(metric))
    }

    var body: some View {
        let styles = MenuBarStatModel.styles(for: metric)
        let activeRaw = MenuBarStatModel.style(styleRaw, for: metric).rawValue
        SettingsRow(Text(MenuBarStatModel.displayName(metric))) {
            HStack(spacing: 8) {
                if !styles.isEmpty {
                    Picker(MenuBarStatModel.displayName(metric), selection: Binding(
                        get: { activeRaw },
                        set: { styleRaw = $0 }
                    )) {
                        ForEach(styles, id: \.self) { style in
                            Text(MenuBarStatModel.displayName(style)).tag(style.rawValue)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 145, alignment: .trailing)
                }
                Toggle(MenuBarStatModel.displayName(metric), isOn: $isEnabled)
                    .labelsHidden().toggleStyle(.switch)
            }
        }
    }
}

private struct MenuBarHubSettingsBlock: View {
    @AppStorage(MenuBarIconMode.defaultsKey) private var iconModeRaw = MenuBarIconMode.statusTrio.rawValue
    @AppStorage(StatusTrioStrokeWeight.defaultsKey) private var strokeRaw = StatusTrioStrokeWeight.regular.rawValue
    @AppStorage(MenuBarHubPrefs.semanticAlertsKey) private var semanticAlerts = false
    @AppStorage(MenuBarHubPrefs.compactReadoutKey) private var compactReadout = false
    @AppStorage(MenuBarHubPrefs.bluetoothInRingKey) private var bluetoothInRing = true
    @AppStorage(HubActionSlotID.defaultsKey) private var boxGridRaw = HubActionSlotID.serialize(HubActionSlotID.defaultSlots)
    @AppStorage(MenuBarHubTab.visibleTabsKey) private var visibleTabsRaw = MenuBarHubTab.serialize(MenuBarHubTab.allCases)
    @AppStorage(MenuBarRightClickConfig.defaultsKey) private var rightClickRaw = MenuBarRightClickConfig.serialize(MenuBarRightClickConfig.defaultTokens)
    @AppStorage(HubModule.storageKey) private var modulesRaw = ""

    var body: some View {
        SettingsCard(Text("Menu Bar Icon")) {
            SettingsSegmentedRow(Text("Style"), selection: $iconModeRaw) {
                Text("Status Trio Ring").tag(MenuBarIconMode.statusTrio.rawValue)
                Text("Classic").tag(MenuBarIconMode.classic.rawValue)
            }
            SettingsDivider()
            SettingsSegmentedRow(Text("Ring Stroke"), selection: $strokeRaw) {
                Text("Light").tag(StatusTrioStrokeWeight.light.rawValue)
                Text("Regular").tag(StatusTrioStrokeWeight.regular.rawValue)
                Text("Bold").tag(StatusTrioStrokeWeight.bold.rawValue)
            }
            SettingsDivider()
            SettingsRowPair(
                left: { SettingsToggleRow(Text("Semantic Alerts"), isOn: $semanticAlerts) },
                right: { SettingsToggleRow(Text("Compact Readout"), isOn: $compactReadout) }
            )
            SettingsDivider()
            SettingsToggleRow(Text("Bluetooth Audio in Ring"), isOn: $bluetoothInRing)
        }

        SettingsCard(Text("Left-Click Creative Hub")) {
            SettingsRowPair(
                left: { slotPicker(Text("Slot 1"), index: 0) },
                right: { slotPicker(Text("Slot 2"), index: 1) }
            )
            SettingsDivider()
            SettingsRowPair(
                left: { slotPicker(Text("Slot 3"), index: 2) },
                right: { slotPicker(Text("Slot 4"), index: 3) }
            )
            SettingsDivider()
            SettingsGrid(MenuBarHubTab.allCases, id: \.self) { tab in
                SettingsCheckboxRow(tabTitle(tab), isOn: Binding(
                    get: { activeTabs.contains(tab) },
                    set: { on in
                        var next = activeTabs
                        if on { if !next.contains(tab) { next.append(tab) } }
                        else if next.count > 1 { next.removeAll { $0 == tab } }
                        let ordered = MenuBarHubTab.allCases.filter { next.contains($0) }
                        visibleTabsRaw = MenuBarHubTab.serialize(ordered)
                    }
                ))
            }
        }

        // Tier B: off by default, and each module's view (and its CoreAudio / filesystem work) is
        // built only while its switch is on. Full-width rows, not a checklist grid: each switch
        // carries the one sentence a reader needs before turning it on.
        SettingsCard(Text("Modules")) {
            SettingsNote(Text("Optional modules stay off until enabled for zero idle CPU."))
            SettingsDivider()
            SettingsToggleRow(Text("Agents"), isOn: moduleBinding(.agents),
                              note: Text("Shows today's spend, the loadout profile and the approval pause in the Creative Hub."))
            SettingsDivider()
            SettingsToggleRow(Text("Audio Mixer"), isOn: moduleBinding(.audioMixer),
                              note: Text("Sets a level per app through a private audio tap. macOS asks for System Audio Recording the first time a slider moves."))
            SettingsDivider()
            SettingsToggleRow(Text("Uninstaller"), isOn: moduleBinding(.uninstaller),
                              note: Text("Plans the app and its support files, then moves them to the Trash."))
        }

        SettingsCard(Text("Right-Click Menu")) {
            SettingsGrid(MenuBarRightClickConfig.allowedTokens, id: \.self) { token in
                SettingsCheckboxRow(rightClickTitle(token), isOn: Binding(
                    get: { activeRightClickTokens.contains(token) },
                    set: { on in
                        var next = activeRightClickTokens
                        if on { if !next.contains(token) { next.append(token) } }
                        else { next.removeAll { $0 == token } }
                        rightClickRaw = MenuBarRightClickConfig.serialize(next)
                    }
                ))
            }
        }
    }

    private func moduleBinding(_ module: HubModule) -> Binding<Bool> {
        Binding(
            get: { HubModule.enabled(modulesRaw).contains(module) },
            set: { on in
                var next = HubModule.enabled(modulesRaw)
                if on { next.insert(module) } else { next.remove(module) }
                modulesRaw = HubModule.serialize(next)
            }
        )
    }

    private var activeSlots: [HubActionSlotID] {
        let parsed = boxGridRaw.split(separator: ",").compactMap { HubActionSlotID(rawValue: String($0)) }
        var seen = Set<HubActionSlotID>()
        var out = parsed.filter { seen.insert($0).inserted }
        for fb in HubActionSlotID.defaultSlots + HubActionSlotID.allCases where out.count < 4 && seen.insert(fb).inserted { out.append(fb) }
        return Array(out.prefix(4))
    }

    private var activeTabs: [MenuBarHubTab] {
        let parsed = visibleTabsRaw.split(separator: ",").compactMap { MenuBarHubTab(rawValue: String($0)) }
        return parsed.isEmpty ? MenuBarHubTab.allCases : parsed
    }

    private var activeRightClickTokens: [String] {
        let parsed = rightClickRaw.split(separator: ",").map(String.init)
        return parsed.filter { MenuBarRightClickConfig.allowedTokens.contains($0) }
    }

    private func slotPicker(_ label: Text, index: Int) -> some View {
        SettingsPickerRow(label, selection: Binding(
            get: { activeSlots[index] },
            set: { next in
                var slots = activeSlots
                slots[index] = next
                boxGridRaw = HubActionSlotID.serialize(slots)
            }
        )) {
            ForEach(HubActionSlotID.allCases) { slot in slotTitle(slot).tag(slot) }
        }
    }

    private func slotTitle(_ slot: HubActionSlotID) -> Text {
        if slot == .captureOCR { return Text("Capture Area") }
        if slot == .notchToggle { return Text("Notch") }
        if slot == .muteOutput { return Text("Mute Audio") }
        return QuickToggleID(rawValue: slot.rawValue)?.title ?? Text(verbatim: slot.rawValue)
    }

    private func tabTitle(_ tab: MenuBarHubTab) -> Text {
        switch tab {
        case .switches: return Text("Switches")
        case .statusAudio: return Text("Status & Audio")
        case .shortcutsEvolutions: return Text("Shortcuts & Evolutions")
        case .schedules: return Text("Schedules")
        }
    }

    private func rightClickTitle(_ token: String) -> Text {
        if token == "muteOutput" { return Text("Mute Audio") }
        return QuickToggleID(rawValue: token)?.title ?? Text(verbatim: token)
    }
}
