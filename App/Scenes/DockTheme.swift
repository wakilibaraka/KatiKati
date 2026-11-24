import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

// MARK: - DockThemeTokens 的 SwiftUI / AppKit 桥接
//
// 纯数值表在 `Core/Support/DockThemeTokens.swift`（不 import SwiftUI，因此可被单测精确冻结）。
// 这里只做「数值 → Color / Material / 修饰符」的翻译，不含任何取值判断。
//
// Usage — a view that needs colour declares
//     @Environment(\.colorScheme) private var colorScheme
//     private var theme: DockThemeTokens { .resolved(for: colorScheme) }
// and reads `theme.xxx.color`.
//
// `colorScheme` comes from the hosting window's `effectiveAppearance`, the same source the frosted
// material and Liquid Glass follow, so text and plate always flip together. There is deliberately
// no appearance-free accessor: a view that skipped the environment would stay light on a dark plate.


struct DockThemeStyleKey: EnvironmentKey {
    static let defaultValue: DockThemeStyle = .auto
}

// DW-6 — the accent the dock's *own* surfaces fill from (selected/active pill, running-app dot, slider track).
// The pure stop→fill mapping lives in `DockAccentFill` (Core, tested); this is only the Color bridge plus the two
// shorthands the views need. Empty stops means "no accent configured", and every surface keeps the signed-off token
// look exactly as it was.
struct DockAccentEnvironment: Equatable {
    var stops: [Color] = []
    var isGradient = false
    var angleDegrees = 90.0

    static let inactive = DockAccentEnvironment()

    var isActive: Bool { !stops.isEmpty }
    var primary: Color { stops.first ?? .clear }

    /// A single `Color` for a solid accent, or a multi-stop `LinearGradient` running along the accent's angle.
    func style(opacity: Double) -> AnyShapeStyle {
        guard isGradient, stops.count > 1 else { return AnyShapeStyle(primary.opacity(opacity)) }
        let points = DockAccentFill.unitPoints(angleDegrees: angleDegrees)
        return AnyShapeStyle(LinearGradient(colors: stops.map { $0.opacity(opacity) },
                                            startPoint: UnitPoint(x: points.start.x, y: points.start.y),
                                            endPoint: UnitPoint(x: points.end.x, y: points.end.y)))
    }

    /// Built from the stored spec and the wallpaper's sampled hues; `enabled` is false only while the dock should keep
    /// its own look (no accent configured at all).
    static func resolve(spec: DockAccentSpec, wallpaperAccent: [String]) -> DockAccentEnvironment {
        let fill = DockAccentFill.stops(spec: spec, wallpaperAccent: wallpaperAccent, enabled: true)
        return DockAccentEnvironment(
            stops: fill.colors.map { Color(red: $0.red, green: $0.green, blue: $0.blue) },
            isGradient: fill.isGradient,
            angleDegrees: fill.angleDegrees
        )
    }
}

struct DockAccentKey: EnvironmentKey {
    static let defaultValue = DockAccentEnvironment.inactive
}

struct IconSetKey: EnvironmentKey {
    static let defaultValue: IconSet = .default
}

struct ThemeTuningKey: EnvironmentKey {
    static let defaultValue = ThemeTuning.identity
}

extension EnvironmentValues {
    var iconSet: IconSet {
        get { self[IconSetKey.self] }
        set { self[IconSetKey.self] = newValue }
    }

    var dockThemeStyle: DockThemeStyle {
        get { self[DockThemeStyleKey.self] }
        set { self[DockThemeStyleKey.self] = newValue }
    }

    var dockAccent: DockAccentEnvironment {
        get { self[DockAccentKey.self] }
        set { self[DockAccentKey.self] = newValue }
    }

    /// The Appearance page's two plate knobs (`ThemeTuning`), injected beside `dockThemeStyle` at
    /// every site that injects that one — same reason: the surfaces read it, they never own it.
    var themeTuning: ThemeTuning {
        get { self[ThemeTuningKey.self] }
        set { self[ThemeTuningKey.self] = newValue }
    }
}

extension DockRGBA {
    /// The SwiftUI bridge for a token colour: the tables hold sRGB channels and a separate alpha.
    var color: Color {
        Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
    }
}

extension DockThemeTokens {

    /// The column for a SwiftUI colour scheme (anything that is not `.dark` is light).
    static func resolved(for colorScheme: ColorScheme, style: DockThemeStyle) -> DockThemeTokens {
        let isDark = colorScheme == .dark
        let appearance: AppearanceMode = isDark ? .dark : .light
        let styleTokens = DockThemeStyleTokens.resolve(style: style, appearance: appearance)
        
        var base = isDark ? DockThemeTokens.dark(styleTokens: styleTokens) : DockThemeTokens.light(styleTokens: styleTokens)
        
        // Honor preset tint (if not auto, we override base fields)
        if style != .auto {
            base = base.with(styleTokens: styleTokens)
        }
        
        return base
    }
    
    // Fallback for views not yet updated
    static func resolved(for colorScheme: ColorScheme) -> DockThemeTokens {
        resolved(for: colorScheme, style: .auto)
    }

