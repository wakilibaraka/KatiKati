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

            wallpaperSection

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

    // MARK: - Wallpaper (Phase 10b-3)

    private var wallpaperSection: some View {
        SettingsCard {
            // The switch and the mode it governs, one line (`Docs/SETTINGS.md` rule 5).
            SettingsToggleRow(
                Text("Dynamic Wallpaper"),
                isOn: Binding(get: { store.wallpaperEnabled }, set: store.setWallpaperEnabled)
            )
        
            SettingsDivider()
            SettingsSegmentedRow(
                Text("Mode"),
                selection: Binding(
                    get: { WallpaperMode(rawValue: store.wallpaperMode) ?? .both },
                    set: store.setWallpaperMode
                )
            ) {
                Text("Time").tag(WallpaperMode.time)
                Text("Weather").tag(WallpaperMode.weather)
                Text("Both").tag(WallpaperMode.both)
            }
        
            // The row's label is the source in use; the buttons change it.
            SettingsRow(
                store.wallpaperFolder.isEmpty
                    ? Text("Built-in Sky")
                    : Text(verbatim: (store.wallpaperFolder as NSString).lastPathComponent)
            ) {
                HStack(spacing: 8) {
                    if !store.wallpaperFolder.isEmpty {
                        Button("Built-in Sky") { store.setWallpaperFolder("") }
                            .buttonStyle(SettingsGelButtonStyle())
                    }
                    Button("Choose Folder…") { chooseWallpaperFolder() }
                        .buttonStyle(SettingsGelButtonStyle())
                }
            }
            skyPreviewGrid
            // Two narrow rows, one line (rule 5): the switch and the button were two lines.
            SettingsToggleRow(
                Text("Tint Dock by Time of Day"),
                isOn: Binding(get: { store.tintSurfacesByPhase }, set: store.setTintSurfacesByPhase)
            )
        
            SettingsDivider()
            // Rule 7: disabled with no reason on the row before this.
            SettingsButtonRow(
                Text("Restore Wallpaper"),
                note: store.wallpaperEnabled ? nil : Text("Turn Dynamic Wallpaper on to restore it.")
            ) { WallpaperEngine.shared.restoreNow() }
                .disabled(!store.wallpaperEnabled)
        
        }
    }

    /// 5 phases (rows) × 6 skies (columns) of the built-in pack, straight from `SkyPalette`. The
    /// swatches are 14 pt tall, not 22 (2026-10-15): this preview alone was 122 pt of a page that
    /// has to fit the window, and the same 30 palettes are still here.
    private var skyPreviewGrid: some View {
        VStack(spacing: 2) {
            ForEach(SolarPhase.allCases, id: \.self) { phase in
                HStack(spacing: 2) {
                    ForEach(WallpaperSky.allCases, id: \.self) { sky in
                        let stops = SkyPalette.stops(phase: phase, sky: sky)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(LinearGradient(colors: [color(stops.top), color(stops.bottom)], startPoint: .top, endPoint: .bottom))
                            .frame(height: 10)
                            .help(Text(verbatim: "\(phase.rawValue) · \(sky.rawValue)"))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func color(_ c: SkyRGB) -> Color { Color(red: c.r, green: c.g, blue: c.b) }

    private func chooseWallpaperFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { store.setWallpaperFolder(url.path) }
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
