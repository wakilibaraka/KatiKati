import Combine
import Foundation

/// App-wide appearance (settings window → General → Appearance). The bar, capsule, drawer, bubble,
/// menus, settings and guide windows all follow it; the stack popups stay dark either way.
///
/// It is applied as `NSApp.appearance` (`AppDelegate`) and nowhere else: the materials and SwiftUI's
/// `colorScheme` both derive from the window appearance, so one switch keeps text and plate together.
///
/// The raw value is persisted — renaming a case resets everyone who chose it to `system`.
enum AppearanceMode: String, CaseIterable {
    /// Whatever macOS is showing right now, including its own automatic light/dark schedule.
    case system
    case light
    case dark

    static let `default` = AppearanceMode.system

    var displayName: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }
}

enum NowPlayingTheme: String, CaseIterable {
    case auto
    case light
    case dark

    var displayTitle: String {
        switch self {
        case .auto: return String(localized: "Auto")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }
}

enum DrawerPlacement: String, CaseIterable {
    case left
    case right
}

/// 悬停效果档位。
/// - `standard`：图标 36→24pt 缩放 + 下方冒出名字 + 文件夹格整块放大（原生程序坞手感）。
/// - `quiet`：鼠标划过任务条时**完全静止**——不缩放、不移动、不冒名字、胶囊底色不提亮。
///
/// 两个不受本档位影响的地方（owner 2026-08-02 定）：**抽屉面板里的图标**照旧，
/// **抽屉入口胶囊**里的四宫格照旧轻微放大——胶囊属于抽屉。
/// 「标题太长时弹出全文浮层」在两档下都保留：它是看全被截断标题的唯一途径，且不移动任何卡片。
///
/// **对外只是一个勾选项**：菜单上叫「鼠标悬停显示应用名」，**勾选 = `.standard`**，
/// 取消勾选 = `.quiet`（owner 2026-08-02 改名，原来的「悬停效果 ▸ 标准 / 安静」太抽象）。
/// 那个名字**有意只说了一半**——取消勾选同时也停掉图标缩放和文件夹格放大；
/// 别为了对齐名字去缩小行为范围，理由见 `Docs/27`。代码里其余地方仍按内部概念叫
/// 「安静档」（= `.quiet` = 取消勾选），枚举保留也是为了以后可能加第三档。
enum HoverStyle: String, CaseIterable {
    case standard
    case quiet

    /// **默认 `.standard`**（owner 2026-10-21 改回；2026-09-01 曾定为 `.quiet`）：鼠标划过
    /// 任务条弹应用名气泡。老用户键里已有值，不受影响。
    static let `default` = HoverStyle.standard

    /// 悬停是否产生**表现型**变化（名字气泡、文件夹格放大）。chip 视图统一用它做判据，
    /// 不各自比 case；菜单的勾选态也读它（`.on` ⟺ `isExpressive`）。
    var isExpressive: Bool { self == .standard }

    /// 表现型悬停此刻是否在发生（名字气泡 / 文件夹格放大）。各 chip 共用，不各自写 `isExpressive && isHovered`。
    func showsExpressiveHover(isHovering: Bool) -> Bool { isExpressive && isHovering }

    /// 安静档的悬停反馈：整块**轻微放大**。
    ///
    /// **标准档恒 false**——那一档的反馈是名字气泡，owner 2026-08-17 要求标准档一个像素不变。
    /// 加这个是因为安静档原本**一点反馈都没有**：2026-08-16 把应用名挪进气泡时顺手冻结了
    /// chip 的悬停几何（图标不缩、药丸不让位），标准档还剩气泡，安静档就归零了。
    ///
    /// 形式先做过「不改尺寸的淡底色」（`Docs/27` 早年预判的那条），owner 2026-08-17 实机
    /// 看完说「一般」，改成轻微放大。**放大在今天是安全的**：当年否掉它的理由是「改尺寸会让
    /// 整行重排」，而那说的是把应用名写在图标下方、名字一冒出来卡就变宽的老布局；
    /// 名字挪进气泡之后两档都不再重排，且这里用的是 `scaleEffect`（纯渲染变换，不改布局）。
    ///
    func showsQuietHoverFeedback(isHovering: Bool) -> Bool {
        !isExpressive && isHovering
    }
}

/// 用户自定义的显隐任务条快捷键（nil = 默认 ⌥⇧⌘D）。
/// `glyphs` 在录制那一刻由 NSEvent 的字符定格（理由见 `HotKeyGlyphs`），展示端只读它。
struct StoredHotKeyShortcut: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let glyphs: String
}


@MainActor
final class AppSettingsStore: ObservableObject {
    static let delayStep: Double = 0.1
    static let finiteDelayMin: Double = 0.1
    static let finiteDelayMax: Double = 3.0
    static let neverHideDelay: Double = -1.0
    static let neverWakeDelay: Double = 999.0
    static let sliderIndexMax = 31
    // nonisolated：要在 snapDelay 的默认参数（nonisolated 求值上下文）里引用。
    nonisolated static let defaultNativeDockAutoHideDelay: Double = 1.0
    /// **全新安装时钨极自己那条的档位：常驻**（owner 2026-09-01 定，此前是 0.1 秒唤醒的自动隐藏）。
    /// 只用在 `register` 那一处。
    ///
    /// ⚠️ **和下面那个是两个常量，永远不许合并。** 这个是「首次装上是什么样」，
    /// 下面那个是「自动隐藏开着时用哪一档」——后者必须是**有限值**，被两处兜底依赖：
    /// remembered 值不许是 `-1`（否则 ⌥⇧⌘D 从常驻切走还是常驻，快捷键变空操作），
    /// `snapDelay` 的非有限兜底也不许是 `-1`（否则 NaN 会被解释成「常驻」这个哨兵）。
    nonisolated static let firstRunEdgeAutoHideDelay: Double = AppSettingsStore.neverHideDelay
    /// 自动隐藏**开着**时的默认档，也是 remembered 与非有限值的兜底。见上面那条 ⚠️。
    nonisolated static let defaultEnabledEdgeAutoHideDelay: Double = 0.1

    static let defaultCenteredWidth: CGFloat = 720
    static let minimumCenteredWidth: CGFloat = 360
    static let maximumCenteredWidth: CGFloat = 1600
    // Fresh install = the **Comfortable** Spacing card (Phase 41c). Derived, not a literal: while
    // these said 10/12 and the card said 10/12 the two agreed by coincidence, and the segmented row
    // reads Custom the moment they drift.
    static let defaultIslandGap: CGFloat = DockSpacing.comfortable.gap
    static let minimumIslandGap: CGFloat = 0.5
    static let defaultIslandMargin: CGFloat = DockSpacing.comfortable.margin
    static let minimumIslandMargin: CGFloat = 0

    @Published private(set) var launchAtLogin: Bool
    /// 中转格是否显示在固定文件夹区头位。关掉后它不再渲染，暂存的文件不受影响。
    @Published private(set) var showShelf: Bool
    @Published private(set) var drawerPlacement: DrawerPlacement
    @Published var nowPlayingTheme: NowPlayingTheme {
        didSet {
            if nowPlayingTheme != oldValue {
                UserDefaults.standard.set(nowPlayingTheme.rawValue, forKey: Keys.nowPlayingTheme)
            }
        }
    }
    
    @Published private(set) var showTrash: Bool
    /// Live Island on the dock capsule (default ON — today's behaviour).
    @Published private(set) var dockIslandEnabled: Bool
    /// Live Island on the notch (default ON; the welcome guide offers a switch to turn it off).
    @Published private(set) var notchIslandEnabled: Bool
    /// Dropover-style shelf: shake a dragged file to summon the drop target (default on).
    @Published private(set) var shelfShakeEnabled: Bool
    /// Drop unpinned shelf items after `shelfExpiryDays` (default off).
    @Published private(set) var shelfAutoExpire: Bool
    @Published private(set) var shelfExpiryDays: Int
    @Published private(set) var shelfStorage: ShelfStorage
    /// Look of the notch Live Island (`boring` = full panel with music + calendar; default).
    @Published private(set) var notchSkin: LiveIslandSkin
    /// Where event notifications show — exactly one place by default, never duplicated (8b-5).
    @Published private(set) var liveEventRoute: LiveEventRoute
    /// OS Notification Center banners for Live Island events (8b-4c). Opt-in, default OFF; only fires
    /// when no in-app surface showed the event.
    @Published private(set) var liveEventOSBanners: Bool
    /// Phase 9a: per-app window-chip grouping (default `.separate` = today's behaviour).
    @Published private(set) var chipGroupingPlan: WindowChipGroupingPlan
    /// Phase 9c/9b: hover window preview + the floating jump list on right-click.
    @Published private(set) var chipPreviewEnabled: Bool
    @Published private(set) var chipPreviewDelayMs: Int
    @Published private(set) var chipPreviewThumbWidth: Int
    @Published private(set) var chipClassicMenu: Bool
    /// Phase 9e: Caps Lock as Hyper. Off by default; needs Input Monitoring.
    @Published private(set) var hyperkeyEnabled: Bool
    /// Every running app gets a chip, even with no window (like the system Dock). Default on.
    @Published private(set) var showAllRunningApps: Bool
    /// Strip tracking parameters from copied links (8e). Opt-in, default OFF — it edits the clipboard.
    @Published private(set) var linkCleanerEnabled: Bool
    /// 任务条尺寸档位。面板几何与条内所有 chip 尺寸都由它派生。
    @Published private(set) var dockPanelHeight: DockPanelHeight
    /// 任务条布局模式（windows / split3 / split4 / centered）。缺键 = windows。
    @Published private(set) var barLayoutMode: BarLayoutMode
    