    /// 实际生效的材质：`DOCK_PANEL_MATERIAL` 覆盖 token 值（认不出的名字回落，不崩）。
    var effectivePanelMaterial: DockPanelMaterial {
        DockPanelMaterial.resolved(from: DockEffectSwitches.environment, fallback: panelMaterial)
    }

    /// 实际生效的背景饱和度。未开 → `1.0`（桥接层的 `dockBackdropSaturation` 会整个跳过修饰符）。
    /// 开了才用表里的候选值，也可以直接在环境变量里给一个数覆盖它。
    var effectiveBackdropSaturation: Double {
        DockEffectSwitches.saturation(from: DockEffectSwitches.environment, candidate: panelBackdropSaturation)
    }

    /// 实际生效的中转格瓷砖配色：`DOCK_SHELF_TILE=blue|graphite|light` 覆盖 token 值
    /// （认不出的名字回落到 `.blue`，不崩）。三档是同一个位置的互斥选项，现场换档不重编译。
    var effectiveShelfTile: DockShelfTileStyle {
        guard let raw = DebugSwitch.shelfTile.value(in: DockEffectSwitches.environment) else { return shelfTile }
        return DockShelfTileStyle.resolve(raw)
    }

    /// 厚度层到底画不画：**先看开关**，再看纯条件（`drawsPanelThickness`，颜色与线宽都得非零）。
    /// 深色两层保险——候选值本来就是 0，开关打开也不画。
    var drawsEffectiveThickness: Bool {
        DockEffectSwitches.thicknessEnabled(from: DockEffectSwitches.environment) && drawsPanelThickness
    }

    /// 实际生效的标题卡药丸底色：`DOCK_CHIP_PILL_FILL` 覆盖表里的值。
    /// 和上面几个不同，这里的默认值**就是已签收的观感**，环境变量只是不重编译的调参出口
    ///（同 `DOCK_DRAG_FLIGHT_MS`），不是「未验收效果 opt-in」那一类。
    var effectiveChipPillFill: DockTintPair {
        DockEffectSwitches.chipPillFill(from: DockEffectSwitches.environment, candidate: chipPillFill)
    }

    /// 实际生效的「不在当前桌面」标题色：`DOCK_LABEL_INACTIVE` 覆盖表里的值。
    /// 必须和 `effectiveChipPillFill` 一起调，理由见 `chipPillFill` 的注释。
    var effectiveLabelInactive: DockTint {
        DockEffectSwitches.labelInactive(from: DockEffectSwitches.environment, candidate: labelInactive)
    }
}

enum DockEffectSwitches {
    /// 读一次就固定——调参期间改环境变量重启一次即可，也避免一次会话里前后不一致。
    static let environment = ProcessInfo.processInfo.environment

    /// `DOCK_PANEL_SATURATION=1.25`。未设 / 非数字 / 超出合理范围 → `1.0`（= 不加滤镜）。
    /// 特例：`1` 也当"开，用表里的候选值"讲不通——数字就是倍数本身，`1` 就是不提饱和。
    /// 想用表里的候选值就写 `candidate`。
    static func saturation(from environment: [String: String], candidate: Double) -> Double {
        guard let raw = DebugSwitch.panelSaturation.value(in: environment)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !raw.isEmpty else { return 1.0 }
        if raw == "candidate" { return candidate }
        guard let value = Double(raw), value > 0, value <= 5 else { return 1.0 }
        return value
    }

    /// `DOCK_PANEL_THICKNESS=1` 才开。其余一切（含未设、`0`、乱填）都是关。
    static func thicknessEnabled(from environment: [String: String]) -> Bool {
        DebugSwitch.panelThickness.value(in: environment)?.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    /// `DOCK_CHIP_PILL_FILL=<常态>[,<悬停态>]`，两个都是 0…1 的不透明度。
    /// 只给一个数时悬停态按表里既有的 **×1.4** 关系推出来。未设 / 非数字 / 越界 → 回落到表里的值。
    /// Only the opacity is overridden; the base stays the column's own, so the pill cannot be
    /// flipped onto the text's side (`DockThemeTokens.chipPillFill`).
    static func chipPillFill(from environment: [String: String], candidate: DockTintPair) -> DockTintPair {
        guard let raw = DebugSwitch.chipPillFill.value(in: environment)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return candidate }
        let parts = raw.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard (1...2).contains(parts.count), let normal = opacity(parts[0]) else { return candidate }
        let emphasized: Double
        if parts.count == 2 {
            guard let parsed = opacity(parts[1]) else { return candidate }
            emphasized = parsed
        } else {
            emphasized = min(normal * 1.4, 1)
        }
        return DockTintPair(normal: DockTint(base: candidate.normal.base, opacity: normal),
                            emphasized: DockTint(base: candidate.emphasized.base, opacity: emphasized))
    }

