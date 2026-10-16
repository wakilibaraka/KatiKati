import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsWindowView: View {
    // Wide enough for ten toolbar items without the overflow chevron. The number lives in
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

    var body: some View {
        // ScrollView 保留作小屏兜底：每页正常都短于一屏，量高把窗口撑到内容高度，滚动不出现。
        // **指示器必须关**：滚动条样式为「自动」且接了鼠标时是占位式的，出现时吃掉约 15pt 可视宽，
        // 切页动画那 0.2 秒内容溢出 → 滚动条在位 → 整页水平平移一下。内层也不许写死宽度（见下）。
        ScrollView(.vertical, showsIndicators: false) {
            SettingsWindowContent(
                store: store,
                coordinator: coordinator,
                tabState: tabState,
                onShowWelcomeGuide: onShowWelcomeGuide
            )
        }
        .frame(width: Self.contentWidth)
    }
}

struct SettingsWindowContent: View {
    @ObservedObject var store: AppSettingsStore
    @ObservedObject var coordinator: SettingsCoordinator
    @ObservedObject var tabState: SettingsTabState
    let onShowWelcomeGuide: () -> Void

    @State private var presentedAlert: SettingsAlert?

    var body: some View {
        // The page margin lives here, once for all ten pages; every pane body renders cards only,
        // so no page can invent an inset of its own (`Docs/SETTINGS.md` rule 1).
        SettingsPane {
            switch tabState.selected {
            case .general: generalPane
            case .widgets:
                // Composed here, not inside the pane: `WidgetLookSettingsBlock` drives the pickers
                // defined in this app-only file, and the pane also compiles into the test target.
                WidgetLookSettingsBlock(store: store)
                SettingsLayoutPane(store: store, mode: .widgets)
            case .notch: notchPane
            case .edgeBars: SettingsLayoutPane(store: store, mode: .edgeBars)
            case .appearance: SettingsAppearancePane(store: store)
            case .windowManagement: windowManagementPane
            case .launcher: launcherPane
            case .shortcuts: SettingsLayoutPane(store: store, mode: .shortcuts)
            case .advanced: advancedPane
            case .tools: toolsPane
            }
        }
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
        SettingsCard {
            languagePicker
            SettingsDivider()
            // Plain stacks, not `LabeledContent`: that aligns on the text baseline, which an
            // AppKit-backed control lacks — the recorder drops below its own label.
            SettingsRow(Text("Appearance")) {
                appearanceCards
            }
            SettingsDivider()
            SettingsRow(Text("Show/hide taskbar shortcut")) {
                hotKeyControls
            }
            SettingsDivider()
            // Two narrow rows on one line (`Docs/SETTINGS.md` rule 5).
            SettingsRowPair(left: { drawerPlacementPicker }, right: { scrollReverserToggle })
        }
        // Permissions are a second group, not a setting of the first: its own card, never a
        // card inside a card.
        PermissionsSettingsBlock()
        // What used to be the About page, minus the page: four rows nobody visits are read here,
        // next to the settings they belong to (`Docs/SETTINGS.md` rule 5 allows three sections).
        SettingsCard(Text("About")) {
            aboutVersionRow
            SettingsDivider()
            SettingsRowPair(left: { autoUpdateToggle }, right: { diagnosticsRow })
        }
        welcomeGuideButton
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
        SettingsLayoutPane(store: store, mode: .notifications)
    }

    /// 「窗口管理」页: tiling, window chips, and the two window behaviours.
    @ViewBuilder
    private var windowManagementPane: some View {
        SettingsTilingPane(store: store)
        SettingsLayoutPane(store: store, mode: .chips)
        WindowBehaviourSettingsBlock()
    }

    /// 「启动器」页: the launcher and the Control Center, then the launcher's own rows. The tools
    /// that used to share this page are on their own tab now (`SettingsTab.tools`).
    @ViewBuilder
    private var launcherPane: some View {
        SettingsLayoutPane(store: store, mode: .launcher)
        LauncherSettingsBlock()
    }

    /// 「工具」页: the clipboard, commands and snippets, in the slot the About page left.
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

    // 登录时启动 2026-08-24 当天两度搬家：随去重进过设置窗口，owner 复议后定为
    // **只在状态栏菜单（第一项）**。这里不再放它，也不再需要 didBecomeActive 刷新。

    /// One control, one label (rule 6): the picker hides its own label and the row supplies it —
    /// this row used to read “Drawer Position” twice.
    private var drawerPlacementPicker: some View {
        SettingsPickerRow(
            Text("Drawer Position"),
            selection: Binding(
                get: { store.drawerPlacement },
                set: { store.setDrawerPlacement($0) }
            )
        ) {
            Text("Left").tag(DrawerPlacement.left)
            Text("Right").tag(DrawerPlacement.right)
        }
    }