    @Published private(set) var widgetOrder: [BarSection]
    /// Phase 10a widget arrangement (order / size / visibility). Not yet consumed by the strip.
    @Published private(set) var widgetLayout: WidgetLayout
    /// Phase 18: which edge the strip sits on, globally and per display (default bottom).
    @Published private(set) var stripPlacementMap: StripPlacementMap
    /// 10b: weather/time reactive desktop wallpaper (off by default), its mode (`WallpaperMode` raw) and optional custom folder.
    @Published private(set) var wallpaperEnabled: Bool
    @Published private(set) var wallpaperMode: String
    @Published private(set) var wallpaperFolder: String
    /// 10b: tint the dock surface from the current sun phase (off by default).
    @Published private(set) var tintSurfacesByPhase: Bool
    /// 10a-7: schedule-driven widget presets (off by default); preset ids per window, "" = none.
    @Published private(set) var contextPresetsEnabled: Bool
    @Published private(set) var contextWorkPresetID: String
    @Published private(set) var contextEveningPresetID: String
    /// User-saved widget presets (built-ins live in `WidgetPresets.builtIns`).
    @Published private(set) var userWidgetPresets: [WidgetPreset]
    /// 居中模式下的目标宽度（points，默认 720，限制 360...1600）。
    @Published private(set) var centeredWidth: CGFloat
    /// 岛屿之间的间距（points，默认 10，最小 0.5）。
    @Published private(set) var islandGap: CGFloat
    /// 任务条距离屏幕左右边缘的外边距（points，默认 12，最小 0）。
    @Published private(set) var islandMargin: CGFloat
    /// 条底与屏幕下缘的间距（points，默认 8 = 浮动，Hugging 预设 2，限制 0...12）。
    @Published private(set) var bottomGap: CGFloat
    /// Edge bars (Phase 7A): the layout preset (default Productivity + Rest) and the side that hosts notes / productivity.
    @Published private(set) var edgeBarPreset: EdgeBarPreset
    /// Phase 18g: an edge bar on the dock rail's edge moves across (merging when needed) or hides.
    @Published private(set) var edgeConflictPolicy: EdgeConflictPolicy
    @Published private(set) var edgePrimarySide: EdgeSide
    /// Enabled productivity buttons (7A-P1; default all) and the Custom layout (item → left / right / hidden).
    @Published private(set) var productivityItems: [ProductivityItem]
    @Published private(set) var edgeCustomPlacements: [EdgeItem: EdgePlacement]
    /// Edge-bar gap above the bottom bar / margin from the screen side (min 0.5, Appendix C).
    @Published private(set) var edgeGap: CGFloat
    /// Notes sync with the iCloud Drive folder (7A-7c). Opt-in, default off.
    @Published private(set) var notesSyncEnabled: Bool
    /// Enabled widget tiles on the left-edge widgets bar, in display order (7A-8). Empty = no widgets bar.
    @Published private(set) var widgetTiles: [WidgetTile]
    /// Noty-style deck settings (7A-D1): one scale for the whole deck, keep-open, hover behaviours, tile look,
    /// tab font (PostScript name, "" = system) and the pill's vertical position per edge (0 = bottom, 1 = top).
    /// Size of each edge's deck (0.8…1.4), set per side; the old single `deckScale` seeds both until one is set.
    @Published private(set) var deckScaleLeft: Double
    @Published private(set) var deckScaleRight: Double
    /// Dock-style magnification of the round buttons under the pointer.
    @Published private(set) var deckMagnify: Bool
    @Published private(set) var launcherScrollDirection: LauncherScrollDirection
    @Published private(set) var launcherPinch: Bool
    @Published private(set) var launcherTheme: LauncherTheme
    @Published private(set) var launcherTint: LauncherTint
    @Published private(set) var launcherIcon: LauncherIconStyle
    /// Phase 16n: which switches and widgets the Control Center shows (user presets).
    @Published private(set) var controlCenterToggles: [QuickToggleID]
    @Published private(set) var controlCenterWidgets: [TileKind]
    /// Phase 16v: Control Center size preset, vertical anchor and open animation.
    @Published private(set) var controlCenterSize: ControlCenterSize
    @Published private(set) var controlCenterAnchor: ControlCenterAnchor
    @Published private(set) var controlCenterAnimation: ControlCenterAnimation
    @Published private(set) var shortcutBindings: [ShortcutAction: ShortcutTrigger]
    @Published private(set) var launcherSearchPosition: LauncherSearchPosition
    @Published private(set) var deckKeepOpen: Bool
    @Published private(set) var deckOpenOnHover: Bool
    @Published private(set) var deckTabPreview: Bool
    @Published private(set) var edgeTileStyle: EdgeTileStyle
    /// Phase 13: open delay, hot-zone sensitivity, magnify amount, icon set, flyout style (one JSON blob).
    @Published private(set) var edgePrefs: EdgeBarPrefs
    @Published private(set) var deckTabFont: String
    @Published private(set) var deckYRatioLeft: Double
    @Published private(set) var deckYRatioRight: Double
    @Published private(set) var edgeMargin: CGFloat
    /// 材质主题。默认 auto (亮色 roseQuartz / 暗色 obsidianDark)。
    @Published private(set) var themeMaterial: DockThemeStyle
    /// Phase 12 —— Appearance 页的两个底板旋钮。默认值就是滑块出现前的观感（
    /// `ThemeTuning.identity`），所以从没碰过它们的人看到的底板逐像素不变。
    @Published private(set) var themeVibrancy: CGFloat
    @Published private(set) var themeContrast: CGFloat
    /// 图标集（modern 3D / classic SF Symbols），与主题互相独立。缺键 = modern。
    @Published private(set) var iconSet: IconSet
    /// 悬停效果档位。只影响条内 chip 的悬停视觉，静息布局逐像素不变（因此无需 relayout）。
    @Published private(set) var hoverStyle: HoverStyle
    /// 最大化窗口避让任务条（菜单「最大化窗口避开任务条」）。
    /// **全新安装播种为开，老用户维持关**（owner 2026-09-01；此前所有人默认关）——
    /// 它配的是同一轮定的「任务条默认常驻」：常驻会压住最大化窗口的底边，避让正好补上。
    /// 但这个功能会真的去改写**别人应用**的窗口尺寸，所以不能因为一次升级就替老用户打开，
    /// 播种走 `seedWindowLiftEnabledForFreshInstall()`，见那里的注释。
    @Published private(set) var windowLiftEnabled: Bool
    /// 标准绿灯 / Control-Command-F 输入投递前预测隐藏任务条，默认开启。
    @Published private(set) var fullscreenIntentEnabled: Bool
    /// 自定义显隐任务条快捷键；nil = 默认 ⌥⇧⌘D。**只由 `SettingsCoordinator.applyEdgeToggleShortcut`
    /// 在注册成功后写入**——先落盘再注册失败会让存的键和实际生效的键分家。
    @Published private(set) var edgeToggleShortcut: StoredHotKeyShortcut?
    /// See `AppearanceMode`. Missing or unrecognised stored value = `system`.
    @Published private(set) var appearanceMode: AppearanceMode
    /// 全局反转鼠标滚轮（只反离散滚轮，触控板 / 妙控鼠标不动）。**默认关**——
    /// 改写全系统输入事件的能力必须由用户主动选择，理由同 `windowLiftEnabled`。
    @Published private(set) var scrollReverserEnabled: Bool
    /// 任务条显示位置。默认 `.followMouse` = 现状（底边停留切屏）；`.pinned` 固定到某屏。
    @Published private(set) var taskbarScreenPlacement: TaskbarScreenPlacement
    /// 这台机器已经看过首次运行的欢迎引导（建议隐藏系统 Dock 那一屏）。
    /// 一次性显示状态，和「有没有真的去隐藏」无关——用户点了「以后再说」也算看过，
    /// 不再骚扰；想改的人走状态栏菜单里那条系统 Dock 滑杆。
    @Published private(set) var hasSeenWelcome: Bool
    @Published private(set) var nativeDockAutoHideDelay: Double
    @Published private(set) var edgeAutoHideDelay: Double
    /// 「自动隐藏」切换（菜单/全局快捷键）从常驻恢复时要回到的延迟值。
    /// 只允许有限档位（0.1...3.0）或不唤醒（999），绝不允许常驻（-1）本身。
    private(set) var lastEnabledEdgeAutoHideDelay: Double
    /// 系统 Dock 组的镜像 remembered，规则同上（回退默认档位是 1.0）。
    private(set) var lastEnabledNativeDockAutoHideDelay: Double