    /// `DOCK_LABEL_INACTIVE=<不透明度>`（0…1）。未设 / 非数字 / 越界 → 回落到表里的值。
    /// The base stays the column's own, as above.
    static func labelInactive(from environment: [String: String], candidate: DockTint) -> DockTint {
        guard let raw = DebugSwitch.labelInactive.value(in: environment)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let value = opacity(raw) else { return candidate }
        return DockTint(base: candidate.base, opacity: value)
    }

    /// 0…1 的不透明度解析。空串 / 非数字 / 越界一律 `nil`，由调用方回落。
    private static func opacity(_ raw: String) -> Double? {
        guard !raw.isEmpty, let value = Double(raw), value >= 0, value <= 1 else { return nil }
        return value
    }

    /// 调参诊断：只有真的设了某个开关才打一行，打的是**解析后**的值——
    /// 名字或数字写错（被回落）当场就看得出来，不会拿着一张其实没生效的对照图瞎比。
    static func logActiveOverrides(material: DockPanelMaterial, saturation: Double, thickness: Bool) {
        if let raw = DebugSwitch.panelMaterial.value(in: environment) {
            print("[panel] DOCK_PANEL_MATERIAL=\"\(raw)\" → 实际生效 \(material)")
        }
        if let raw = DebugSwitch.panelSaturation.value(in: environment) {
            print("[panel] DOCK_PANEL_SATURATION=\"\(raw)\" → 实际生效 \(saturation)")
        }
        if let raw = DebugSwitch.panelThickness.value(in: environment) {
            print("[panel] DOCK_PANEL_THICKNESS=\"\(raw)\" → 厚度层\(thickness ? "开" : "关")")
        }
        // 这两个不属于底板，但调对比度时和上面几个一起看，所以打在同一处。
        // Both overrides apply to whichever column is showing (opacity only).
        if let raw = DebugSwitch.chipPillFill.value(in: environment) {
            let pair = DockThemeTokens.resolved(for: .light).effectiveChipPillFill
            print("[panel] DOCK_CHIP_PILL_FILL=\"\(raw)\" → 实际生效 常态 \(pair.normal.opacity) / 悬停 \(pair.emphasized.opacity)")
        }
        if let raw = DebugSwitch.labelInactive.value(in: environment) {
            print("[panel] DOCK_LABEL_INACTIVE=\"\(raw)\" → 实际生效 \(DockThemeTokens.resolved(for: .light).effectiveLabelInactive.opacity)")
        }
    }
}

extension DockRGB {
    var color: Color { Color(red: red, green: green, blue: blue) }
}

extension DockShelfTileStyle {
    /// 瓷砖的上→下渐变。`lifted` = 外部文件悬停命中，整块朝白提一点。
    func gradient(lifted: Bool) -> LinearGradient {
        let c = colors
        let amount = lifted ? Self.dropTargetLift : 0
        return LinearGradient(colors: [c.top.lightened(by: amount).color,
                                       c.bottom.lightened(by: amount).color],
                              startPoint: .top,
                              endPoint: .bottom)
    }

    var glyphColor: Color { colors.glyph.color }
}

extension DockTint {
    var color: Color {
        switch base {
        case .white: return Color.white.opacity(opacity)
        case .black: return Color.black.opacity(opacity)
        case .rgb(let rgba): return Color(red: rgba.r, green: rgba.g, blue: rgba.b).opacity(opacity)
        }
    }

    /// 同基色的全透明版本。
    /// **不要用 `Color.clear` 代替**：动画是在两个颜色之间插值，从 `.clear` 淡向一个白色描边
    /// 会在中途透出灰边；改造前的写法本来就是 `opacity(isActive ? 0.9 : 0)`。
    var transparent: Color { DockTint(base: base, opacity: 0).color }

    /// 按状态开关同一处着色（关 = 同基色全透明）。
    func color(active: Bool) -> Color { active ? color : transparent }
}

extension DockTintPair {
    /// - Parameter emphasized: 悬停中，或投放命中。
    func color(emphasized: Bool) -> Color {
        (emphasized ? self.emphasized : normal).color
    }

    func color(emphasisProgress rawProgress: Double) -> Color {
        let progress = min(max(rawProgress, 0), 1)
        let opacity = normal.opacity + (emphasized.opacity - normal.opacity) * progress
        return DockTint(base: normal.base, opacity: opacity).color
    }
}

extension DockPanelMaterial {
    var nsMaterial: NSVisualEffectView.Material {
        switch self {
        case .popover: return .popover
        case .hudWindow: return .hudWindow
        case .menu: return .menu
        case .underWindowBackground: return .underWindowBackground
        case .sidebar: return .sidebar
        case .titlebar: return .titlebar
        case .selection: return .selection
        case .headerView: return .headerView
        case .fullScreenUI: return .fullScreenUI
        case .toolTip: return .toolTip
        case .sheet: return .sheet
        case .windowBackground: return .windowBackground
        case .contentBackground: return .contentBackground
        case .underPageBackground: return .underPageBackground
        }
    }
}