    /// 界面语言（2026-08-24 加，2026-09-01 由三档收成两档、删掉「跟随系统」，见 `Docs/27`）。
    /// 写**应用自己域**的 `AppleLanguages`（与 macOS 13+ 逐 App 语言同一个键），重启生效。
    /// 读现状必须走 `CFPreferencesCopyAppValue`——`array(forKey:)` 会继承全局域，
    /// 分不清「没设过」和「显式设置」（`AppLanguageOption` 注释是权威）。
    ///
    /// ⚠️ 没设过语言的人键是不存在的，此时选单显示的是**推断值**（当前实际加载的那份
    /// `.lproj`）。**这条读取路径绝不许回写**：一回写就等于替所有从没选过的用户把语言钉死。
    private var languagePicker: some View {
        SettingsPickerRow(
            Text("Language"),
            selection: Binding(
                get: { Self.currentLanguageOption() },
                set: { applyLanguage($0) }
            )
        ) {
            ForEach(AppLanguageOption.allCases, id: \.self) { option in
                Text(option.displayName).tag(option)
            }
        }
    }

    private static func currentLanguageOption() -> AppLanguageOption {
        let bundleID = (Bundle.main.bundleIdentifier ?? "") as CFString
        let value = CFPreferencesCopyAppValue("AppleLanguages" as CFString, bundleID) as? [String]
        return AppLanguageOption.current(
            appDomainValue: value,
            // 真正加载的那份 .lproj——比推断系统语言准：用户在系统设置里给钨极单独设了
            // 第三种语言时界面实际回落英文，这里就答 English。
            effectiveLocalization: Bundle.main.preferredLocalizations.first ?? "en"
        )
    }

    /// 选中的档**一律写键**，哪怕点的就是当前显示的那一档——那一档可能只是推断值（键不存在），
    /// 用户点它的意思是「固定成这个」，不写就还在跟着系统跑。但界面语言没真的变时**不弹重启提示**：
    /// 什么都没变还要人重启是打扰。
    private func applyLanguage(_ option: AppLanguageOption) {
        let previous = Self.currentLanguageOption()
        UserDefaults.standard.set(option.appleLanguagesValue, forKey: "AppleLanguages")
        guard option != previous else { return }
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
    private var scrollReverserToggle: some View {
        SettingsToggleRow(
            Text("Reverse mouse scroll direction"),
            isOn: binding(get: { store.scrollReverserEnabled }, set: store.setScrollReverserEnabled),
            info: scrollReverserHelp
        )
    }

    private var scrollReverserHelp: String {
        String(localized: "Flips mouse-wheel scrolling system-wide, like Scroll Reverser. Trackpads and Magic Mouse are not affected. KatiKati only inverts the direction values of scroll-wheel events; nothing is recorded or sent anywhere. If Scroll Reverser or Mos is also running, the two cancel out — keep only one.")
    }

    /// 重开首次引导（那扇写系统 Dock 推荐设置的窗）。2026-09-01 从状态栏菜单搬来
    /// （owner 拍板）：它是"打开另一个界面"的入口，不是随手切的开关。
    /// 放「通用」页分组框下面——框里是设置，它是入口。
    ///
    /// ⚠️ 闭包直通 `AppDelegate.showWelcomeWindow()`，**绝不能改成走
    /// `presentWelcomeGuideIfNeeded()`、也不能靠删 `hasSeenWelcome`**：那条决策函数对
    /// 「系统 Dock 已自动隐藏」的存量用户恰好会跳过并把键写回，而存量用户正是这个入口的全部受众。
    private var welcomeGuideButton: some View {
        Button("Show Setup Guide Again") { onShowWelcomeGuide() }
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

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                let isSelected = mode == selection
                Button { onSelect(mode) } label: {
                    VStack(spacing: 5) {
                        Image(systemName: Self.symbolName(for: mode))
                            .font(.system(size: 16))
                            .foregroundColor(isSelected ? .accentColor : .secondary)
                            .frame(height: 18)
                        Text(mode.displayName)
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .frame(minWidth: 76, minHeight: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 1.5)
                            .opacity(isSelected ? 1 : 0)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
struct WeatherSettingsBlock: View {
    @AppStorage(WeatherUnits.temperatureKey) private var tempUnit: TemperatureUnit = .celsius
    @AppStorage(WeatherUnits.windKey) private var windUnit: WindSpeedUnit = .kmh
    @AppStorage(WeatherLayoutPreset.storageKey) private var weatherLayout: WeatherLayoutPreset = .glance
    @AppStorage(WeatherHeroStyle.storageKey) private var heroStyle: WeatherHeroStyle = .scene
    @State private var thresholds = WeatherPrefs.thresholds()

    /// Rows only, no card: `WidgetLookSettingsBlock` puts them in the "Weather" section. Every row is
    /// a shared variant, so a control's alignment follows its type instead of this block's opinion
    /// (`Docs/SETTINGS.md` rule 3).
    var body: some View {
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
        SettingsRowPair(
            left: {
                SettingsSegmentedRow(Text("Weather Layout"), selection: $weatherLayout) {
                    Text("Glance").tag(WeatherLayoutPreset.glance)
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
        // "Weather Animations" moved to the Widget Appearance card (2026-10-15), where the other
        // widget-animation row already lives and where it shares a line instead of owning one.
        SettingsDivider()
        // Two thresholds, one line (`Docs/SETTINGS.md` rule 5): each is a short readout and a
        // stepper, which fits half a card — measured live 2026-10-15, the label is 156 pt and the
        // readout under 40. The third stays on its own line.
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
}
