import AppKit
import SwiftUI

// Phase 6 Appearance tab: the Phase-4 theme presets (`com.katikati.theme.material`).
// Light/dark itself stays on General › Appearance
// (`appearanceMode`) — this page never duplicates that control.
//
// Phase 12 (2026-10-15): renders through `SettingsCard`/`SettingsRow` only, and only cards — the
// page margin comes from `SettingsWindowContent` through `SettingsPane` (`Docs/SETTINGS.md` rule 1),
// instead of this file cancelling an embedded pane's own margin with a negative padding.

struct SettingsAppearancePane: View {
    @ObservedObject var store: AppSettingsStore

    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredThemeToken: String?
    @AppStorage(SpaceTransitionSettings.effectKey) private var spaceEffectRaw = SpaceTransitionEffect.fade.rawValue
    @AppStorage(SpaceTransitionSettings.durationKey) private var spaceDuration = SpaceTransitionSettings.defaultDuration

    private static let defaultCustom = DockThemeStyle.customRGBA(r: 0.23, g: 0.43, b: 0.65, a: 0.7)

    private var choices: [DockThemeStyle] {
        let custom: DockThemeStyle
        if case .customRGBA = store.themeMaterial { custom = store.themeMaterial } else { custom = Self.defaultCustom }
        return [.auto] + DockThemeStyle.presets + [custom]
    }