// MARK: - 未验收效果的开关
//
// **默认值 = owner 已认可的观感；未验收的效果一律 opt-in。**
//
// 这条是 2026-07-30 订正出来的：玻璃探路当时做成了默认关 + `DOCK_LIQUID_GLASS=1` 才开，
// 但同一天加的提饱和与厚度层却默认生效了——同样是没验收的效果，两套标准。结果 owner
// 眼前的观感在他不知情的情况下偏离了他点过头的那一版，是他自己发现的。
//
// 所以下面三样统一 opt-in。调参时一次重启切一样，也顺带解决「三个变量叠一起归不了因」。
// 候选数值仍然只有一张表（`DockThemeTokens.light`），开关只决定用不用它。

extension DockThemeTokens {
    /// 面板描边：上沿亮、下沿暗，模拟来自上方的光（苹果原生玻璃的打光方向）。
    /// 深色两端同值 → 渐变退化成均匀色，与改造前的 `.strokeBorder(.white.opacity(0.15))` 逐像素一致。
    var panelRimStyle: LinearGradient {
        LinearGradient(colors: [panelRimTop.color, panelRimBottom.color],
                       startPoint: .top,
                       endPoint: .bottom)
    }

    /// 投放命中时换成实色整框；否则用上下渐变。
    func panelRimStyle(highlighted: Bool) -> AnyShapeStyle {
        highlighted ? AnyShapeStyle(panelRimHighlighted.color) : AnyShapeStyle(panelRimStyle)
    }

    func panelRimLineWidth(highlighted: Bool) -> CGFloat {
        highlighted ? panelRimHighlightedLineWidth : panelRimLineWidth
    }