    var nativeDockAutoHideEnabled: Bool { nativeDockAutoHideDelay != Self.neverHideDelay }
    var edgeAutoHideEnabled: Bool { edgeAutoHideDelay != Self.neverHideDelay }
    var taskbarPerDisplaySeedPending: Bool {
        defaults.bool(forKey: Keys.taskbarScreenPerDisplaySeedPending)
    }
    var hasStoredTaskbarScreenChoice: Bool {
        defaults.object(forKey: Keys.taskbarScreenMode) != nil
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        TungstenDefaultsMigrator.migrateIfNeeded(defaults: defaults)
        Self.migrateLegacyEnabledKey(
            defaults: defaults,
            enabledKey: Keys.nativeDockAutoHideEnabled,
            delayKey: Keys.nativeDockAutoHideDelay
        )
        Self.migrateLegacyEnabledKey(
            defaults: defaults,
            enabledKey: Keys.edgeAutoHideEnabled,
            delayKey: Keys.edgeAutoHideDelay
        )
        Self.forceNewLayoutDefaults(defaults: defaults)
        // Phase 4U decision 3: the widget order is hardcoded — no reader, no writer.
        // Decision 8b removed `.tray` (edge-bar scope): canonical order is weather → apps → clock.
        let defaultWidgetOrder: [BarSection] = BarSection.canonicalOrder
        
        // remembered 键（lastEnabledDelay）不注册默认值：区分「从未写过」和「真实写过」，
        // 从未写过时由下面的播种逻辑决定，而不是静默拿到一个注册出来的假历史值。
        defaults.register(defaults: [
            Keys.launchAtLogin: false,
            Keys.drawerPlacement: DrawerPlacement.right.rawValue,
            Keys.showShelf: true,
            Keys.showTrash: true,
            Keys.fullscreenIntentEnabled: true,
            Keys.nativeDockAutoHideDelay: Self.defaultNativeDockAutoHideDelay,
            // 首次安装 = 常驻；remembered 的种子仍是有限档，见常量注释。
            Keys.edgeAutoHideDelay: Self.firstRunEdgeAutoHideDelay,
            Keys.barLayoutMode: BarLayoutMode.centered.rawValue,
            Keys.centeredWidth: Double(Self.defaultCenteredWidth),
            Keys.islandGap: Double(Self.defaultIslandGap),
            Keys.islandMargin: Double(Self.defaultIslandMargin),
            Keys.bottomGap: Double(PanelLayoutMetrics.huggingBottomGap),
            Keys.edgePreset: EdgeBarPreset.default.rawValue,
            Keys.edgePrimarySide: EdgeSide.right.rawValue,
            Keys.widgetTiles: WidgetTile.serialize(WidgetTile.allCases),
            Keys.productivityItems: ProductivityItem.serialize(ProductivityItem.allCases),
            Keys.edgeGap: Double(PanelGeometry.edgeBarDefaultBottomGap),
            Keys.edgeMargin: 8.0,
            Keys.notesSync: false,
            Keys.dockIslandEnabled: true,
            Keys.notchIslandEnabled: true,
            Keys.notchSkin: LiveIslandSkin.boring.rawValue,
            Keys.themeVibrancy: Double(DockThemeStyle.identityVibrancy),
            Keys.themeContrast: 1.0,
            ShelfStore.shakeKey: true,
            ShelfStore.autoExpireKey: false,
            ShelfStore.expiryDaysKey: 1,
            ShelfStore.storageKey: ShelfStorage.reference.rawValue,
            Keys.liveEventRoute: LiveEventRoute.automatic.rawValue,
            Keys.liveEventOSBanners: false,
            Keys.chipPreviewEnabled: true,
            Keys.chipPreviewDelayMs: 350,
            Keys.chipPreviewThumbWidth: 180,
            Keys.chipClassicMenu: false,
            Keys.hyperkeyEnabled: false,
            Keys.showAllRunningApps: false,
            Keys.linkCleanerEnabled: false,
            Keys.wallpaperEnabled: false,
            Keys.wallpaperMode: WallpaperMode.both.rawValue,
            Keys.deckScale: DeckSettingsRules.defaultScale,
            Keys.deckMagnify: true,
            Keys.launcherScroll: LauncherScrollDirection.default.rawValue,
            Keys.launcherPinch: false,
            Keys.launcherTheme: LauncherTheme.default.rawValue,
            Keys.launcherTint: LauncherTint.default.rawValue,
            Keys.launcherIcon: LauncherIconStyle.default.rawValue,
            Keys.controlCenterToggles: QuickToggleID.serialize(QuickToggleID.defaultOrder),
            Keys.controlCenterWidgets: TileKind.serialize(TileKind.controlCenterDefault),
            Keys.controlCenterSize: ControlCenterSize.default.rawValue,
            Keys.controlCenterAnchor: ControlCenterAnchor.default.rawValue,
            Keys.controlCenterAnimation: ControlCenterAnimation.default.rawValue,
            Keys.launcherSearchPosition: LauncherSearchPosition.default.rawValue,
            Keys.deckKeepOpen: false,
            Keys.deckOpenOnHover: false,
            Keys.deckTabPreview: true,
            Keys.edgeTileStyle: EdgeTileStyle.glass.rawValue,
            Keys.deckTabFont: "",
            Keys.deckYRatioLeft: 0.5,
            Keys.deckYRatioRight: 0.5
        ])

        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        drawerPlacement = DrawerPlacement(rawValue: defaults.string(forKey: Keys.drawerPlacement) ?? "") ?? .right
        showShelf = defaults.bool(forKey: Keys.showShelf)
        nowPlayingTheme = NowPlayingTheme(rawValue: defaults.string(forKey: Keys.nowPlayingTheme) ?? "") ?? .auto
        showTrash = defaults.bool(forKey: Keys.showTrash)
        dockIslandEnabled = defaults.bool(forKey: Keys.dockIslandEnabled)
        notchIslandEnabled = defaults.bool(forKey: Keys.notchIslandEnabled)
        shelfShakeEnabled = defaults.bool(forKey: ShelfStore.shakeKey)
        shelfAutoExpire = defaults.bool(forKey: ShelfStore.autoExpireKey)
        shelfExpiryDays = ShelfPolicy.expiryChoices.contains(defaults.integer(forKey: ShelfStore.expiryDaysKey)) ? defaults.integer(forKey: ShelfStore.expiryDaysKey) : 1
        shelfStorage = ShelfStorage(rawValue: defaults.string(forKey: ShelfStore.storageKey) ?? "") ?? .reference
        notchSkin = LiveIslandSkin(rawValue: defaults.string(forKey: Keys.notchSkin) ?? "") ?? .boring
        liveEventRoute = LiveEventRoute(rawValue: defaults.string(forKey: Keys.liveEventRoute) ?? "") ?? .automatic
        liveEventOSBanners = defaults.bool(forKey: Keys.liveEventOSBanners)
        chipPreviewEnabled = defaults.bool(forKey: Keys.chipPreviewEnabled)
        chipPreviewDelayMs = Self.chipPreviewDelayChoices.contains(defaults.integer(forKey: Keys.chipPreviewDelayMs)) ? defaults.integer(forKey: Keys.chipPreviewDelayMs) : 350
        chipPreviewThumbWidth = Self.chipPreviewSizeChoices.contains(defaults.integer(forKey: Keys.chipPreviewThumbWidth)) ? defaults.integer(forKey: Keys.chipPreviewThumbWidth) : 180
        chipClassicMenu = defaults.bool(forKey: Keys.chipClassicMenu)
        hyperkeyEnabled = defaults.bool(forKey: Keys.hyperkeyEnabled)
        showAllRunningApps = defaults.bool(forKey: Keys.showAllRunningApps)
        chipGroupingPlan = WindowChipGroupingPlan(
            defaultPolicy: WindowChipGroupPolicy(rawValue: defaults.string(forKey: Keys.chipGroupingDefault) ?? "") ?? .separate,
            overrides: (defaults.dictionary(forKey: Keys.chipGroupingOverrides) as? [String: String] ?? [:])
                .compactMapValues(WindowChipGroupPolicy.init(rawValue:))
        )
        linkCleanerEnabled = defaults.bool(forKey: Keys.linkCleanerEnabled)
        wallpaperEnabled = defaults.bool(forKey: Keys.wallpaperEnabled)
        wallpaperMode = WallpaperMode(rawValue: defaults.string(forKey: Keys.wallpaperMode) ?? "")?.rawValue ?? WallpaperMode.both.rawValue
        wallpaperFolder = defaults.string(forKey: Keys.wallpaperFolder) ?? ""
        tintSurfacesByPhase = defaults.bool(forKey: Keys.tintByPhase)
        contextPresetsEnabled = defaults.bool(forKey: ContextPresetRules.enabledKey)
        contextWorkPresetID = defaults.string(forKey: Keys.contextWorkPreset) ?? ""
        contextEveningPresetID = defaults.string(forKey: Keys.contextEveningPreset) ?? ""
        barLayoutMode = BarLayoutMode(rawValue: defaults.string(forKey: Keys.barLayoutMode) ?? "") ?? .centered
        let storedCentered = Self.storedNumericValue(defaults.object(forKey: Keys.centeredWidth)) ?? Double(Self.defaultCenteredWidth)
        centeredWidth = CGFloat(min(max(storedCentered, Double(Self.minimumCenteredWidth)), Double(Self.maximumCenteredWidth)))
        let storedGap = Self.storedNumericValue(defaults.object(forKey: Keys.islandGap)) ?? Double(Self.defaultIslandGap)
        islandGap = CGFloat(max(Double(Self.minimumIslandGap), storedGap))
        let storedMargin = Self.storedNumericValue(defaults.object(forKey: Keys.islandMargin)) ?? Double(Self.defaultIslandMargin)
        islandMargin = CGFloat(max(Double(Self.minimumIslandMargin), storedMargin))
        let storedBottomGap = Self.storedNumericValue(defaults.object(forKey: Keys.bottomGap)) ?? Double(PanelLayoutMetrics.huggingBottomGap)
        bottomGap = Self.clampedBottomGap(CGFloat(storedBottomGap))
        edgeBarPreset = EdgeBarPreset(rawValue: defaults.string(forKey: Keys.edgePreset) ?? "") ?? .default
        edgeConflictPolicy = EdgeConflictPolicy(rawValue: defaults.string(forKey: EdgeConflictPolicy.defaultsKey) ?? "") ?? .moveAcross
        edgePrimarySide = EdgeSide(rawValue: defaults.string(forKey: Keys.edgePrimarySide) ?? "") ?? .right
        productivityItems = ProductivityItem.parse(defaults.string(forKey: Keys.productivityItems))
        edgeCustomPlacements = EdgeItem.parsePlacements(defaults.string(forKey: Keys.edgeCustom))
        notesSyncEnabled = defaults.bool(forKey: Keys.notesSync)
        widgetTiles = WidgetTile.parse(defaults.string(forKey: Keys.widgetTiles))
        let legacyScale = Self.storedNumericValue(defaults.object(forKey: Keys.deckScale))
        deckScaleLeft = DeckSettingsRules.clampedScale(Self.storedNumericValue(defaults.object(forKey: Keys.deckScaleLeft)) ?? legacyScale)
        deckScaleRight = DeckSettingsRules.clampedScale(Self.storedNumericValue(defaults.object(forKey: Keys.deckScaleRight)) ?? legacyScale)
        deckMagnify = defaults.bool(forKey: Keys.deckMagnify)
        launcherSearchPosition = LauncherSearchPosition.parse(defaults.string(forKey: Keys.launcherSearchPosition))
        controlCenterToggles = QuickToggleID.parse(defaults.string(forKey: Keys.controlCenterToggles))
        controlCenterWidgets = TileKind.parse(defaults.string(forKey: Keys.controlCenterWidgets))
        controlCenterSize = ControlCenterSize.parse(defaults.string(forKey: Keys.controlCenterSize))
        controlCenterAnchor = ControlCenterAnchor.parse(defaults.string(forKey: Keys.controlCenterAnchor))
        controlCenterAnimation = ControlCenterAnimation.parse(defaults.string(forKey: Keys.controlCenterAnimation))
        shortcutBindings = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map {
            ($0, ShortcutTrigger.parse(defaults.string(forKey: Keys.shortcut($0))) ?? $0.defaultTrigger)
        })
        launcherTheme = LauncherTheme.parse(defaults.string(forKey: Keys.launcherTheme))
        launcherTint = LauncherTint.parse(defaults.string(forKey: Keys.launcherTint))
        launcherIcon = LauncherIconStyle.parse(defaults.string(forKey: Keys.launcherIcon))
        launcherScrollDirection = LauncherScrollDirection.parse(defaults.string(forKey: Keys.launcherScroll))
        launcherPinch = defaults.bool(forKey: Keys.launcherPinch)
        deckKeepOpen = defaults.bool(forKey: Keys.deckKeepOpen)
        deckOpenOnHover = defaults.bool(forKey: Keys.deckOpenOnHover)
        deckTabPreview = defaults.bool(forKey: Keys.deckTabPreview)
        edgeTileStyle = EdgeTileStyle(rawValue: defaults.string(forKey: Keys.edgeTileStyle) ?? "") ?? .glass
        edgePrefs = EdgeBarPrefs.load(defaults)
        deckTabFont = defaults.string(forKey: Keys.deckTabFont) ?? ""
        deckYRatioLeft = DeckSettingsRules.clampedRatio(Self.storedNumericValue(defaults.object(forKey: Keys.deckYRatioLeft)))
        deckYRatioRight = DeckSettingsRules.clampedRatio(Self.storedNumericValue(defaults.object(forKey: Keys.deckYRatioRight)))
        edgeGap = Self.clampedEdgeSpacing(Self.storedNumericValue(defaults.object(forKey: Keys.edgeGap)), fallback: PanelGeometry.edgeBarDefaultBottomGap)
        edgeMargin = Self.clampedEdgeSpacing(Self.storedNumericValue(defaults.object(forKey: Keys.edgeMargin)), fallback: 8)
        
        // Hardcoded order (Phase 4U decision 3): any previously stored custom order
        // from the removed drag-reorder UI is ignored, not restored.
        // Phase 40e: the sliders that wrote this legacy dictionary retired, but the migration stays — a
        // stored width still renders as it did, and picking any S/M/L preset clears it (`setWidgetSize`).
        let legacyWidgetWidths = defaults.dictionary(forKey: "widgetWidths") as? [String: CGFloat] ?? [:]
        let storedWidgetLayout = WidgetLayout.decode(defaults.data(forKey: WidgetLayout.defaultsKey))
            ?? WidgetLayout.migrating(legacyWidths: legacyWidgetWidths)
        widgetLayout = storedWidgetLayout
        widgetOrder = storedWidgetLayout.visibleOrder
        stripPlacementMap = StripPlacementMap.decode(defaults.data(forKey: StripPlacementMap.defaultsKey)) ?? StripPlacementMap()
        userWidgetPresets = WidgetPresets.decode(defaults.data(forKey: WidgetPresets.defaultsKey))
        