    var body: some View {
        Group {
            // Phase 12: preview, layout mode and size live here, as their own cards.
            SettingsLayoutPane(store: store, mode: .geometry)

            SettingsCard(
                Text("Theme"),
                // Rule 8: the swatches are previews, and they say so. It used to be a two-line
                // paragraph under the grid, which rule 4 does not allow on a card either.
                note: Text("Swatches show the dock plate's tint; Auto follows light and dark, set in General.")
            ) {
                // 48 pt of minimum width, not 55: the swatch draws 48 wide and the cell owes it 4 pt
                // of padding each side, so a 55 pt cell is 62 pt of ink and only twelve of thirteen
                // swatches fit — the thirteenth wrapped to a second row (~55 pt the page does not
                // have). Same control, same preview, same names.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 10) {
                    ForEach(choices, id: \.token) { style in
                        themeCard(style)
                    }
                }
                if case let .customRGBA(r, g, b, a) = store.themeMaterial {
                    customControls(r: r, g: g, b: b, a: a)
                }
                // 12f. Only a pinned preset tints the plate, so on Auto / System these two would be
                // controls that visibly do nothing — they appear with the theme that has a tint.
                if store.themeMaterial.tintsPlate {
                    SettingsDivider()
                    // The two plate knobs share a line (2026-10-18): both are label + track +
                    // readout, which fits half the card, and with them stacked the page ran past
                    // the window whenever a tinted theme was pinned.
                    SettingsSliderRow(
                        Text("Vibrancy"),
                        value: store.themeVibrancy,
                        range: DockThemeStyle.vibrancyRange,
                        step: 0.05,
                        valueText: "\(Int((store.themeVibrancy * 100).rounded()))%",
                        set: store.setThemeVibrancy
                    )
                
                    SettingsDivider()
                    SettingsSliderRow(
                        Text("Contrast"),
                        value: store.themeContrast,
                        range: DockThemeStyle.contrastRange,
                        step: 0.1,
                        valueText: String(format: "%.1f×", Double(store.themeContrast)),
                        set: store.setThemeContrast
                    )

                    // 2026-10-26. Same knob family as the two above and the one translucency
                    // handle that reaches every plate: the tint is drawn over the backdrop, so
                    // thickening it is what makes the plate read solid.
                    SettingsDivider()
                    SettingsSliderRow(
                        Text("Translucency"),
                        value: store.themeTranslucency,
                        range: DockThemeStyle.translucencyRange,
                        step: 0.05,
                        valueText: "\(Int((store.themeTranslucency * 100).rounded()))%",
                        set: store.setThemeTranslucency
                    )
                
                }
            }

            // DW-4: the wallpaper controls moved to their own page (Settings › Wallpaper).

            spaceSwitchingCard
        }
    }

    // MARK: - Space switching (ported from Spacewalk)

    /// The two knobs the transition controller reads straight from the defaults on every switch, so
    /// they apply without a restart and without touching the settings store.
    private var spaceSwitchingCard: some View {
        SettingsCard(
            Text("Space Switching"),
            note: Text("Freezes the picture, lets the Dock switch underneath, then plays the effect. Needs macOS 26 or newer, Screen Recording and Accessibility; older systems post the switch plain.")
        ) {
            SettingsSegmentedRow(
                Text("Effect"),
                selection: Binding(
                    get: { SpaceTransitionEffect(rawValue: spaceEffectRaw) ?? .fade },
                    set: { spaceEffectRaw = $0.rawValue }
                )
            ) {
                Text("Instant").tag(SpaceTransitionEffect.instant)
                Text("Fade").tag(SpaceTransitionEffect.fade)
            }
            SettingsDivider()
            SettingsSliderRow(
                Text("Duration"),
                value: spaceDuration,
                range: SpaceTransitionSettings.durationRange,
                step: 0.02,
                valueText: "\(Int((spaceDuration * 1000).rounded())) ms",
                set: { spaceDuration = $0 }
            )
        }
    }

    // MARK: - Theme cards

    private func themeCard(_ style: DockThemeStyle) -> some View {
        let isSelected = isSame(style, store.themeMaterial)
        let isHovered = hoveredThemeToken == style.token
        let palette = SettingsIridescentPalette.resolve(style: style, colorScheme: colorScheme)
        return Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.76)) {
                store.setThemeMaterial(style)
            }
        } label: {
            VStack(spacing: 4) {
                ThemeSwatch(style: style)
                    .frame(width: 48, height: 32)
                    .shadow(color: isSelected ? palette.glowColor : .clear, radius: 5, x: 0, y: 2)
                ThemeName(style: style)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.center)
                    .frame(height: 26, alignment: .top)
            }
            .padding(4)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(palette.subtleSurfaceGradient)
                            : AnyShapeStyle(Color.primary.opacity(isHovered ? 0.06 : 0.0))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? AnyShapeStyle(palette.pillGradient)
                            : AnyShapeStyle(Color.primary.opacity(isHovered ? 0.16 : 0.0)),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .scaleEffect(isHovered ? 1.04 : 1.0)
            .animation(.spring(response: 0.24, dampingFraction: 0.75), value: isHovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hoveredThemeToken = inside ? style.token : (hoveredThemeToken == style.token ? nil : hoveredThemeToken)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func isSame(_ lhs: DockThemeStyle, _ rhs: DockThemeStyle) -> Bool {
        if case .customRGBA = lhs, case .customRGBA = rhs { return true }
        return lhs == rhs
    }

    private func customControls(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) -> some View {
        HStack(spacing: SettingsMetrics.controlSpacing) {
            Text("Custom Tint")
            ColorPicker("Custom Tint", selection: Binding(
                get: { Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b)) },
                set: { newColor in
                    guard let c = NSColor(newColor).usingColorSpace(.sRGB) else { return }
                    store.setThemeMaterial(.customRGBA(r: c.redComponent, g: c.greenComponent, b: c.blueComponent, a: a))
                }
            ), supportsOpacity: false)
            .labelsHidden()
            Text("Opacity")
            Slider(value: Binding(
                get: { a },
                set: { store.setThemeMaterial(.customRGBA(r: r, g: g, b: b, a: $0)) }
            ), in: 0.2...1)
        }
    }

}

/// Localized preset names. Literals, so the localization gate sees every key.
private struct ThemeName: View {
    let style: DockThemeStyle

    var body: some View {
        Text(style.menuTitle)
    }
}