    /// 玻璃厚度层：上内沿一条亮线（光从上方进入介质）+ 下内沿一道暗收（介质底部自阴影）。
    /// 画在材质**之上**、内容**之下**，是我们自己的像素——所以不受「拿不到窗口背后像素」
    /// 那条限制（折射与背景饱和度就是卡在那里）。
    ///
    /// 调用方必须先判 `drawsEffectiveThickness`（开关 + 纯条件）：深色与未开时整层不进视图树。
    @ViewBuilder
    func panelThicknessLayer(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape
                .strokeBorder(
                    LinearGradient(colors: [panelInnerHighlight.color, panelInnerHighlight.transparent],
                                   startPoint: .top, endPoint: .center),
                    lineWidth: panelInnerHighlightWidth
                )
                .blur(radius: panelInnerHighlightBlur)
            shape
                .strokeBorder(
                    LinearGradient(colors: [panelInnerShadow.transparent, panelInnerShadow.color],
                                   startPoint: .center, endPoint: .bottom),
                    lineWidth: panelInnerShadowWidth
                )
                .blur(radius: panelInnerShadowBlur)
        }
        // 模糊会溢出形状，必须裁回来，否则厚度层会糊到面板外面去。
        .clipShape(shape)
        // 纯装饰层，绝不能抢 chip 的点击（面板是 nonactivatingPanel，chip 全靠 onTapGesture）。
        .allowsHitTesting(false)
    }

    /// 标题胶囊的描边：同样是上亮下暗。
    /// - Parameter emphasized: 悬停中。
    func chipPillRimStyle(emphasized: Bool) -> LinearGradient {
        LinearGradient(colors: [chipPillRimTop.color(emphasized: emphasized), chipPillRimBottom.color],
                       startPoint: .top,
                       endPoint: .bottom)
    }

    func chipPillRimStyle(emphasisProgress: Double) -> LinearGradient {
        LinearGradient(
            colors: [chipPillRimTop.color(emphasisProgress: emphasisProgress), chipPillRimBottom.color],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension View {
    /// 安静档的悬停反馈：整块**轻微放大**。判据见 `HoverStyle.showsQuietHoverFeedback`。
    ///
    /// `scaleEffect` 是纯渲染变换：**不改布局尺寸**（这一档的底线就是"鼠标划过任务条不重排"），
    /// 也不影响 `.background` 里 GeometryReader 上报的投放命中矩形——`PinnedFolderChip`
    /// 的整块放大早就是这么做的，同一条既有结论。
    ///
    /// anchor 取 `.bottom`：条只有 54pt 高、卡片撑满条高，从中心放大会往下越出条外；
    /// 从底边顶起既留在条内，也更像原生 Dock 的放大方向。
    ///
    /// 动画用 `.animation(_:value:)`（值域限定），只有 `isActive` 变化时才动。
    /// `LauncherChip` 的启动弹跳有自己更内层的 `.animation(_:value: bounceUp)`，
    /// 内层优先，不会被这一层裹走——AGENTS 里「安静档不产生事务」防的就是弹跳被劫持。
    ///
    /// **曲线是 owner 2026-08-17 从三档里挑定的（`easeOut 0.12` = 保持现状）**，不是随手写的默认值。
    /// 依据分两层，别混着读：**实测**——合成一次悬停，那 120ms 内主线程零卡顿、整条零重算、
    /// 零 relayout；**由此推断**——他说的「不够流畅」是曲线取舍，不是被别的东西抢了资源，
    /// 而曲线属于观感，量不出来，所以做成三档让他上眼比。比完选了现状，脚手架随即拆除。
    /// `cardWidth` 是**这张卡自己的宽度**（已按档位缩放），用来把每侧外扩量封顶——
    /// 等比放大在 168pt 的标题卡上会外扩 8.4pt，把 10pt 的卡间缝挤掉（owner 2026-08-17 报）。
    /// **故意不给默认值**：漏传必须是编译错误，同 `scale` / `hoverStyle` 那条既有规矩。
    func chipQuietHoverScale(_ isActive: Bool, cardWidth: CGFloat, scale: CGFloat) -> some View {
        let target = ChipPillMetrics.quietHoverScale(forCardWidth: cardWidth, scale: scale)
        return self
            .scaleEffect(isActive ? target : 1, anchor: .bottom)
            .animation(.easeOut(duration: 0.12), value: isActive)
    }

    /// 给毛玻璃底板加背景提饱和。**1.0 时整个修饰符都不挂**——`.saturation(1.0)` 虽是恒等，
    /// 但仍可能触发离屏渲染，多一层就可能破坏深色的逐像素冻结（同厚度层的理由）。
    @ViewBuilder
    func dockBackdropSaturation(_ amount: Double) -> some View {
        if amount == 1.0 { self } else { self.saturation(amount) }
    }

    /// 应用一个 `DockShadow`（x 恒为 0）。**拍拖动副本时一律不画**（理由与实测见
    /// `EnvironmentValues.isDragCarrierSnapshot`）。
    ///
    /// 注意这里已经**没有图标投影这一路了**：图标 / 中转格 / 文件夹封面都不带外投影
    /// （owner 2026-08-19，对齐原生 Dock）。剩下的用户是面板、弹窗、气泡和文字光晕。
    func dockShadow(_ shadow: DockShadow) -> some View {
        modifier(DockShadowModifier(shadow: shadow))
    }

    /// `visible == false` attaches nothing at all — a zero-alpha `.shadow` is still a filter.
    @ViewBuilder
    func dockShadow(_ shadow: DockShadow, visible: Bool) -> some View {
        if visible { dockShadow(shadow) } else { self }
    }

    /// 条件式光晕：`active` 为假时半径与不透明度都归零（等价于不画）。
    /// 光晕不在「不烘投影」的范围内：它是卡自己的一部分（拖动中也该跟着走），不是落地要交接的投影。
    func dockGlow(_ tint: DockTint, radius: CGFloat, active: Bool) -> some View {
        self.shadow(color: tint.color(active: active), radius: active ? radius : 0)
    }
}

/// The one container every dock tile wears: the Launcher and Wi-Fi/Volume buttons, the weather pod and the
/// two rail tiles. **These numbers are the Launcher/Wi-Fi buttons' recipe, copied verbatim** — those two were
/// the owner-approved look, and five other surfaces each carried a near-copy with a different radius, stroke
/// alpha or hover curve, which is how the dock came to read as several docks (Phase 40b/40f). A new tile uses
/// this modifier; it does not restate the numbers.
struct DockTileChrome: ViewModifier {
    /// The dock's own plate colour. One home for the number: the glass weather presets fill the same
    /// pill with it, and a second copy would be a second dock.
    static let plate = Color(red: 0.11, green: 0.12, blue: 0.16).opacity(0.88)

    /// Widget Look (Settings > Widgets): Tiles swaps the dock plate for the graphite square on every tile.
    @AppStorage(WidgetLook.storageKey) private var lookRaw = WidgetLook.default.rawValue

    /// The dock's Animation Speed (Dock > Animation Speed): the one stored motion preset, so the
    /// picker finally changes what the tiles do. Reduce Motion wins, as everywhere else.
    @AppStorage(WidgetMotionPreset.storageKey) private var motionRaw = WidgetMotionPreset.default.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: WidgetMotion {
        (WidgetMotionPreset(rawValue: motionRaw) ?? WidgetMotionPreset.default).effective(reduceMotion: reduceMotion)
    }

    let isHovered: Bool
    var cornerRadius: CGFloat = 14
    /// A tile with a plate of its own (the weather pod's sky). `nil` = the dock plate above, so every
    /// existing tile is bit-for-bit unchanged (Phase 46).
    var fill: LinearGradient?

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill.map { AnyShapeStyle($0) } ?? (lookRaw == WidgetLook.tiles.rawValue
                        ? AnyShapeStyle(Color(white: 0.085)) : AnyShapeStyle(Self.plate)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isHovered ? Color.white.opacity(0.28) : Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.32 : 0.16), radius: isHovered ? 6 : 3, x: 0, y: 2)
            .scaleEffect(isHovered ? motion.hoverScale : 1.0)
            .animation(motion.hoverSpring?.animation, value: isHovered)
    }
}

extension View {
    func dockTileChrome(isHovered: Bool, cornerRadius: CGFloat = 14, fill: LinearGradient? = nil) -> some View {
        modifier(DockTileChrome(isHovered: isHovered, cornerRadius: cornerRadius, fill: fill))
    }