        themeMaterial = DockThemeStyle(token: defaults.string(forKey: Keys.themeMaterial) ?? "") ?? .auto
        // Both knobs go through the same clamp the setters use, so a hand-edited key cannot put the
        // plate somewhere the sliders cannot.
        themeVibrancy = ThemeTuning.resolved(
            vibrancy: Self.storedNumericValue(defaults.object(forKey: Keys.themeVibrancy))
                .map { CGFloat($0) } ?? DockThemeStyle.identityVibrancy,
            contrast: 1
        ).vibrancy
        themeContrast = ThemeTuning.resolved(
            vibrancy: DockThemeStyle.identityVibrancy,
            contrast: Self.storedNumericValue(defaults.object(forKey: Keys.themeContrast)).map { CGFloat($0) } ?? 1
        ).contrast
        iconSet = IconSet(storedValue: defaults.string(forKey: Keys.iconSet))
        // 有意**不**进上面的 register：缺键即 false = 老用户维持关。
        // 全新安装那一次由 `seedWindowLiftEnabledForFreshInstall()` 显式写成 true——
        // register 一个 true 会把**所有**从没碰过这个开关的老用户一并打开，而这个功能
        // 会改写别人应用的窗口尺寸，不能靠一次升级静默生效。
        windowLiftEnabled = defaults.bool(forKey: Keys.windowLiftEnabled)
        // 同样有意不进 register：缺键即 false = 还没订阅过。
        // 同上：缺键即 false = 还没看过欢迎引导。
        hasSeenWelcome = defaults.bool(forKey: Keys.hasSeenWelcome)
        fullscreenIntentEnabled = defaults.bool(forKey: Keys.fullscreenIntentEnabled)
        // 有意不 register：缺键即 nil = 默认 ⌥⇧⌘D；坏数据（手改过、类型不对）也回落 nil。
        edgeToggleShortcut = Self.storedHotKeyShortcut(defaults.dictionary(forKey: Keys.edgeToggleShortcut))
        // 同样有意不 register：缺键即 false 正好是「默认关」，注册个 false 会让人误读成默认开。
        scrollReverserEnabled = defaults.bool(forKey: Keys.scrollReverserEnabled)
        // Read only, never written back here: a missing key keeps meaning "follow the system".
        appearanceMode = AppearanceMode(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .default
        // 有意不 register：缺键即 followMouse = 现状行为，老用户升级无感。
        let pinnedSelection = Self.storedPinnedScreenSelection(
            defaults.dictionary(forKey: Keys.taskbarScreenPinned)
        )
        switch defaults.string(forKey: Keys.taskbarScreenMode) {
        case nil, TaskbarScreenMode.followMouse.rawValue:
            taskbarScreenPlacement = .followMouse
        case TaskbarScreenMode.allScreens.rawValue:
            taskbarScreenPlacement = .allScreens
        case TaskbarScreenMode.allScreensPerDisplay.rawValue:
            taskbarScreenPlacement = .allScreensPerDisplay
        case TaskbarScreenMode.pinned.rawValue:
            if let pinnedSelection {
                taskbarScreenPlacement = .pinned(pinnedSelection)
            } else {
                // pinned 但选择缺失/坏 → 回退并立刻重写 mode 键（对齐 dockPanelHeight 的坏值即重写惯例）。
                taskbarScreenPlacement = .followMouse
                defaults.set(TaskbarScreenMode.followMouse.rawValue, forKey: Keys.taskbarScreenMode)
            }
        default:
            // 未知字符串（将来版本的新档被老版本读到）→ 按 followMouse 跑但**不重写键**，
            // 降级不毁掉用户在新版本里做的选择。
            taskbarScreenPlacement = .followMouse
        }
        // Bar height: the new key wins; a user upgrading from the four-tier releases carries only
        // the legacy `dockSize` string, which is mapped once (the legacy key is read here and
        // never written or removed, so a rollback still finds it). Corrupt values fall back to
        // the native height and are rewritten immediately, like every other key here.
        dockPanelHeight = Self.storedDockPanelHeight(defaults: defaults)
        hoverStyle = HoverStyle(rawValue: defaults.string(forKey: Keys.hoverStyle) ?? "") ?? .default
        let nativeDelay = Self.sanitizedStoredDelay(
            defaults.object(forKey: Keys.nativeDockAutoHideDelay),
            fallback: Self.defaultNativeDockAutoHideDelay
        )
        nativeDockAutoHideDelay = nativeDelay
        if nativeDelay == Self.neverHideDelay {
            lastEnabledNativeDockAutoHideDelay = Self.sanitizedLastEnabledDelay(
                Self.storedNumericValue(defaults.object(forKey: Keys.nativeDockAutoHideLastEnabledDelay)),
                fallback: Self.defaultNativeDockAutoHideDelay
            )
        } else {
            lastEnabledNativeDockAutoHideDelay = nativeDelay
        }
        let edgeDelay = Self.sanitizedStoredDelay(
            defaults.object(forKey: Keys.edgeAutoHideDelay),
            fallback: Self.defaultEnabledEdgeAutoHideDelay
        )
        edgeAutoHideDelay = edgeDelay
        if edgeDelay == Self.neverHideDelay {
            lastEnabledEdgeAutoHideDelay = Self.sanitizedLastEnabledDelay(
                Self.storedNumericValue(defaults.object(forKey: Keys.edgeAutoHideLastEnabledDelay)),
                fallback: Self.defaultEnabledEdgeAutoHideDelay
            )
        } else {
            lastEnabledEdgeAutoHideDelay = edgeDelay
        }
        defaults.set(Double(dockPanelHeight.points), forKey: Keys.dockPanelHeight)
        defaults.set(hoverStyle.rawValue, forKey: Keys.hoverStyle)
        defaults.set(nativeDelay, forKey: Keys.nativeDockAutoHideDelay)
        defaults.set(lastEnabledNativeDockAutoHideDelay, forKey: Keys.nativeDockAutoHideLastEnabledDelay)
        defaults.set(edgeDelay, forKey: Keys.edgeAutoHideDelay)
        defaults.set(lastEnabledEdgeAutoHideDelay, forKey: Keys.edgeAutoHideLastEnabledDelay)
    }

    /// Called on every accepted tick of a height drag (the drag decision already dedupes to
    /// whole points, so a tick that changes nothing never reaches the publisher or the disk).
    func setDockPanelHeight(_ value: DockPanelHeight) {
        guard dockPanelHeight != value else { return }
        dockPanelHeight = value
        defaults.set(Double(value.points), forKey: Keys.dockPanelHeight)
    }

    func setBarLayoutMode(_ value: BarLayoutMode) {
        guard barLayoutMode != value else { return }
        barLayoutMode = value
        defaults.set(value.rawValue, forKey: Keys.barLayoutMode)
    }

    func setCenteredWidth(_ value: CGFloat) {
        let clamped = min(max(value, Self.minimumCenteredWidth), Self.maximumCenteredWidth)
        guard centeredWidth != clamped else { return }
        centeredWidth = clamped
        defaults.set(Double(clamped), forKey: Keys.centeredWidth)
    }

    func setIslandGap(_ value: CGFloat) {
        let clamped = max(Self.minimumIslandGap, value)
        guard islandGap != clamped else { return }
        islandGap = clamped
        defaults.set(Double(clamped), forKey: Keys.islandGap)
    }

    func setIslandMargin(_ value: CGFloat) {
        let clamped = max(Self.minimumIslandMargin, value)
        guard islandMargin != clamped else { return }
        islandMargin = clamped
        defaults.set(Double(clamped), forKey: Keys.islandMargin)
    }

    func setBottomGap(_ value: CGFloat) {
        let clamped = Self.clampedBottomGap(value)
        guard bottomGap != clamped else { return }
        bottomGap = clamped
        defaults.set(Double(clamped), forKey: Keys.bottomGap)
    }