// The dedicated page the dynamic wallpaper grew into: one stage that shows the actual scene model, the three
// pillars (time/solar, weather, environment) and the dock accent studio. Everything it previews is computed by
// the pure Core types (`SolarDaylightEvaluator`, `TerrainMimicCatalog`, `DockAccentSpec`) — the page draws the
// same values the engine paints with, so the preview cannot drift from the desktop.
struct SettingsWallpaperPane: View {
    @ObservedObject var store: AppSettingsStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var followLiveTime = true
    @State private var previewHour = 12.0
    @State private var previewSky: WallpaperSky = .clear
    @State private var draftStops: [String] = []

    private var mode: WallpaperMode { WallpaperMode(rawValue: store.wallpaperMode) ?? .both }

    var body: some View {
        Group {
            previewCard
            dynamicCard
            accentCard
            restoreCard
        }
        .onAppear(perform: loadDraft)
    }

    // MARK: Stage

    private var previewCard: some View {
        SettingsCard(
            Text("Live Preview"),
            note: Text("Scrub the day and the sky to see the scene. The desktop follows your own clock and forecast; until the weather service reports sun times this preview uses a 06:30–19:30 day.")
        ) {
            WallpaperStageView(environment: previewEnvironment, accent: accentPreviewColors)
                .frame(height: 168)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.18)))
                .accessibilityHidden(true)
            SettingsToggleRow(Text("Follow Live Time"), isOn: $followLiveTime)
            SettingsDivider()
            SettingsSliderRow(
                Text("Time of Day"),
                value: followLiveTime ? liveHour : previewHour,
                range: 0...24,
                step: 0.25,
                valueText: hourLabel(followLiveTime ? liveHour : previewHour),
                set: { previewHour = $0; followLiveTime = false }
            )
            SettingsDivider()
            SettingsSegmentedRow(Text("Sky"), selection: $previewSky) {
                ForEach(WallpaperSky.allCases, id: \.self) { sky in
                    Text(skyTitle(sky)).tag(sky)
                }
            }
        }
    }

    // MARK: Pillars

    private var dynamicCard: some View {
        SettingsCard(
            Text("Dynamic Wallpaper"),
            note: Text("Painted locally from the clock and the forecast already in the app — no downloads and no extra location prompt.")
        ) {
            SettingsToggleRow(
                Text("Dynamic Wallpaper"),
                isOn: Binding(get: { store.wallpaperEnabled }, set: store.setWallpaperEnabled)
            )
            SettingsDivider()
            SettingsToggleRow(
                Text("Live Time & Solar"),
                isOn: Binding(get: { mode != .weather }, set: { on in setMode(time: on, weather: mode != .time) })
            )
            SettingsDivider()
            SettingsToggleRow(
                Text("Live Weather"),
                isOn: Binding(get: { mode != .time }, set: { on in setMode(time: mode != .weather, weather: on) })
            )
            SettingsDivider()
            // DW-6: Auto follows the forecast; a locked mood paints its own sky + time of day until Auto is chosen again.
            SettingsRow(
                Text("Weather Mood"),
                note: store.wallpaperMoodValue == .auto
                    ? Text("Auto follows the live forecast and the clock.")
                    : Text("Locked: this atmosphere stays until you choose Auto.")
            ) {
                Picker("Weather Mood", selection: Binding(get: { store.wallpaperMoodValue }, set: store.setWallpaperMood)) {
                    ForEach(WallpaperMood.allCases, id: \.self) { mood in
                        Text(Self.moodTitle(mood)).tag(mood)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            SettingsDivider()
            SettingsSegmentedRow(
                Text("Environment"),
                selection: Binding(get: { store.wallpaperTerrainValue }, set: store.setWallpaperTerrain)
            ) {
                Text("Auto").tag(WallpaperTerrain.auto)
                Text("City").tag(WallpaperTerrain.city)
                Text("Countryside").tag(WallpaperTerrain.countryside)
                Text("Terrain").tag(WallpaperTerrain.terrain)
            }
            SettingsDivider()
            // Rule 7: the source in use is the label; the buttons change it.
            SettingsRow(
                store.wallpaperFolder.isEmpty
                    ? Text("Built-in Scenes")
                    : Text(verbatim: (store.wallpaperFolder as NSString).lastPathComponent)
            ) {
                HStack(spacing: 8) {
                    if !store.wallpaperFolder.isEmpty {
                        Button("Built-in Scenes") { store.setWallpaperFolder("") }
                            .buttonStyle(SettingsGelButtonStyle())
                    }
                    Button("Choose Folder…") { chooseWallpaperFolder() }
                        .buttonStyle(SettingsGelButtonStyle())
                }
            }
            SettingsDivider()
            SettingsToggleRow(
                Text("Reapply on Space Change"),
                isOn: Binding(get: { store.wallpaperReapplyOnSpaceChange }, set: store.setWallpaperReapplyOnSpaceChange)
            )
            SettingsDivider()
            SettingsToggleRow(
                Text("Respect Low Power Mode"),
                isOn: Binding(get: { store.wallpaperRespectLowPower }, set: store.setWallpaperRespectLowPower)
            )
            SettingsDivider()
            SettingsToggleRow(
                Text("Tint Dock by Time of Day"),
                isOn: Binding(get: { store.tintSurfacesByPhase }, set: store.setTintSurfacesByPhase)
            )
        }
    }

    // MARK: Dock accent

    private var accentCard: some View {
        SettingsCard(
            Text("Dock Accent"),
            note: Text("One colour, a gradient of up to four, or the wallpaper's own sampled palette.")
        ) {
            SettingsSegmentedRow(
                Text("Style"),
                selection: Binding(get: { store.dockAccent.style }, set: { style in
                    // Pressing Style has to stick: with no stops entered yet a gradient form would normalize back to
                    // wallpaper-adaptive on the spot, so the switch seeds the stops it needs from the palette first.
                    store.setDockAccent(store.dockAccent.switching(to: style, wallpaperAccent: sampledAccentHexes))
                    draftStops = padded(store.dockAccent.hexStops)
                })
            ) {
                Text("Solid").tag(DockAccentStyle.solid)
                Text("Gradient").tag(DockAccentStyle.linearGradient)
                Text("Mesh").tag(DockAccentStyle.mesh)
                Text("Wallpaper").tag(DockAccentStyle.wallpaperAdaptive)
            }
            SettingsDivider()
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { index in
                    TextField(Self.hexPlaceholder, text: Binding(
                        get: { index < draftStops.count ? draftStops[index] : "" },
                        set: { new in
                            var stops = padded(draftStops)
                            stops[index] = new
                            draftStops = stops
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 88)
                }
                Spacer(minLength: 0)
                Button("Apply Accent") { applyAccent() }
                    .buttonStyle(SettingsGelButtonStyle())
            }
            SettingsDivider()
            SettingsSliderRow(
                Text("Angle"),
                value: store.dockAccent.angleDegrees,
                range: 0...359,
                step: 1,
                valueText: "\(Int(store.dockAccent.angleDegrees.rounded()))°",
                set: { angle in
                    var spec = store.dockAccent
                    spec.angleDegrees = angle
                    store.setDockAccent(spec)
                }
            )
            SettingsDivider()
            SettingsRow(Text("Accent Preview")) {
                LinearGradient(colors: accentPreviewColors, startPoint: .leading, endPoint: .trailing)
                    .frame(width: 180, height: 18)
                    .clipShape(Capsule())
                    .accessibilityHidden(true)
            }
        }
    }

    private var restoreCard: some View {
        SettingsCard {
            SettingsButtonRow(
                Text("Restore Wallpaper"),
                note: store.wallpaperEnabled ? nil : Text("Turn Dynamic Wallpaper on to restore it.")
            ) { WallpaperEngine.shared.restoreNow() }
                .disabled(!store.wallpaperEnabled)
        }
    }

    // MARK: Model

    /// The scene drawn on the stage: the pinned environment (or Auto's fallback), the previewed sky and either the
    /// real clock or the scrubber, run through the same evaluator the engine uses.
    private var previewEnvironment: WallpaperEnvironment {
        let hour = followLiveTime ? liveHour : previewHour
        let live = Self.phase(forHour: hour, on: Date()).solarPhase
        // The stage obeys the same mood resolution the engine does, so a locked atmosphere is what the page shows —
        // not the clock's sky with a label saying otherwise.
        let resolved = store.wallpaperMoodValue.resolve(weather: previewSky, phase: live)
        let scene = TerrainMimicCatalog.resolve(store.wallpaperTerrainValue, latitude: nil, cityName: "")
        return TerrainMimicCatalog.environment(scene: scene, phase: resolved.phase, sky: resolved.sky)
    }

    private var accentPreviewColors: [Color] {
        store.dockAccent.resolved(wallpaperAccent: sampledAccentHexes).map {
            Color(red: $0.red, green: $0.green, blue: $0.blue)
        }
    }

    /// The wallpaper's own sampled accent as hex, the same palette the dock reads when nothing is entered.
    private var sampledAccentHexes: [String] {
        previewEnvironment.accent.map {
            DockAccentColor(r: CGFloat($0.r), g: CGFloat($0.g), b: CGFloat($0.b)).hex
        }
    }

    /// A synthetic 06:30–19:30 day on `date`'s calendar day: the preview cannot read the weather service's sun times
    /// (the Settings window has no weather environment), and a fixed day is honest about it.
    static func times(on date: Date) -> SunTimes {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        return SunTimes(sunrise: calendar.date(byAdding: .minute, value: 390, to: start),
                        sunset: calendar.date(byAdding: .minute, value: 1170, to: start))
    }

    static func phase(forHour hour: Double, on date: Date) -> DaylightPhase {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let at = start.addingTimeInterval(min(max(hour, 0), 24) * 3600)
        return SolarDaylightEvaluator.sample(at: at, times: times(on: date)).phase
    }

    private var liveHour: Double {
        let calendar = Calendar.current
        let now = Date()
        return Double(calendar.component(.hour, from: now)) + Double(calendar.component(.minute, from: now)) / 60
    }

    private func hourLabel(_ hour: Double) -> String {
        let whole = Int(hour) % 24
        let minutes = Int(((hour - floor(hour)) * 60).rounded())
        return String(format: "%02d:%02d", whole, minutes == 60 ? 0 : minutes)
    }

    static func moodTitle(_ mood: WallpaperMood) -> String {
        switch mood {
        case .auto: return String(localized: "Auto")
        case .rainyEvening: return String(localized: "Rainy Evening")
        case .goldenEvening: return String(localized: "Golden Evening")
        case .snowyDay: return String(localized: "Snowy Day")
        case .stormNight: return String(localized: "Storm Night")
        case .clearNight: return String(localized: "Clear Night")
        }
    }

    private func skyTitle(_ sky: WallpaperSky) -> String {
        switch sky {
        case .clear: return String(localized: "Clear")
        case .cloudy: return String(localized: "Cloudy")
        case .rain: return String(localized: "Rain")
        case .snow: return String(localized: "Snow")
        case .storm: return String(localized: "Storm")
        case .fog: return String(localized: "Fog")
        }
    }

    private func setMode(time: Bool, weather: Bool) {
        switch (time, weather) {
        case (true, true): store.setWallpaperMode(.both)
        case (true, false): store.setWallpaperMode(.time)
        case (false, true): store.setWallpaperMode(.weather)
        case (false, false): store.setWallpaperMode(.time)   // neither is not a mode; keep the clock
        }
    }

    private func loadDraft() {
        draftStops = padded(store.dockAccent.hexStops)
    }

    private func padded(_ stops: [String]) -> [String] {
        var result = Array(stops.prefix(3))
        while result.count < 3 { result.append("") }
        return result
    }

    /// Applies the entered stops as one edit: empty fields are dropped, invalid hexes are refused by the model (a
    /// gradient short of its minimum falls back to wallpaper-adaptive rather than painting one arbitrary colour).
    private func applyAccent() {
        var spec = store.dockAccent
        let entered = draftStops.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !entered.isEmpty { spec.hexStops = entered }
        // The Angle slider writes the store live, so Apply must not carry a stale copy over it.
        store.setDockAccent(spec)
        draftStops = padded(store.dockAccent.hexStops)
    }

    /// Not a localized string: the format hint for a hex field reads the same in every language, and declaring it
    /// as a `String` keeps `TextField` on its verbatim initializer instead of making the catalog carry it.
    private static let hexPlaceholder = "#RRGGBB"

    private func chooseWallpaperFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { store.setWallpaperFolder(url.path) }
    }
}

/// The stage: sky gradient, sun/moon glow and the three silhouette bands of the resolved scene, plus a capsule in
/// the current accent stops so the dock's own colours are visible next to the picture they were sampled from.
struct WallpaperStageView: View {
    let environment: WallpaperEnvironment
    let accent: [Color]

    var body: some View {
        Canvas { context, size in
            let sky = Gradient(colors: [color(environment.skyTop), color(environment.skyBottom)])
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(sky, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            if environment.glowStrength > 0 {
                let center = CGPoint(x: size.width * 0.72, y: size.height * 0.34)
                let radius = size.height * 0.45
                context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                    width: radius * 2, height: radius * 2)),
                             with: .radialGradient(Gradient(colors: [color(environment.glow).opacity(environment.glowStrength), .clear]),
                                                   center: center, startRadius: 0, endRadius: radius))
            }
            for (index, layer) in environment.layers.enumerated() {
                context.fill(band(index: index, of: environment.layers.count, size: size), with: .color(color(layer)))
            }
            let capsule = CGRect(x: size.width * 0.25, y: size.height - 34, width: size.width * 0.5, height: 18)
            context.fill(Path(roundedRect: capsule, cornerRadius: 9),
                         with: .linearGradient(Gradient(colors: accent.map { $0.opacity(0.9) }),
                                               startPoint: CGPoint(x: capsule.minX, y: 0),
                                               endPoint: CGPoint(x: capsule.maxX, y: 0)))
        }
    }

    /// The same band geometry the PNG renderer paints, in SwiftUI coordinates (origin top-left).
    private func band(index: Int, of count: Int, size: CGSize) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        let depth = CGFloat(count - index - 1)
        let base = size.height * (0.90 - 0.08 * depth)
        switch environment.scene {
        case .city:
            return cityPath(index: index, base: base, size: size)
        default:
            let steps = 96
            let amplitude: CGFloat = environment.scene == .alpine ? 0.30 : environment.scene == .countryside ? 0.16 : 0.24
            let sea = environment.scene == .coast && index == count - 1
            for step in 0...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let ridge = CGFloat(SceneGeometry.ridge(x: Double(t), layer: index, peakX: environment.scene == .coast ? 0.28 : 0.5))
                let y = sea ? size.height * 0.94 : base - size.height * amplitude * ridge
                path.addLine(to: CGPoint(x: t * size.width, y: y))
            }
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        return path
    }

    private func cityPath(index: Int, base: CGFloat, size: CGSize) -> Path {
        var path = Path()
        let blocks = 14
        var x: CGFloat = 0
        for i in 0..<blocks {
            let seed = (i &* 73 &+ index &* 31) & 97
            let width = size.width / CGFloat(blocks) * (0.7 + CGFloat(seed % 6) / 10)
            let height = size.height * (0.10 + CGFloat(seed % 9) / 100)
            path.addRect(CGRect(x: x, y: base - height, width: min(width, size.width - x), height: height + (size.height - base)))
            x += width
            if x >= size.width { break }
        }
        return path
    }

    private func color(_ c: SkyRGB) -> Color { Color(red: c.r, green: c.g, blue: c.b) }
}