    /// The dock app icon's frame (Phase 32d, **packed**: the Settings row is gone, so `DOCK_ICON_FRAME`
    /// decides). Unset = the squircle macOS draws icons in — the shape every icon wears today; `circle`
    /// = the hard circular crop plus the 0.16 hairline rim that preset shipped with. One home for the
    /// branch: `ChipView`, `LauncherChip` and `DrawerCapsuleButton` each wore their own copy of it.
    @ViewBuilder
    func dockIconMask(size: CGFloat) -> some View {
        switch DockIconShape.packed {
        case .squircle:
            clipShape(RoundedRectangle(cornerRadius: size / 4, style: .continuous))
        case .circle:
            clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 0.5))
        }
    }
}

struct ChipPillUsesGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether title pills may be drawn as system glass. Set only by the taskbar, from its panel's
    /// `usesLiquidGlass`. The default is the safe side on purpose: a drag-carrier bitmap is rendered
    /// off-window, where a glass effect captures as nothing, so it must get the flat pill.
    var chipPillUsesGlass: Bool {
        get { self[ChipPillUsesGlassKey.self] }
        set { self[ChipPillUsesGlassKey.self] = newValue }
    }
}

struct DragCarrierSnapshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// 这一棵视图树是不是正被拍成拖动副本的位图。
    ///
    /// 拍出来的位图与屏幕上那张卡有**两处刻意的不同**，都由它控制：
    /// - **不画运行小圆点**：原生 Dock 拖起有圆点的图标时圆点是消失的，落位才回来（owner 2026-08-19）。
    /// - **不烘任何 `dockShadow`**：眼下没有哪张卡还画 `dockShadow`（图标外投影和文件夹名光晕
    ///   都已去掉），这条留着防以后加回来的：`cacheDisplay` 抓 SwiftUI 的 `.shadow` 只抓到约四分之一
    ///   强度——实测同一块白板 0.6 的投影只捕到 alpha 23（`ImageRenderer` 同一张是 99）——烘进去
    ///   会得到一份比卡上淡得多的阴影，落位交接反而出现台阶，比干脆不画更糟。
    var isDragCarrierSnapshot: Bool {
        get { self[DragCarrierSnapshotKey.self] }
        set { self[DragCarrierSnapshotKey.self] = newValue }
    }
}

/// `dockShadow` 的实现体。做成 `ViewModifier` 只是为了能读环境——`View` 的扩展方法里读不到。
private struct DockShadowModifier: ViewModifier {
    let shadow: DockShadow
    @Environment(\.isDragCarrierSnapshot) private var isSnapshot

    func body(content: Content) -> some View {
        if isSnapshot {
            content
        } else {
            content.shadow(color: shadow.tint.color, radius: shadow.radius, x: 0, y: shadow.y)
        }
    }
}

// MARK: - IS-2.1 Icon Studio Asset Loader, Static Finish Baker & Two-Tier Cache

enum IconAssetLoader {
    static func loadCGImage(from url: URL) -> CGImage? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
        if isDir.boolValue || url.pathExtension.lowercased() == "icon" { return loadFromIconBundle(at: url) }
        return NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func loadFromIconBundle(at bundleURL: URL) -> CGImage? {
        let assetsURL = bundleURL.appendingPathComponent("Assets", isDirectory: true)
        let searchDirs = FileManager.default.fileExists(atPath: assetsURL.path) ? [assetsURL, bundleURL] : [bundleURL]
        let exts: Set<String> = ["png", "icns", "tiff", "tif", "jpg", "jpeg", "webp", "pdf"]
        for dir in searchDirs {
            guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for file in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where exts.contains(file.pathExtension.lowercased()) {
                if let cg = NSImage(contentsOf: file)?.cgImage(forProposedRect: nil, context: nil, hints: nil) { return cg }
            }
        }
        return nil
    }

    static func pngData(from cgImage: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }
}

