import AppKit
import SwiftUI

// Phase 6 Appearance tab: the Phase-4 theme presets (`com.katikati.theme.material`) and the
// icon set (`com.katikati.iconSet`). Light/dark itself stays on General › Appearance
// (`appearanceMode`) — this page never duplicates that control.
//
// Phase 12 (2026-10-15): renders through `SettingsCard`/`SettingsRow` only, and only cards — the
// page margin comes from `SettingsWindowContent` through `SettingsPane` (`Docs/SETTINGS.md` rule 1),
// instead of this file cancelling an embedded pane's own margin with a negative padding.

struct SettingsAppearancePane: View {
    @ObservedObject var store: AppSettingsStore

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("com.katikati.dock.iconShape") private var iconShapeRaw: String = DockIconShape.squircle.rawValue

    private static let presets: [DockThemeStyle] = [
        .system, .translucent, .crystalClear, .obsidianDark, .monochrome, .titaniumFrost,
        .auroraGlow, .deepOcean, .forestMoss, .cyberpunkGlass, .emberSunset, .roseQuartz,
    ]
    private static let defaultCustom = DockThemeStyle.customRGBA(r: 0.23, g: 0.43, b: 0.65, a: 0.7)

    private var choices: [DockThemeStyle] {
        let custom: DockThemeStyle
        if case .customRGBA = store.themeMaterial { custom = store.themeMaterial } else { custom = Self.defaultCustom }
        return [.auto] + Self.presets + [custom]
    }

    var body: some View {
        Group {
            // Phase 12: preview, layout mode and size live here, as their own cards.
            SettingsLayoutPane(store: store, mode: .geometry)

            SettingsCard(Text("Theme")) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 10) {
                    ForEach(choices, id: \.token) { style in
                        themeCard(style)
                    }
                }
                if case let .customRGBA(r, g, b, a) = store.themeMaterial {
                    customControls(r: r, g: g, b: b, a: a)
                }
                SettingsNote(Text("Auto uses Rose Quartz in light mode and Obsidian Dark in dark mode. Light or dark is set in General › Appearance."))
            }

            SettingsCard {
                // The picker is the control; the two cards under it are previews, not a second control.
                SettingsSegmentedRow(
                    Text("Icon Set"),
                    selection: Binding(get: { store.iconSet }, set: store.setIconSet)
                ) {
                    Text("Modern").tag(IconSet.modern)
                    Text("Classic").tag(IconSet.classic)
                }
                HStack(spacing: 12) {
                    iconPreview(.modern)
                    iconPreview(.classic)
                }
                SettingsNote(Text("Applies to the trash and the menu bar icon. Independent of the theme."))
            }

            SettingsCard {
                SettingsSegmentedRow(
                    Text("Dock App Icon Shape"),
                    selection: $iconShapeRaw
                ) {
                    Text("Squircle").tag(DockIconShape.squircle.rawValue)
                    Text("Circle").tag(DockIconShape.circle.rawValue)
                }
                SettingsNote(Text("Switch dock app icons between standard macOS squircle and clean circular masking."))
            }

            wallpaperSection
        }
    }

    // MARK: - Wallpaper (Phase 10b-3)

    private var wallpaperSection: some View {
        SettingsCard {
            SettingsToggleRow(
                Text("Dynamic Wallpaper"),
                isOn: Binding(get: { store.wallpaperEnabled }, set: store.setWallpaperEnabled)
            )
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
                    }
                    Button("Choose Folder…") { chooseWallpaperFolder() }
                }
            }
            skyPreviewGrid
            SettingsToggleRow(
                Text("Tint Dock by Time of Day"),
                isOn: Binding(get: { store.tintSurfacesByPhase }, set: store.setTintSurfacesByPhase)
            )
            SettingsButtonRow(Text("Restore Wallpaper")) { WallpaperEngine.shared.restoreNow() }
                .disabled(!store.wallpaperEnabled)
        }
    }

    /// 5 phases (rows) × 6 skies (columns) of the built-in pack, straight from `SkyPalette`.
    private var skyPreviewGrid: some View {
        VStack(spacing: 3) {
            ForEach(SolarPhase.allCases, id: \.self) { phase in
                HStack(spacing: 3) {
                    ForEach(WallpaperSky.allCases, id: \.self) { sky in
                        let stops = SkyPalette.stops(phase: phase, sky: sky)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(LinearGradient(colors: [color(stops.top), color(stops.bottom)], startPoint: .top, endPoint: .bottom))
                            .frame(height: 22)
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
        return Button {
            store.setThemeMaterial(style)
        } label: {
            VStack(spacing: 4) {
                ThemeSwatch(style: style)
                    .frame(width: 54, height: 34)
                ThemeName(style: style)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.center)
                    .frame(height: 26, alignment: .top)
            }
            .padding(4)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    // MARK: - Icon set

    private func iconPreview(_ set: IconSet) -> some View {
        let isSelected = store.iconSet == set
        return HStack(spacing: 10) {
            Group {
                if set == .modern {
                    Image("TrashEmpty").resizable().aspectRatio(contentMode: .fit)
                    Image("TrashFull").resizable().aspectRatio(contentMode: .fit)
                    Image("MenuBarIcon").resizable().renderingMode(.template).aspectRatio(contentMode: .fit)
                        .padding(4)
                } else {
                    Image(systemName: IconSet.classicTrashSymbol(isFull: false)).font(.system(size: 18))
                    Image(systemName: IconSet.classicTrashSymbol(isFull: true)).font(.system(size: 18))
                    Image(systemName: IconSet.classicMenuBarSymbol).font(.system(size: 16))
                }
            }
            .frame(width: 26, height: 26)
            Spacer(minLength: 4)
            Group {
                if set == .modern { Text("Modern") } else { Text("Classic") }
            }
            .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
        .accessibilityElement(children: .combine)
    }
}

/// Localized preset names. Literals, so the localization gate sees every key.
private struct ThemeName: View {
    let style: DockThemeStyle

    var body: some View {
        switch style {
        case .auto: Text("Auto")
        case .system: Text("System")
        case .translucent: Text("Translucent")
        case .crystalClear: Text("Crystal Clear")
        case .obsidianDark: Text("Obsidian Dark")
        case .monochrome: Text("Monochrome")
        case .titaniumFrost: Text("Titanium Frost")
        case .auroraGlow: Text("Aurora Glow")
        case .deepOcean: Text("Deep Ocean")
        case .forestMoss: Text("Forest Moss")
        case .cyberpunkGlass: Text("Cyberpunk Glass")
        case .emberSunset: Text("Ember Sunset")
        case .roseQuartz: Text("Rose Quartz")
        case .customRGBA: Text("Custom")
        }
    }
}