    /// Non-finite → floating default; otherwise rounded to whole points and clamped 0...12.
    static func clampedBottomGap(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return PanelLayoutMetrics.floatingBottomGap }
        let range = PanelLayoutMetrics.bottomGapRange
        return min(max(value.rounded(), range.lowerBound), range.upperBound)
    }

    func setEdgeConflictPolicy(_ value: EdgeConflictPolicy) {
        guard edgeConflictPolicy != value else { return }
        edgeConflictPolicy = value
        defaults.set(value.rawValue, forKey: EdgeConflictPolicy.defaultsKey)
    }

    func setEdgeBarPreset(_ value: EdgeBarPreset) {
        guard edgeBarPreset != value else { return }
        // First time into Custom: start from what is on screen now, so "Customize" never begins empty.
        if value == .custom, edgeCustomPlacements.isEmpty {
            let current = EdgeBarComposition.placements(
                preset: edgeBarPreset, primary: edgePrimarySide, widgets: widgetTiles, productivity: productivityItems, custom: [:]
            )
            setEdgeCustomPlacements(Dictionary(uniqueKeysWithValues: EdgeItem.allCases.map { ($0, current[$0] ?? .hidden) }))
        }
        edgeBarPreset = value
        defaults.set(value.rawValue, forKey: Keys.edgePreset)
    }

    func setEdgePrimarySide(_ value: EdgeSide) {
        guard edgePrimarySide != value else { return }
        edgePrimarySide = value
        defaults.set(value.rawValue, forKey: Keys.edgePrimarySide)
    }

    func setProductivityItem(_ item: ProductivityItem, enabled: Bool) {
        let next = ProductivityItem.allCases.filter { $0 == item ? enabled : productivityItems.contains($0) }
        guard next != productivityItems else { return }
        productivityItems = next
        defaults.set(ProductivityItem.serialize(next), forKey: Keys.productivityItems)
    }

    /// Where an item sits in the Custom layout (an item not yet stored shows where Productivity + Rest puts it).
    func edgePlacement(of item: EdgeItem) -> EdgePlacement {
        EdgeBarComposition.placements(preset: .custom, primary: edgePrimarySide, widgets: [], productivity: [],
                                      custom: edgeCustomPlacements)[item] ?? .hidden
    }

    func setEdgePlacement(_ place: EdgePlacement, of item: EdgeItem) {
        var next = EdgeBarComposition.placements(preset: .custom, primary: edgePrimarySide, widgets: [], productivity: [],
                                                 custom: edgeCustomPlacements)
        next[item] = place
        setEdgeCustomPlacements(next)
    }

    private func setEdgeCustomPlacements(_ value: [EdgeItem: EdgePlacement]) {
        guard edgeCustomPlacements != value else { return }
        edgeCustomPlacements = value
        defaults.set(EdgeItem.serialize(value), forKey: Keys.edgeCustom)
    }

    func deckScale(for side: EdgeSide) -> Double { side == .left ? deckScaleLeft : deckScaleRight }

    func setDeckScale(_ value: Double, for side: EdgeSide) {
        let v = DeckSettingsRules.clampedScale(value)
        switch side {
        case .left:
            guard deckScaleLeft != v else { return }
            deckScaleLeft = v
            defaults.set(v, forKey: Keys.deckScaleLeft)
        case .right:
            guard deckScaleRight != v else { return }
            deckScaleRight = v
            defaults.set(v, forKey: Keys.deckScaleRight)
        }
    }

    func setLauncherSearchPosition(_ value: LauncherSearchPosition) {
        guard launcherSearchPosition != value else { return }
        launcherSearchPosition = value
        defaults.set(value.rawValue, forKey: Keys.launcherSearchPosition)
    }

    func setControlCenterToggle(_ id: QuickToggleID, enabled: Bool) {
        var next = controlCenterToggles.filter { $0 != id }
        if enabled {
            // Keep catalog order so toggling never reshuffles the grid.
            next = QuickToggleID.defaultOrder.filter { $0 == id || next.contains($0) }
        }
        guard next != controlCenterToggles else { return }
        controlCenterToggles = next
        defaults.set(QuickToggleID.serialize(next), forKey: Keys.controlCenterToggles)
    }

    func setControlCenterWidget(_ kind: TileKind, enabled: Bool) {
        var next = controlCenterWidgets.filter { $0 != kind }
        if enabled {
            next = TileKind.controlCenterDefault.filter { $0 == kind || next.contains($0) }
        }
        guard next != controlCenterWidgets else { return }
        controlCenterWidgets = next
        defaults.set(TileKind.serialize(next), forKey: Keys.controlCenterWidgets)
    }

    func setControlCenterSize(_ value: ControlCenterSize) {
        guard controlCenterSize != value else { return }
        controlCenterSize = value
        defaults.set(value.rawValue, forKey: Keys.controlCenterSize)
    }

    func setControlCenterAnchor(_ value: ControlCenterAnchor) {
        guard controlCenterAnchor != value else { return }
        controlCenterAnchor = value
        defaults.set(value.rawValue, forKey: Keys.controlCenterAnchor)
    }

    func setControlCenterAnimation(_ value: ControlCenterAnimation) {
        guard controlCenterAnimation != value else { return }
        controlCenterAnimation = value
        defaults.set(value.rawValue, forKey: Keys.controlCenterAnimation)
    }

    func setShortcut(_ action: ShortcutAction, _ trigger: ShortcutTrigger) {
        guard shortcutBindings[action] != trigger else { return }
        shortcutBindings[action] = trigger
        defaults.set(trigger.serialized, forKey: Keys.shortcut(action))
    }

    func setLauncherTheme(_ value: LauncherTheme) {
        guard launcherTheme != value else { return }
        launcherTheme = value
        defaults.set(value.rawValue, forKey: Keys.launcherTheme)
    }

    func setLauncherTint(_ value: LauncherTint) {
        guard launcherTint != value else { return }
        launcherTint = value
        defaults.set(value.rawValue, forKey: Keys.launcherTint)
    }

    func setLauncherIcon(_ value: LauncherIconStyle) {
        guard launcherIcon != value else { return }
        launcherIcon = value
        defaults.set(value.rawValue, forKey: Keys.launcherIcon)
    }

    func setLauncherPinch(_ value: Bool) {
        guard launcherPinch != value else { return }
        launcherPinch = value
        defaults.set(value, forKey: Keys.launcherPinch)
    }

    func setLauncherScrollDirection(_ value: LauncherScrollDirection) {
        guard launcherScrollDirection != value else { return }
        launcherScrollDirection = value
        defaults.set(value.rawValue, forKey: Keys.launcherScroll)
    }

    func setDeckMagnify(_ value: Bool) {
        guard deckMagnify != value else { return }
        deckMagnify = value
        defaults.set(value, forKey: Keys.deckMagnify)
    }

    func setDeckKeepOpen(_ value: Bool) {
        guard deckKeepOpen != value else { return }
        deckKeepOpen = value
        defaults.set(value, forKey: Keys.deckKeepOpen)
    }

    func setDeckOpenOnHover(_ value: Bool) {
        guard deckOpenOnHover != value else { return }
        deckOpenOnHover = value
        defaults.set(value, forKey: Keys.deckOpenOnHover)
    }

    func setDeckTabPreview(_ value: Bool) {
        guard deckTabPreview != value else { return }
        deckTabPreview = value
        defaults.set(value, forKey: Keys.deckTabPreview)
    }

    func setEdgePrefs(_ value: EdgeBarPrefs) {
        let v = value.clamped()
        guard edgePrefs != v else { return }
        edgePrefs = v
        v.save(defaults)
    }

    func setEdgeTileStyle(_ value: EdgeTileStyle) {
        guard edgeTileStyle != value else { return }
        edgeTileStyle = value
        defaults.set(value.rawValue, forKey: Keys.edgeTileStyle)
    }

    func setDeckTabFont(_ value: String) {
        guard deckTabFont != value else { return }
        deckTabFont = value
        defaults.set(value, forKey: Keys.deckTabFont)
    }

    func deckYRatio(for side: EdgeSide) -> Double { side == .left ? deckYRatioLeft : deckYRatioRight }

    func setDeckYRatio(_ value: Double, for side: EdgeSide) {
        let v = DeckSettingsRules.clampedRatio(value)
        switch side {
        case .left:
            guard deckYRatioLeft != v else { return }
            deckYRatioLeft = v
            defaults.set(v, forKey: Keys.deckYRatioLeft)
        case .right:
            guard deckYRatioRight != v else { return }
            deckYRatioRight = v
            defaults.set(v, forKey: Keys.deckYRatioRight)
        }
    }

    func setWidgetTile(_ tile: WidgetTile, enabled: Bool) {
        var next = widgetTiles.filter { $0 != tile }
        if enabled {
            // Keep catalog order so toggling never reshuffles the bar.
            next = WidgetTile.allCases.filter { $0 == tile || next.contains($0) }
        }
        guard next != widgetTiles else { return }
        widgetTiles = next
        defaults.set(WidgetTile.serialize(next), forKey: Keys.widgetTiles)
    }

    func setNotesSyncEnabled(_ value: Bool) {
        guard notesSyncEnabled != value else { return }
        notesSyncEnabled = value
        defaults.set(value, forKey: Keys.notesSync)
    }

    func setEdgeGap(_ value: CGFloat) {
        let clamped = Self.clampedEdgeSpacing(Double(value), fallback: PanelGeometry.edgeBarDefaultBottomGap)
        guard edgeGap != clamped else { return }
        edgeGap = clamped
        defaults.set(Double(clamped), forKey: Keys.edgeGap)
    }

    func setEdgeMargin(_ value: CGFloat) {
        let clamped = Self.clampedEdgeSpacing(Double(value), fallback: 8)
        guard edgeMargin != clamped else { return }
        edgeMargin = clamped
        defaults.set(Double(clamped), forKey: Keys.edgeMargin)
    }

    /// Missing / non-finite → fallback; otherwise floored at the 0.5 pt edge minimum.
    static func clampedEdgeSpacing(_ value: Double?, fallback: CGFloat) -> CGFloat {
        guard let value, value.isFinite else { return fallback }
        return max(PanelGeometry.edgeBarMinimumSpacing, CGFloat(value))
    }

    /// Sides that currently host an edge bar, from the preset and the status side.
    var edgeActiveSides: Set<EdgeSide> {
        Set(edgeContent.keys)
    }

    /// Same resolution straight from stored defaults, for panels that don't hold the store.
    static func edgeContent(defaults: UserDefaults) -> [EdgeSide: [EdgeBarContent]] {
        func stored(_ key: String, _ fallback: String) -> String { defaults.string(forKey: key) ?? fallback }
        let composed = EdgeBarComposition.resolve(
            preset: EdgeBarPreset(rawValue: stored(Keys.edgePreset, "")) ?? .default,
            primary: EdgeSide(rawValue: stored(Keys.edgePrimarySide, "")) ?? .right,
            widgets: WidgetTile.parse(stored(Keys.widgetTiles, WidgetTile.serialize(WidgetTile.allCases))),
            productivity: ProductivityItem.parse(stored(Keys.productivityItems, ProductivityItem.serialize(ProductivityItem.allCases))),
            custom: EdgeItem.parsePlacements(defaults.string(forKey: Keys.edgeCustom)))
        let dock = (StripPlacementMap.decode(defaults.data(forKey: StripPlacementMap.defaultsKey)) ?? StripPlacementMap()).global
        let policy = EdgeConflictPolicy(rawValue: defaults.string(forKey: EdgeConflictPolicy.defaultsKey) ?? "") ?? .moveAcross
        return EdgeOccupancy.resolve(composed, dock: dock, policy: policy)
    }

    /// Per-edge content for the current preset / custom layout, then made room for a dock rail (18g).
    var edgeContent: [EdgeSide: [EdgeBarContent]] {
        EdgeOccupancy.resolve(
            EdgeBarComposition.resolve(preset: edgeBarPreset, primary: edgePrimarySide, widgets: widgetTiles,
                                       productivity: productivityItems, custom: edgeCustomPlacements),
            dock: stripPlacementMap.global, policy: edgeConflictPolicy)
    }

    /// Live panel geometry: the height-derived metrics plus the user's bottom gap.
    var layoutMetrics: PanelLayoutMetrics { dockPanelHeight.metrics(bottomGap: bottomGap) }

    /// 只应由 `SettingsCoordinator.applyEdgeToggleShortcut` 在**注册成功后**调用（见属性注释）。
    func setEdgeToggleShortcut(_ value: StoredHotKeyShortcut?) {
        guard edgeToggleShortcut != value else { return }
        edgeToggleShortcut = value
        guard let value else {
            defaults.removeObject(forKey: Keys.edgeToggleShortcut)
            return
        }
        defaults.set(
            [
                "keyCode": Int(value.keyCode),
                "modifiers": Int(value.carbonModifiers),
                "glyphs": value.glyphs,
            ],
            forKey: Keys.edgeToggleShortcut
        )
    }

    func setAppearanceMode(_ value: AppearanceMode) {
        guard appearanceMode != value else { return }
        appearanceMode = value
        defaults.set(value.rawValue, forKey: Keys.appearance)
    }

    func setIconSet(_ value: IconSet) {
        guard iconSet != value else { return }
        iconSet = value
        defaults.set(value.rawValue, forKey: Keys.iconSet)
    }

    func setThemeMaterial(_ value: DockThemeStyle) {
        guard themeMaterial != value else { return }
        themeMaterial = value
        defaults.set(value.token, forKey: Keys.themeMaterial)
    }

    func setThemeVibrancy(_ value: CGFloat) {
        let clamped = ThemeTuning.resolved(vibrancy: value, contrast: themeContrast).vibrancy
        guard themeVibrancy != clamped else { return }
        themeVibrancy = clamped
        defaults.set(Double(clamped), forKey: Keys.themeVibrancy)
    }

    func setThemeContrast(_ value: CGFloat) {
        let clamped = ThemeTuning.resolved(vibrancy: themeVibrancy, contrast: value).contrast
        guard themeContrast != clamped else { return }
        themeContrast = clamped
        defaults.set(Double(clamped), forKey: Keys.themeContrast)
    }

    /// What the themed surfaces read, one value for the environment (`\.themeTuning`).
    var themeTuning: ThemeTuning {
        ThemeTuning.resolved(vibrancy: themeVibrancy, contrast: themeContrast)
    }

    func setScrollReverserEnabled(_ value: Bool) {
        guard scrollReverserEnabled != value else { return }
        scrollReverserEnabled = value
        defaults.set(value, forKey: Keys.scrollReverserEnabled)
    }

    func setTaskbarScreenPlacement(_ value: TaskbarScreenPlacement) {
        consumeTaskbarPerDisplaySeedIfPresent()
        guard taskbarScreenPlacement != value else { return }
        taskbarScreenPlacement = value
        defaults.set(value.mode.rawValue, forKey: Keys.taskbarScreenMode)
        if let selection = value.pinnedSelection {
            defaults.set(
                ["uuid": selection.uuid, "name": selection.name],
                forKey: Keys.taskbarScreenPinned
            )
        }
        // 切回 followMouse 时**保留** pinned 字典不删（remembered 惯例，
        // 同 lastEnabledEdgeAutoHideDelay 的精神：再切回固定档时还记得上次选的屏）。
    }

    /// Only a genuinely fresh install may arm this; the store's own init never creates the key.
    func armTaskbarPerDisplaySeedForFreshInstall(lineage: InstallLineage) {
        guard lineage == .pristine,
              defaults.object(forKey: Keys.taskbarScreenPerDisplaySeedPending) == nil
        else { return }
        defaults.set(true, forKey: Keys.taskbarScreenPerDisplaySeedPending)
    }

    func applyTaskbarPerDisplaySeed() {
        setTaskbarScreenPlacement(.allScreensPerDisplay)
    }

    func consumeTaskbarPerDisplaySeedIfPresent() {
        guard defaults.object(forKey: Keys.taskbarScreenPerDisplaySeedPending) != nil,
              defaults.bool(forKey: Keys.taskbarScreenPerDisplaySeedPending)
        else { return }
        defaults.set(false, forKey: Keys.taskbarScreenPerDisplaySeedPending)
    }

    private static func storedPinnedScreenSelection(_ dict: [String: Any]?) -> PinnedScreenSelection? {
        guard let dict,
              let uuid = dict["uuid"] as? String, !uuid.isEmpty,
              let name = dict["name"] as? String
        else { return nil }
        return PinnedScreenSelection(uuid: uuid, name: name)
    }

    private static func storedHotKeyShortcut(_ dict: [String: Any]?) -> StoredHotKeyShortcut? {
        guard let dict,
              let keyCode = dict["keyCode"] as? Int, keyCode >= 0, keyCode <= 0xFFFF,
              let modifiers = dict["modifiers"] as? Int, modifiers >= 0,
              let glyphs = dict["glyphs"] as? String, !glyphs.isEmpty
        else { return nil }
        return StoredHotKeyShortcut(
            keyCode: UInt32(keyCode),
            carbonModifiers: UInt32(modifiers),
            glyphs: glyphs
        )
    }

    func setHoverStyle(_ value: HoverStyle) {
        guard hoverStyle != value else { return }
        hoverStyle = value
        defaults.set(value.rawValue, forKey: Keys.hoverStyle)
    }

    func setDrawerPlacement(_ value: DrawerPlacement) {
        guard drawerPlacement != value else { return }
        drawerPlacement = value
        defaults.set(value.rawValue, forKey: Keys.drawerPlacement)
    }

    func setShowShelf(_ value: Bool) {
        guard showShelf != value else { return }
        showShelf = value
        defaults.set(value, forKey: Keys.showShelf)
    }

    func setDockIslandEnabled(_ value: Bool) {
        guard dockIslandEnabled != value else { return }
        dockIslandEnabled = value
        defaults.set(value, forKey: Keys.dockIslandEnabled)
    }

    func setNotchIslandEnabled(_ value: Bool) {
        guard notchIslandEnabled != value else { return }
        notchIslandEnabled = value
        defaults.set(value, forKey: Keys.notchIslandEnabled)
    }

    static let chipPreviewDelayChoices = [150, 350, 600]
    static let chipPreviewSizeChoices = [140, 180, 240]

    func setChipPreviewEnabled(_ value: Bool) {
        guard chipPreviewEnabled != value else { return }
        chipPreviewEnabled = value
        defaults.set(value, forKey: Keys.chipPreviewEnabled)
    }

    func setChipPreviewDelayMs(_ value: Int) {
        guard Self.chipPreviewDelayChoices.contains(value), chipPreviewDelayMs != value else { return }
        chipPreviewDelayMs = value
        defaults.set(value, forKey: Keys.chipPreviewDelayMs)
    }

    func setChipPreviewThumbWidth(_ value: Int) {
        guard Self.chipPreviewSizeChoices.contains(value), chipPreviewThumbWidth != value else { return }
        chipPreviewThumbWidth = value
        defaults.set(value, forKey: Keys.chipPreviewThumbWidth)
    }

    func setShowAllRunningApps(_ value: Bool) {
        guard showAllRunningApps != value else { return }
        showAllRunningApps = value
        defaults.set(value, forKey: Keys.showAllRunningApps)
    }

    func setHyperkeyEnabled(_ value: Bool) {
        guard hyperkeyEnabled != value else { return }
        hyperkeyEnabled = value
        defaults.set(value, forKey: Keys.hyperkeyEnabled)
    }

    func setChipClassicMenu(_ value: Bool) {
        guard chipClassicMenu != value else { return }
        chipClassicMenu = value
        defaults.set(value, forKey: Keys.chipClassicMenu)
    }

    func setChipGroupingDefault(_ value: WindowChipGroupPolicy) {
        guard chipGroupingPlan.defaultPolicy != value else { return }
        chipGroupingPlan.defaultPolicy = value
        defaults.set(value.rawValue, forKey: Keys.chipGroupingDefault)
    }

    /// `nil` removes the override (the app follows the default again).
    func setChipGrouping(_ policy: WindowChipGroupPolicy?, forBundleID bundleID: String) {
        var plan = chipGroupingPlan
        plan.overrides[bundleID] = policy
        guard plan != chipGroupingPlan else { return }
        chipGroupingPlan = plan
        defaults.set(plan.overrides.mapValues(\.rawValue), forKey: Keys.chipGroupingOverrides)
    }

    func setShelfShakeEnabled(_ value: Bool) {
        guard shelfShakeEnabled != value else { return }
        shelfShakeEnabled = value
        defaults.set(value, forKey: ShelfStore.shakeKey)
    }

    func setShelfAutoExpire(_ value: Bool) {
        guard shelfAutoExpire != value else { return }
        shelfAutoExpire = value
        defaults.set(value, forKey: ShelfStore.autoExpireKey)
    }

    func setShelfExpiryDays(_ value: Int) {
        guard ShelfPolicy.expiryChoices.contains(value), shelfExpiryDays != value else { return }
        shelfExpiryDays = value
        defaults.set(value, forKey: ShelfStore.expiryDaysKey)
    }

    func setShelfStorage(_ value: ShelfStorage) {
        guard shelfStorage != value else { return }
        shelfStorage = value
        defaults.set(value.rawValue, forKey: ShelfStore.storageKey)
    }

    func setNotchSkin(_ value: LiveIslandSkin) {
        guard notchSkin != value else { return }
        notchSkin = value
        defaults.set(value.rawValue, forKey: Keys.notchSkin)
    }

    func setLiveEventOSBanners(_ value: Bool) {
        guard liveEventOSBanners != value else { return }
        liveEventOSBanners = value
        defaults.set(value, forKey: Keys.liveEventOSBanners)
    }

    func setContextPresetsEnabled(_ value: Bool) {
        guard contextPresetsEnabled != value else { return }
        contextPresetsEnabled = value
        defaults.set(value, forKey: ContextPresetRules.enabledKey)
    }

    func setContextWorkPreset(_ id: String) {
        contextWorkPresetID = id
        defaults.set(id, forKey: Keys.contextWorkPreset)
    }

    func setContextEveningPreset(_ id: String) {
        contextEveningPresetID = id
        defaults.set(id, forKey: Keys.contextEveningPreset)
    }

    func setTintSurfacesByPhase(_ value: Bool) {
        guard tintSurfacesByPhase != value else { return }
        tintSurfacesByPhase = value
        defaults.set(value, forKey: Keys.tintByPhase)
    }

    func setWallpaperEnabled(_ value: Bool) {
        guard wallpaperEnabled != value else { return }
        wallpaperEnabled = value
        defaults.set(value, forKey: Keys.wallpaperEnabled)
    }

    func setWallpaperMode(_ value: WallpaperMode) {
        wallpaperMode = value.rawValue
        defaults.set(value.rawValue, forKey: Keys.wallpaperMode)
    }

    func setWallpaperFolder(_ path: String) {
        wallpaperFolder = path
        defaults.set(path, forKey: Keys.wallpaperFolder)
    }

    func setLinkCleanerEnabled(_ value: Bool) {
        guard linkCleanerEnabled != value else { return }
        linkCleanerEnabled = value
        defaults.set(value, forKey: Keys.linkCleanerEnabled)
    }

    func setLiveEventRoute(_ value: LiveEventRoute) {
        guard liveEventRoute != value else { return }
        liveEventRoute = value
        defaults.set(value.rawValue, forKey: Keys.liveEventRoute)
    }

    func setShowTrash(_ value: Bool) {
        guard showTrash != value else { return }
        showTrash = value
        defaults.set(value, forKey: Keys.showTrash)
    }

    /// Seeds "lift maximized windows clear of the taskbar" to on for a fresh install (owner 2026-09-01).
    ///
    /// **Only `AppDelegate` may call this, once.** The verdict is `InstallLineage`: a snapshot of the
    /// persistent domain taken at the very start of the process, where an empty domain means a fresh
    /// install. ⚠️ What is load-bearing is *where* that snapshot is taken — `AppDelegate.installLineage`
    /// must be that type's **first stored property**, because this store and its siblings write defaults
    /// inside their own inits, so a snapshot taken one step later is guaranteed to be non-empty. This has
    /// **nothing** to do with the ordering against `recordFirstLaunchIfNeeded()`; that was the old,
    /// now-retired verdict.
    ///
    /// Getting the order wrong fails in the safe direction: a non-empty domain reads as `.priorUse` and
    /// nothing is seeded, so the feature goes silently dead for fresh installs rather than flipping an
    /// existing user. That is why there is **no assertion** here — 71 tests construct this type directly,
    /// and a process-level assert would abort the whole test run on the first one.
    ///
    /// An existing key means the user chose, even if they chose off: always respected, never overwritten.
    func seedWindowLiftEnabledForFreshInstall(lineage: InstallLineage) {
        guard lineage == .pristine else { return }
        guard defaults.object(forKey: Keys.windowLiftEnabled) == nil else { return }
        setWindowLiftEnabled(true)
    }

    func setWindowLiftEnabled(_ value: Bool) {
        guard windowLiftEnabled != value else { return }
        windowLiftEnabled = value
        defaults.set(value, forKey: Keys.windowLiftEnabled)
    }

    func setHasSeenWelcome(_ value: Bool) {
        guard hasSeenWelcome != value else { return }
        hasSeenWelcome = value
        defaults.set(value, forKey: Keys.hasSeenWelcome)
    }

    func setFullscreenIntentEnabled(_ value: Bool) {
        guard fullscreenIntentEnabled != value else { return }
        fullscreenIntentEnabled = value
        defaults.set(value, forKey: Keys.fullscreenIntentEnabled)
    }

    func setLaunchAtLogin(_ value: Bool) {
        guard launchAtLogin != value else { return }
        launchAtLogin = value
        defaults.set(value, forKey: Keys.launchAtLogin)
    }

    func setNativeDockAutoHideDelay(_ value: Double) {
        guard value.isFinite else { return }
        let snapped = Self.snapDelay(value, fallbackForNonFinite: Self.defaultNativeDockAutoHideDelay)
        // remembered 同步先于 active 去重：active 未变时也要修正 remembered。
        if snapped != Self.neverHideDelay, lastEnabledNativeDockAutoHideDelay != snapped {
            lastEnabledNativeDockAutoHideDelay = snapped
            defaults.set(snapped, forKey: Keys.nativeDockAutoHideLastEnabledDelay)
        }
        guard nativeDockAutoHideDelay != snapped else { return }
        nativeDockAutoHideDelay = snapped
        defaults.set(snapped, forKey: Keys.nativeDockAutoHideDelay)
    }

    // 系统 Dock 组刻意不提供盲翻的 toggle 方法：系统状态可被外部改（⌥⌘D / 系统设置），
    // 盲翻本地存值会在两者脱节时翻错方向。菜单里的显隐命令已于 2026-08-01 删除，
    // 整组改由滑块 + 确认行表达，翻转这件事交还给系统自己的 ⌥⌘D。
    //
    // 因此 `lastEnabledNativeDockAutoHideDelay` 目前**没有读取方**（原先只有那条命令用它来
    // 恢复「上次的档」）：滑块自己带着位置，不需要记忆。字段与持久化保留——它是用户数据，
    // 删键属于有损迁移，且命令一旦回归就还要用。不是漏读。

    func setEdgeAutoHideDelay(_ value: Double) {
        guard value.isFinite else { return }
        let snapped = Self.snapDelay(value, fallbackForNonFinite: Self.defaultEnabledEdgeAutoHideDelay)
        // remembered 同步先于 active 去重：active 未变时也要修正 remembered。
        if snapped != Self.neverHideDelay, lastEnabledEdgeAutoHideDelay != snapped {
            lastEnabledEdgeAutoHideDelay = snapped
            defaults.set(snapped, forKey: Keys.edgeAutoHideLastEnabledDelay)
        }
        guard edgeAutoHideDelay != snapped else { return }
        edgeAutoHideDelay = snapped
        defaults.set(snapped, forKey: Keys.edgeAutoHideDelay)
    }

    /// 钨极的「自动隐藏」切换：常驻 ⇄ 上一次的延迟（含不唤醒 999）。
    /// 命名避免 "Now"——切到自动隐藏侧不是立即隐藏，仍走原空闲计时与鼠标判定。
    func toggleEdgeAutoHideMode() {
        if edgeAutoHideDelay == Self.neverHideDelay {
            setEdgeAutoHideDelay(lastEnabledEdgeAutoHideDelay)
        } else {
            setEdgeAutoHideDelay(Self.neverHideDelay)
        }
    }

    static func delayFromSliderIndex(_ index: Int) -> Double {
        let clamped = min(max(index, 0), sliderIndexMax)
        switch clamped {
        case 0:
            return neverHideDelay
        case sliderIndexMax:
            return neverWakeDelay
        case sliderIndexMax - 1:
            return finiteDelayMax
        default:
            return ((finiteDelayMin + Double(clamped - 1) * delayStep) * 10).rounded() / 10
        }
    }

    static func sliderIndexFromDelay(_ value: Double) -> Int {
        guard value > neverHideDelay else { return 0 }
        guard value < neverWakeDelay else { return sliderIndexMax }
        let clamped = min(max(value, finiteDelayMin), finiteDelayMax)
        return Int(((clamped - finiteDelayMin) / delayStep).rounded()) + 1
    }

    static func snapDelay(_ value: Double, fallbackForNonFinite fallback: Double = AppSettingsStore.defaultEnabledEdgeAutoHideDelay) -> Double {
        // NaN/±inf 穿透到下面的 Int(...) 转换会直接 crash（NaN 的比较全为 false，clamp 不生效）。
        guard value.isFinite else { return fallback }
        if value <= neverHideDelay { return neverHideDelay }
        if value >= neverWakeDelay { return neverWakeDelay }
        let clamped = min(max(value, finiteDelayMin), finiteDelayMax)
        return delayFromSliderIndex(Int(((clamped - finiteDelayMin) / delayStep).rounded()) + 1)
    }

    /// UserDefaults 的 active delay 读取入口。只接受真正的数值对象；字符串、布尔值和非有限值
    /// 都按该组默认档位回退，避免 `double(forKey:)` 把坏类型静默变成 0.0。
    static func sanitizedStoredDelay(_ value: Any?, fallback: Double) -> Double {
        guard let value = storedNumericValue(value) else { return fallback }
        return snapDelay(value, fallbackForNonFinite: fallback)
    }

    /// remembered 值的防御收口：缺失、类型错误、非有限、吸附后为常驻，一律回退默认档位
    /// （edge 组 0.1，系统 Dock 组 1.0）。
    static func sanitizedLastEnabledDelay(_ value: Double?, fallback: Double = AppSettingsStore.defaultEnabledEdgeAutoHideDelay) -> Double {
        guard let value, value.isFinite else { return fallback }
        let snapped = snapDelay(value, fallbackForNonFinite: fallback)
        return snapped == neverHideDelay ? fallback : snapped
    }

    private static func storedNumericValue(_ value: Any?) -> Double? {
        DefaultsValueParsing.finiteNumericValue(value)
    }
    
    /// The saved layout with widgets auto-degraded (L→M→S) to fit `screenWidth`; what the strip and solver use.
    func fittedWidgetLayout(screenWidth: CGFloat) -> WidgetLayout {
        widgetLayout.fitted(toBudget: WidgetLayout.widgetBudget(
            screenWidth: screenWidth, margin: islandMargin, gap: islandGap,
            tileStride: IslandLayoutSolver.tileStride(barHeight: dockPanelHeight.points),
            mode: barLayoutMode, order: widgetLayout.visibleOrder, barHeight: dockPanelHeight.points))
    }

    // MARK: Strip placement (Phase 18a)

    func stripPlacement(forDisplay displayUUID: String?) -> StripPlacement {
        stripPlacementMap.placement(forDisplay: displayUUID)
    }

    /// Global placement; per-display overrides are kept.
    func setStripPlacement(_ placement: StripPlacement) {
        guard stripPlacementMap.global != placement else { return }
        var map = stripPlacementMap
        map.global = placement
        setStripPlacementMap(map)
    }

    func setStripPlacement(_ placement: StripPlacement, forDisplay displayUUID: String) {
        setStripPlacementMap(stripPlacementMap.setting(placement, forDisplay: displayUUID))
    }

    private func setStripPlacementMap(_ map: StripPlacementMap) {
        guard stripPlacementMap != map else { return }
        stripPlacementMap = map
        defaults.set(map.encoded(), forKey: StripPlacementMap.defaultsKey)
    }

    // MARK: Dock styles (Phase 11e)

    /// The built-in style the live values equal, or `nil` (= Custom).
    var currentDockStyle: DockStyle? {
        DockStyle.matching(mode: barLayoutMode, barHeight: dockPanelHeight.points, gap: islandGap,
                           margin: islandMargin, bottomGap: bottomGap, placement: stripPlacementMap.global)
    }

    /// One write per setting; the style is first fitted to `screenWidth` so it never overflows.
    func applyDockStyle(_ style: DockStyle, screenWidth: CGFloat) {
        let fitted = DockStyleFit.resolve(style, screenWidth: screenWidth, widgetOrder: widgetLayout.visibleOrder)
        setBarLayoutMode(fitted.mode)
        setDockPanelHeight(DockPanelHeight(clamping: fitted.size.barHeight))
        setIslandGap(fitted.spacing.gap)
        setIslandMargin(fitted.spacing.margin)
        setBottomGap(fitted.bottomGap)
        setStripPlacement(fitted.placement)
        if let id = fitted.widgetPresetID, let preset = WidgetPresets.builtIns.first(where: { $0.id == id }) {
            applyWidgetPreset(preset)
        }
    }

    func setDockSpacing(_ spacing: DockSpacing) {
        setIslandGap(spacing.gap)
        setIslandMargin(spacing.margin)
    }

    func setWidgetLayout(_ layout: WidgetLayout) {
        widgetLayout = layout
        widgetOrder = layout.visibleOrder
        defaults.set(layout.encoded(), forKey: WidgetLayout.defaultsKey)
    }

    func saveCurrentWidgetLayout(as name: String) {
        userWidgetPresets = WidgetPresets.saving(widgetLayout, as: name, into: userWidgetPresets)
        defaults.set(WidgetPresets.encode(userWidgetPresets), forKey: WidgetPresets.defaultsKey)
    }

    func deleteWidgetPreset(id: String) {
        userWidgetPresets = WidgetPresets.removing(id: id, from: userWidgetPresets)
        defaults.set(WidgetPresets.encode(userWidgetPresets), forKey: WidgetPresets.defaultsKey)
    }

    /// One atomic write; exact-width overrides from the preset replace the current ones.
    func applyWidgetPreset(_ preset: WidgetPreset) {
        setWidgetLayout(preset.layout)
    }

    /// Picks an S/M/L preset and clears any width override so the preset takes effect. **This is the only
    /// path that sets a widget's width now** — the exact-width sliders and their `widgetWidths` key retired
    /// in Phase 40e, because a stored width silently overrode the chosen preset. `exactWidth` itself stays:
    /// the rail's own geometry sets it (`PanelGeometry.railWidgetLayout`).
    func setWidgetSize(_ size: WidgetSize, for section: BarSection) {
        setWidgetLayout(widgetLayout.updating(section) { $0.size = size; $0.exactWidth = nil })
    }

    private static func storedDockPanelHeight(defaults: UserDefaults) -> DockPanelHeight {
        if let stored = storedNumericValue(defaults.object(forKey: Keys.dockPanelHeight)) {
            return DockPanelHeight(clamping: CGFloat(stored))
        }
        if let legacy = defaults.string(forKey: Keys.dockSize),
           let migrated = DockPanelHeight.migratingLegacyTier(rawValue: legacy) {
            return migrated
        }
        return .default
    }

    private static func migrateLegacyEnabledKey(defaults: UserDefaults, enabledKey: String, delayKey: String) {
        if let storedEnabled = defaults.object(forKey: enabledKey) as? Bool, storedEnabled == false {
            defaults.set(neverHideDelay, forKey: delayKey)
        }
        defaults.removeObject(forKey: enabledKey)
    }

    /// Owner 2026-10-14: **hugging** (not floating) and **centred** (not split3) are the defaults,
    /// and an install that already saved one of them gets the new default too. A stamp makes this
    /// run exactly once, so a later deliberate change to either setting still sticks.
    private static func forceNewLayoutDefaults(defaults: UserDefaults) {
        guard defaults.object(forKey: Keys.huggingCentredDefaultsStamp) == nil else { return }
        defaults.removeObject(forKey: Keys.bottomGap)
        defaults.removeObject(forKey: Keys.barLayoutMode)
        defaults.set(true, forKey: Keys.huggingCentredDefaultsStamp)
    }
}