actor IconBakeActor {
    static let shared = IconBakeActor()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let cacheDir: URL

    init(cacheDir: URL? = nil) {
        if let cacheDir { self.cacheDir = cacheDir }
        else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.cacheDir = caches.appendingPathComponent("com.katikati.app/IconStudio", isDirectory: true)
        }
    }

    nonisolated func cacheFileURL(fingerprint: String) -> URL { cacheDir.appendingPathComponent("\(fingerprint).png", isDirectory: false) }

    func bakeIfNeeded(fingerprint: String, sourceImageData: Data?, recolor: IconRecolorSpec, shader: IconShaderSpec, pixelSize: Int) -> Data? {
        let outURL = cacheFileURL(fingerprint: fingerprint)
        if let cached = try? Data(contentsOf: outURL), !cached.isEmpty { return cached }
        guard let sourceImageData, let cg = NSImage(data: sourceImageData)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let size = max(32, min(512, pixelSize))
        var ci = CIImage(cgImage: cg)
        ci = ci.transformed(by: CGAffineTransform(scaleX: CGFloat(size) / max(1, ci.extent.width), y: CGFloat(size) / max(1, ci.extent.height)))
        if !recolor.isIdentity { ci = applyRecolor(ci, spec: recolor) }
        if shader.preset.requiresStaticBake { ci = applyStaticFinish(ci, preset: shader.preset, strength: shader.strength, size: CGFloat(size)) }
        guard let outCG = ciContext.createCGImage(ci, from: CGRect(x: 0, y: 0, width: size, height: size)),
              let png = IconAssetLoader.pngData(from: outCG) else { return nil }
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try? png.write(to: outURL, options: .atomic)
        return png
    }

    private func applyRecolor(_ input: CIImage, spec: IconRecolorSpec) -> CIImage {
        let t = CGFloat(spec.intensity)
        let c1 = ciColor(hex: spec.primaryHex) ?? CIColor(red: 0.25, green: 0.55, blue: 1.0)
        let c2 = ciColor(hex: spec.secondaryHex) ?? CIColor(red: 0.1, green: 0.12, blue: 0.18)
        switch spec.mode {
        case .original: return input
        case .monochrome:
            return blend(base: input, overlay: input.applyingFilter("CIColorMonochrome", parameters: [kCIInputColorKey: c1, kCIInputIntensityKey: t]), alpha: t)
        case .tint:
            return blend(base: input, overlay: input.applyingFilter("CIColorMonochrome", parameters: [kCIInputColorKey: c1, kCIInputIntensityKey: t * 0.75]), alpha: t)
        case .duotone:
            let map = input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
                .applyingFilter("CIFalseColor", parameters: ["inputColor0": c2, "inputColor1": c1])
            return blend(base: input, overlay: map, alpha: t)
        }
    }

    private func applyStaticFinish(_ input: CIImage, preset: IconShaderPreset, strength: Double, size: CGFloat) -> CIImage {
        let s = CGFloat(strength)
        let extent = CGRect(x: 0, y: 0, width: size, height: size)
        switch preset {
        case .none, .holographicFoil, .vhs, .crt, .lavaLamp, .neonSign: return input
        case .liquidGlass:
            let glass = input.applyingFilter("CIGlassDistortion", parameters: [kCIInputScaleKey: 12 * s])
                .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: 0.06 * s, kCIInputContrastKey: 1 + 0.14 * s])
            return addTopSheen(to: blend(base: input, overlay: glass, alpha: 0.85 * s), extent: extent, opacity: 0.35 * s)
        case .gloss:
            return addTopSheen(to: input.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1 + 0.12 * s]), extent: extent, opacity: 0.48 * s)
        case .gold:
            let g = input.applyingFilter("CIColorMonochrome", parameters: [kCIInputColorKey: CIColor(red: 0.95, green: 0.75, blue: 0.25), kCIInputIntensityKey: 0.92])
                .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.25, kCIInputBrightnessKey: 0.04])
            return addTopSheen(to: blend(base: input, overlay: g, alpha: s), extent: extent, opacity: 0.32 * s)
        case .lightLeather, .tooledLeather:
            let leather = CIColor(red: preset == .lightLeather ? 0.76 : 0.42, green: preset == .lightLeather ? 0.58 : 0.27, blue: preset == .lightLeather ? 0.40 : 0.17)
            let base = input.applyingFilter("CIColorMonochrome", parameters: [kCIInputColorKey: leather, kCIInputIntensityKey: 0.78])
            let noise = CIFilter.randomGenerator().outputImage?.cropped(to: extent)
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 0.35])
            let embossed = noise.map { base.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: $0]) } ?? base
            return blend(base: input, overlay: embossed, alpha: s)
        case .woodInlay:
            return blend(base: input, overlay: input.applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: 0.88]).applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.18]), alpha: s)
        case .carvedMarble:
            return blend(base: input, overlay: input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.12, kCIInputBrightnessKey: 0.14, kCIInputContrastKey: 1.15]), alpha: s)
        case .embroidery:
            return blend(base: input, overlay: input.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: max(2.0, size * 0.025)]), alpha: s * 0.85)
        case .brushedMetal:
            let metal = input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.08, kCIInputContrastKey: 1.22])
                .applyingFilter("CIMotionBlur", parameters: [kCIInputRadiusKey: 2.2 * s, kCIInputAngleKey: 0])
            return addTopSheen(to: blend(base: input, overlay: metal, alpha: s), extent: extent, opacity: 0.22 * s)
        case .stainedGlass:
            return blend(base: input, overlay: input.applyingFilter("CICrystallize", parameters: [kCIInputRadiusKey: max(4, size * 0.06)]).applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.35]), alpha: s * 0.9)
        case .classicMac:
            return blend(base: input, overlay: input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 1.65]), alpha: s)
        }
    }

    private func addTopSheen(to base: CIImage, extent: CGRect, opacity: CGFloat) -> CIImage {
        let grad = CIFilter.linearGradient()
        grad.point0 = CGPoint(x: extent.midX, y: extent.maxY); grad.point1 = CGPoint(x: extent.midX, y: extent.midY * 0.85)
        grad.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: min(1, max(0, opacity))); grad.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 0)
        guard let sheen = grad.outputImage?.cropped(to: extent) else { return base }
        return sheen.applyingFilter("CISourceOverCompositing", parameters: [kCIInputBackgroundImageKey: base])
            .applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: base])
    }

    private func blend(base: CIImage, overlay: CIImage, alpha: CGFloat) -> CIImage {
        let scaled = overlay.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: min(1, max(0, alpha)))])
        return scaled.applyingFilter("CISourceOverCompositing", parameters: [kCIInputBackgroundImageKey: base])
    }

    private func ciColor(hex: String?) -> CIColor? {
        guard var raw = hex?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard raw.count == 6, let val = UInt32(raw, radix: 16) else { return nil }
        return CIColor(red: CGFloat((val >> 16) & 0xFF) / 255, green: CGFloat((val >> 8) & 0xFF) / 255, blue: CGFloat(val & 0xFF) / 255)
    }
}

