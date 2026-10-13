import AppKit
import SwiftUI

// Phase 6 Appearance tab: the Phase-4 theme presets (`com.katikati.theme.material`) and the
// icon set (`com.katikati.iconSet`). Light/dark itself stays on General › Appearance
// (`appearanceMode`) — this page never duplicates that control.

struct SettingsAppearancePane: View {
    @ObservedObject var store: AppSettingsStore

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(BackgroundAppsStore.showSystemHelpersKey) private var showSystemHelpers = false
    @ObservedObject private var backgroundStore = BackgroundAppsStore.shared
    @AppStorage(WindowSwitcherController.enabledKey) private var switcherEnabled = true
    @AppStorage(MemoryOverlayController.enabledKey) private var memoryOverlayEnabled = true

    private static let margin: CGFloat = 28
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
        VStack(alignment: .leading, spacing: 18) {
            section {
                Text("Theme")
            } content: {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 10) {
                    ForEach(choices, id: \.token) { style in
                        themeCard(style)
                    }
                }
                if case let .customRGBA(r, g, b, a) = store.themeMaterial {
                    customControls(r: r, g: g, b: b, a: a)
                }
                Text("Auto uses Rose Quartz in light mode and Obsidian Dark in dark mode. Light or dark is set in General › Appearance.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            section {
                HStack {
                    Text("Icon Set")
                    Spacer(minLength: 12)
                    Picker("Icon Set", selection: Binding(get: { store.iconSet }, set: store.setIconSet)) {
                        Text("Modern").tag(IconSet.modern)
                        Text("Classic").tag(IconSet.classic)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            } content: {
                HStack(spacing: 12) {
                    iconPreview(.modern)
                    iconPreview(.classic)
                }
                Text("Applies to the trash and the menu bar icon. Independent of the theme.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            section {
                Toggle(isOn: $memoryOverlayEnabled) { Text("Hold Control to Show Memory").font(.headline) }
            } content: {
                Text("While the pointer is over the dock, holding Control shows how much memory each app uses.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            section {
                Toggle(isOn: $showSystemHelpers) { Text("Show System Helpers").font(.headline) }
                HStack {
                    Button("Reset Ignored Apps") { backgroundStore.unignoreAll() }
                        .disabled(backgroundStore.ignored.isEmpty)
                }
            } content: {
                Text("Background Apps lists running apps that have no window. Apple helper processes stay hidden unless this is on.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            section {
                Toggle(isOn: $switcherEnabled) { Text("Option-Tab Window Switcher").font(.headline) }
            } content: {
                Text("Hold Option and press Tab to pick a window from a thumbnail grid; release to switch. Shift reverses, Esc cancels.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            wallpaperSection
        }
        .padding(Self.margin)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Wallpaper (Phase 10b-3)

    private var wallpaperSection: some View {
        section {
            Toggle(isOn: Binding(get: { store.wallpaperEnabled }, set: store.setWallpaperEnabled)) {
                Text("Dynamic Wallpaper").font(.headline)
            }
        } content: {
            HStack {
                Text("Mode")
                Spacer(minLength: 12)
                Picker("Mode", selection: Binding(
                    get: { WallpaperMode(rawValue: store.wallpaperMode) ?? .both },
                    set: store.setWallpaperMode
                )) {
                    Text("Time").tag(WallpaperMode.time)
                    Text("Weather").tag(WallpaperMode.weather)
                    Text("Both").tag(WallpaperMode.both)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
            HStack(spacing: 8) {
                if store.wallpaperFolder.isEmpty {
                    Text("Built-in Sky").foregroundStyle(.secondary)
                } else {
                    Text(verbatim: (store.wallpaperFolder as NSString).lastPathComponent).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if !store.wallpaperFolder.isEmpty {
                    Button("Built-in Sky") { store.setWallpaperFolder("") }
                }
                Button("Choose Folder…") { chooseWallpaperFolder() }
            }
            skyPreviewGrid
            Toggle(isOn: Binding(get: { store.tintSurfacesByPhase }, set: store.setTintSurfacesByPhase)) {
                Text("Tint Dock by Time of Day")
            }
            HStack {
                Spacer()
                Button("Restore Wallpaper") { WallpaperEngine.shared.restoreNow() }
                    .disabled(!store.wallpaperEnabled)
            }
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
                swatch(style)
                    .frame(width: 54, height: 34)
                ThemeName(style: style)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .lineLimit(2)
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

    /// Plate tint + rim from the real preset tokens (both appearance columns for Auto).
    @ViewBuilder
    private func swatch(_ style: DockThemeStyle) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        if style == .auto {
            HStack(spacing: 0) {
                plate(DockThemeStyleTokens.resolve(style: .auto, appearance: .light))
                plate(DockThemeStyleTokens.resolve(style: .auto, appearance: .dark))
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.15)))
        } else {
            let tokens = DockThemeStyleTokens.resolve(style: style, appearance: colorScheme == .dark ? .dark : .light)
            plate(tokens)
                .clipShape(shape)
                .overlay(shape.strokeBorder(color(tokens.rim).opacity(max(0.35, tokens.rim.a)), lineWidth: 1.5))
        }
    }

    private func plate(_ tokens: DockThemeStyleTokens) -> some View {
        ZStack {
            // Neutral desktop under the translucent plate so alpha reads as it does on screen.
            Color(white: 0.62)
            color(tokens.baseTint)
            LinearGradient(colors: [color(tokens.gradientSheen), .clear], startPoint: .top, endPoint: .center)
        }
    }

    private func color(_ rgba: DockRGBA) -> Color {
        Color(.sRGB, red: Double(rgba.r), green: Double(rgba.g), blue: Double(rgba.b), opacity: Double(rgba.a))
    }

    private func isSame(_ lhs: DockThemeStyle, _ rhs: DockThemeStyle) -> Bool {
        if case .customRGBA = lhs, case .customRGBA = rhs { return true }
        return lhs == rhs
    }

    private func customControls(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) -> some View {
        HStack(spacing: 10) {
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

    private func section<Header: View, Content: View>(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header().font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
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