private enum Keys {
    static let launchAtLogin = "com.katikati.launchAtLogin"
    /// Read-once stamp for the hugging + centred default switch (see `forceNewLayoutDefaults`).
    static let huggingCentredDefaultsStamp = "com.katikati.migration.huggingCentredDefaults"
    static let drawerPlacement = "com.katikati.drawerPlacement"
    static let showShelf = "com.katikati.showShelf"
    // Never read the retired com.katikati.trash.visible key.
    static let showTrash = "com.katikati.showTrash"
    static let nowPlayingTheme = "com.katikati.nowPlayingTheme"
    static let dockIslandEnabled = "com.katikati.liveIsland.dock"
    static let notchIslandEnabled = "com.katikati.liveIsland.notch"
    static let notchSkin = "com.katikati.liveIsland.notchSkin"
    static let liveEventRoute = "com.katikati.liveIsland.eventRoute"
    static let liveEventOSBanners = "com.katikati.liveIsland.osBanners"
    static let chipPreviewEnabled = "com.katikati.chips.previewEnabled"
    static let chipPreviewDelayMs = "com.katikati.chips.previewDelayMs"
    static let chipPreviewThumbWidth = "com.katikati.chips.previewThumbWidth"
    static let showAllRunningApps = "com.katikati.strip.showAllRunningApps"
    static let hyperkeyEnabled = "com.katikati.hyperkey.enabled"
    static let chipClassicMenu = "com.katikati.chips.classicMenu"
    static let chipGroupingDefault = "com.katikati.chips.groupingDefault"
    static let chipGroupingOverrides = "com.katikati.chips.groupingOverrides"
    static let linkCleanerEnabled = "com.katikati.linkCleaner"
    static let wallpaperEnabled = "com.katikati.wallpaper.enabled"
    static let wallpaperMode = "com.katikati.wallpaper.mode"
    static let wallpaperFolder = "com.katikati.wallpaper.folder"
    static let tintByPhase = "com.katikati.theme.tintByPhase"
    static let contextWorkPreset = "com.katikati.widgets.contextPresets.work"
    static let contextEveningPreset = "com.katikati.widgets.contextPresets.evening"