@MainActor
final class IconStudioController: ObservableObject {
    static let shared = IconStudioController()

    @Published private(set) var state: IconStudioState
    @Published private(set) var revision: Int = 0
    @Published var liveOverrides: [String: Double] = [:]
    @Published var previewBadgeOverride: Bool = false

    private let stateURL: URL
    private var fastCache: [String: NSImage] = [:]
    private var inFlightKeys: Set<String> = []

    init(stateURL: URL = IconStudioPersistence.defaultFileURL()) {
        self.stateURL = stateURL
        self.state = IconStudioPersistence.load(from: stateURL)
    }

    func look(for bundleID: String) -> IconLook? { state.looksByBundleID[bundleID] }
    func badgeEffect(for bundleID: String) -> IconBadgeEffectSpec { state.looksByBundleID[bundleID]?.badgeEffect ?? .init() }
    func setLook(_ look: IconLook, for bundleID: String) { state.setLook(look, for: bundleID); persistAndBump() }
    func restoreOriginal(for bundleID: String) { state.restoreOriginal(for: bundleID); persistAndBump() }
    func savePreset(name: String, from look: IconLook) { state.savePreset(name: name, from: look); persistAndBump() }
    func applyPreset(_ preset: SavedIconLookPreset, to bundleID: String) { state.applyPreset(preset, to: bundleID); persistAndBump() }
    func deletePreset(id: UUID) { state.deletePreset(id: id); persistAndBump() }

    func importArtwork(from url: URL, for bundleID: String) -> Bool {
        guard let cg = IconAssetLoader.loadCGImage(from: url), let png = IconAssetLoader.pngData(from: cg) else { return false }
        let assetsDir = stateURL.deletingLastPathComponent().appendingPathComponent("IconStudioAssets", isDirectory: true)
        let rel = "\(bundleID)-\(UUID().uuidString.prefix(8)).png"
        try? FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        guard (try? png.write(to: assetsDir.appendingPathComponent(rel), options: .atomic)) != nil else { return false }
        var look = state.looksByBundleID[bundleID] ?? IconLook()
        look.artwork = .localFile(relativePath: rel)
        setLook(look, for: bundleID)
        return true
    }

    func artworkFileURL(for source: IconArtworkSource) -> URL? {
        let base = stateURL.deletingLastPathComponent().appendingPathComponent("IconStudioAssets", isDirectory: true)
        switch source {
        case .original: return nil
        case .localFile(let rel), .macOSIcons(_, let rel): return base.appendingPathComponent(rel)
        }
    }

    func resolvedStaticImage(for bundleID: String, pixelSize: Int, fallbackArtwork: @escaping () -> Data? = { nil }) -> NSImage? {
        guard let look = state.looksByBundleID[bundleID],
              look.artwork.isCustom || !look.recolor.isIdentity || look.shader.preset.requiresStaticBake else { return nil }
        let fp = look.staticBakeFingerprint(bundleID: bundleID, pixelSize: pixelSize)
        if let hit = fastCache[fp] { return hit }
        if !inFlightKeys.contains(fp) {
            inFlightKeys.insert(fp)
            let sourceData = artworkFileURL(for: look.artwork).flatMap { IconAssetLoader.loadCGImage(from: $0) }.flatMap { IconAssetLoader.pngData(from: $0) }
                ?? fallbackArtwork()
            let (recolor, shader) = (look.recolor, look.shader)
            Task.detached(priority: .utility) {
                let png = await IconBakeActor.shared.bakeIfNeeded(
                    fingerprint: fp, sourceImageData: sourceData, recolor: recolor, shader: shader, pixelSize: pixelSize
                )
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.inFlightKeys.remove(fp)
                    if let png, let img = NSImage(data: png) {
                        img.size = NSSize(width: CGFloat(pixelSize) / 2.0, height: CGFloat(pixelSize) / 2.0)
                        if self.fastCache.count >= 512 { self.fastCache.removeAll() }
                        self.fastCache[fp] = img
                        self.revision &+= 1
                    }
                }
            }
        }
        return nil
    }

    private func persistAndBump() { try? IconStudioPersistence.save(state, to: stateURL); revision &+= 1 }
}