    /// Continuous bar height in points (since the drag-to-resize release).
    static let dockPanelHeight = "com.katikati.dockPanelHeight"
    /// Legacy four-tier raw string. **Read once for migration, never written or removed.**
    static let dockSize = "com.katikati.dockSize"
    static let hoverStyle = "com.katikati.hoverStyle"
    /// system / light / dark. Missing key = system.
    /// The pre-glass `com.katikati.appearanceMode` is an orphan and stays one: never read,
    /// written or removed — a choice made for that older look is not carried over.
    static let appearance = "com.katikati.appearance"
    static let windowLiftEnabled = "com.katikati.windowLiftEnabled"
    static let fullscreenIntentEnabled = "com.katikati.fullscreenIntentEnabled"
    /// 自定义显隐快捷键（字典：keyCode / modifiers / glyphs）。缺键 = 默认 ⌥⇧⌘D。
    static let edgeToggleShortcut = "com.katikati.hotKey.edgeAutoHideMode"
    static let scrollReverserEnabled = "com.katikati.scrollReverserEnabled"
    /// 任务条显示位置（followMouse / pinned / allScreens / allScreensPerDisplay）。缺键 = followMouse。
    /// ⚠️ 旧的 `com.katikati.displayMode`（早期「单屏/多屏」档，已随功能删除）是孤儿键，
    /// **永不再读**（`Docs/05`）——新功能只认下面这两个键。
    static let taskbarScreenMode = "com.katikati.taskbarScreen.mode"
    /// 固定屏身份（字典：uuid / name）。切回 followMouse 时保留不删。
    static let taskbarScreenPinned = "com.katikati.taskbarScreen.pinned"
    /// A fresh install waiting to first see multiple displays. Missing key = existing user,
    /// false = already consumed.
    static let taskbarScreenPerDisplaySeedPending = "com.katikati.taskbarScreen.perDisplaySeedPending"
    /// ⚠️ 这个键名进了用户磁盘。改名 = 所有已订阅的人重新看到订阅区块。
    /// ⚠️ 同上：改名 = 所有老用户下次启动被欢迎引导再拦一次。
    static let hasSeenWelcome = "com.katikati.hasSeenWelcome"
    static let nativeDockAutoHideEnabled = "com.katikati.autoHide.nativeDock.enabled"
    static let nativeDockAutoHideDelay = "com.katikati.autoHide.nativeDock.delay"
    static let nativeDockAutoHideLastEnabledDelay = "com.katikati.autoHide.nativeDock.lastEnabledDelay"
    static let edgeAutoHideEnabled = "com.katikati.autoHide.edge.enabled"
    static let edgeAutoHideDelay = "com.katikati.autoHide.edge.delay"
    static let edgeAutoHideLastEnabledDelay = "com.katikati.autoHide.edge.lastEnabledDelay"
    static let barLayoutMode = "com.katikati.layout.mode"
    static let centeredWidth = "com.katikati.layout.centeredWidth"
    static let islandGap = "com.katikati.layout.islandGap"
    static let islandMargin = "com.katikati.layout.islandMargin"
    static let bottomGap = "com.katikati.layout.bottomGap"
    static let edgePreset = "com.katikati.edge.preset"
    static let edgePrimarySide = "com.katikati.edge.side"
    static let edgeCustom = "com.katikati.edge.custom"
    static let productivityItems = "com.katikati.productivity.items"
    static let edgeGap = "com.katikati.edge.gap"
    static let notesSync = "com.katikati.notes.sync"
    static let widgetTiles = "com.katikati.widgets.tiles"
    static let deckScale = "com.katikati.edge.deckScale"
    static let deckScaleLeft = "com.katikati.edge.deckScale.left"
    static let deckScaleRight = "com.katikati.edge.deckScale.right"
    static let deckMagnify = "com.katikati.edge.magnify"
    static let launcherScroll = "com.katikati.launcher.scroll"
    static let launcherPinch = "com.katikati.launcher.pinch"
    static let launcherTheme = "com.katikati.launcher.theme"
    static let launcherTint = "com.katikati.launcher.tint"
    static let launcherIcon = "com.katikati.launcher.icon"
    static let controlCenterToggles = "com.katikati.controlcenter.toggles"
    static let controlCenterWidgets = "com.katikati.controlcenter.widgets"
    static let controlCenterSize = "com.katikati.controlcenter.size"
    static let controlCenterAnchor = "com.katikati.controlcenter.anchor"
    static let controlCenterAnimation = "com.katikati.controlcenter.animation"
    static func shortcut(_ action: ShortcutAction) -> String { "com.katikati.shortcut.\(action.rawValue)" }
    static let launcherSearchPosition = "com.katikati.launcher.searchPosition"
    static let deckKeepOpen = "com.katikati.edge.alwaysShown"
    static let deckOpenOnHover = "com.katikati.edge.openOnHover"
    static let deckTabPreview = "com.katikati.edge.tabPreview"
    static let edgeTileStyle = "com.katikati.edge.tileStyle"
    static let deckTabFont = "com.katikati.edge.tabFont"
    static let deckYRatioLeft = "com.katikati.edge.yRatio.left"
    static let deckYRatioRight = "com.katikati.edge.yRatio.right"
    static let edgeMargin = "com.katikati.edge.margin"
    static let iconSet = "com.katikati.iconSet"
    static let themeMaterial = "com.katikati.theme.material"
    static let themeVibrancy = "com.katikati.theme.vibrancy"
    static let themeContrast = "com.katikati.theme.contrast"
}

/// One-way first-run migrator from legacy Tungsten Edge (`com.tungsten.edge.*`) defaults
/// to KatiKati (`com.katikati.*`) defaults with an install-lineage stamp.
enum TungstenDefaultsMigrator {
    static let migrationStampKey = "com.katikati.migration.tungstenLineageStamp"

    /// Pairs of (legacy tungsten key, new katikati key).
    static let keyMap: [(legacy: String, new: String)] = [
        ("com.tungsten.edge.launchAtLogin", "com.katikati.launchAtLogin"),
        ("com.tungsten.edge.showShelf", "com.katikati.showShelf"),
        ("com.tungsten.edge.showTrash", "com.katikati.showTrash"),
        ("com.tungsten.edge.dockPanelHeight", "com.katikati.dockPanelHeight"),
        ("com.tungsten.edge.dockSize", "com.katikati.dockSize"),
        ("com.tungsten.edge.hoverStyle", "com.katikati.hoverStyle"),
        ("com.tungsten.edge.appearance", "com.katikati.appearance"),
        ("com.tungsten.edge.windowLiftEnabled", "com.katikati.windowLiftEnabled"),
        ("com.tungsten.edge.fullscreenIntentEnabled", "com.katikati.fullscreenIntentEnabled"),
        ("com.tungsten.edge.hotKey.edgeAutoHideMode", "com.katikati.hotKey.edgeAutoHideMode"),
        ("com.tungsten.edge.scrollReverserEnabled", "com.katikati.scrollReverserEnabled"),
        ("com.tungsten.edge.taskbarScreen.mode", "com.katikati.taskbarScreen.mode"),
        ("com.tungsten.edge.taskbarScreen.pinned", "com.katikati.taskbarScreen.pinned"),
        ("com.tungsten.edge.taskbarScreen.perDisplaySeedPending", "com.katikati.taskbarScreen.perDisplaySeedPending"),
        ("com.tungsten.edge.hasSeenWelcome", "com.katikati.hasSeenWelcome"),
        ("com.tungsten.edge.autoHide.nativeDock.enabled", "com.katikati.autoHide.nativeDock.enabled"),
        ("com.tungsten.edge.autoHide.nativeDock.delay", "com.katikati.autoHide.nativeDock.delay"),
        ("com.tungsten.edge.autoHide.nativeDock.lastEnabledDelay", "com.katikati.autoHide.nativeDock.lastEnabledDelay"),
        ("com.tungsten.edge.autoHide.edge.enabled", "com.katikati.autoHide.edge.enabled"),
        ("com.tungsten.edge.autoHide.edge.delay", "com.katikati.autoHide.edge.delay"),
        ("com.tungsten.edge.autoHide.edge.lastEnabledDelay", "com.katikati.autoHide.edge.lastEnabledDelay"),
    ]

    @discardableResult
    static func migrateIfNeeded(defaults: UserDefaults, now: Date = Date()) -> Bool {
        guard defaults.object(forKey: migrationStampKey) == nil else {
            return false
        }
        var migratedAny = false
        for (legacyKey, newKey) in keyMap {
            if let legacyVal = defaults.object(forKey: legacyKey) {
                defaults.set(legacyVal, forKey: newKey)
                migratedAny = true
            }
        }
        defaults.set(now, forKey: migrationStampKey)
        return migratedAny
    }
}
