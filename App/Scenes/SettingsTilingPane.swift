import AppKit
import ApplicationServices
import SwiftUI

/// Settings pane for auto-tiling, layout presets, gaps, floating exclusions, and tiling shortcuts (Phase 26b).
/// Renders through the shared card/row system (`Docs/SETTINGS.md` rule 2) — it used to be the one
/// pane whose headers had no card around them at all.
struct SettingsTilingPane: View {
    @ObservedObject var store: AppSettingsStore
    @ObservedObject private var engine = TilingEngine.shared
    @State private var floatingAppsDraft: String = ""
    @AppStorage(FocusFollowService.enabledKey) private var focusFollow = false
    @AppStorage(StripScrollService.enabledKey) private var stripScroll = false

    /// The strip's own rows only make sense when a display is actually drawing the ribbon.
    private var showsRibbonRows: Bool {
        engine.preset == .ribbon || engine.displayPresets.values.contains(.ribbon)
    }

    var body: some View {
        // One card, not four. Window Management carried **six** sections — Tiling, Layout, Floating
        // Applications, Tiling Shortcuts, Window Chips, Window Behaviour — against rule 5's three,
        // and the extra headers plus their gaps are exactly what ran the page past the window.
        // Tiling shortcut assignments are consolidated under the Shortcuts tab (no duplicate controls).
        SettingsCard(Text("Tiling")) {
            SettingsToggleRow(
                Text("Enable Auto-Tiling"),
                isOn: Binding(
                    get: { engine.isEnabled },
                    set: { engine.setEnabled($0) }
                ),
                note: Text("Arranges your open windows on this screen without overlap. Turning it off puts every window back where it was.")
            )

            if !axTrusted {
                SettingsDivider()
                SettingsButtonRow(
                    Text("Allow Accessibility"),
                    note: Text("macOS needs this before KatiKati can move other apps' windows."),
                    action: { AccessibilitySettingsLink.url.map { NSWorkspace.shared.open($0) } }
                )
            }

            if engine.isEnabled {
                SettingsDivider()
                Text("Layout")
                    .font(.subheadline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(TilingLayoutPreset.allCases, id: \.self) { preset in
                        layoutTile(preset)
                    }
                }
                SettingsDivider()
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: engine.preset.describedName)
                        .font(.callout.weight(.semibold))
                    if let standard = engine.preset.standardNames {
                        Text(verbatim: standard)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                SettingsNote(presetNote)
                SettingsDivider()
                SettingsNote(Text("Ribbon pictures: pick a shape for the strip, or set one with ⌘⌃1–8."))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(RibbonQuickLayout.allCases, id: \.self) { picture in
                        Button { TilingEngine.shared.applyQuickLayout(picture) } label: {
                            Text(picture.title)
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.bordered)
                        .help(Text(picture.title))
                    }
                }
                if showsRibbonRows {
                    SettingsDivider()
                    SettingsPickerRow(
                        Text("Column Width"),
                        selection: Binding(
                            get: { engine.focusedColumnWidth },
                            set: { engine.setStripColumnWidth($0) }
                        )
                    ) {
                        ForEach(ColumnWidthPreset.allCases, id: \.self) { width in
                            Text(verbatim: width.glyph).tag(width)
                        }
                    }
                    SettingsNote(Text("Parked columns keep the sliver macOS allows at the edge (about 1 pt); the peek is the OS clamp, so there is nothing to tune."))
                    SettingsDivider()
                    SettingsToggleRow(
                        Text("Scroll the Strip with ⌥-Scroll"),
                        isOn: $stripScroll,
                        note: Text("Holding Option, a two-finger scroll steps to the next or previous column. Off by default: the app under the pointer still scrolls, because the gesture does not take the event away from it.")
                    )
                    .onChange(of: stripScroll) { _, on in StripScrollService.shared.setEnabled(on) }
                }
                if NSScreen.screens.count > 1 {
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        SettingsDivider()
                        SettingsPickerRow(
                            Text(verbatim: screen.localizedName),
                            selection: Binding(
                                get: { engine.preset(for: screen) },
                                set: { engine.setPreset($0, for: screen) }
                            )
                        ) {
                            ForEach(TilingLayoutPreset.allCases, id: \.self) { Text($0.localizedTitleKey).tag($0) }
                        }
                        if let activeLayout = engine.layout(for: screen) {
                            SettingsButtonRow(
                                Text(verbatim: String(format: String(localized: "Layout Override: %@"), activeLayout.title)),
                                note: Text("Set from the Windows flyout. Resetting returns this display to its preset."),
                                action: { engine.setLayout(nil, for: screen) }
                            )
                        }
                    }
                } else if let primary = NSScreen.screens.first, let activeLayout = engine.layout(for: primary) {
                    SettingsDivider()
                    SettingsButtonRow(
                        Text(verbatim: String(format: String(localized: "Layout Override: %@"), activeLayout.title)),
                        note: Text("Set from the Windows flyout. Resetting returns this display to its preset."),
                        action: { engine.setLayout(nil, for: primary) }
                    )
                }
                if engine.preset == .mainStack || engine.preset == .centeredMain {
                    SettingsDivider()
                    SettingsSliderRow(
                        Text("Main Window Size"),
                        value: engine.options.mainRatio * 100,
                        range: 30...70,
                        step: 5,
                        valueText: "\(Int(engine.options.mainRatio * 100))%",
                        set: { engine.setOptions(TilingLayoutOptions(mainRatio: CGFloat($0) / 100, mirrored: engine.options.mirrored)) }
                    )
                    SettingsDivider()
                    SettingsToggleRow(
                        Text("Main Window on the Right"),
                        isOn: Binding(
                            get: { engine.options.mirrored },
                            set: { engine.setOptions(TilingLayoutOptions(mainRatio: engine.options.mainRatio, mirrored: $0)) }
                        )
                    )
                }
                SettingsDivider()
                SettingsSliderRow(
                    Text("Inner Gap"),
                    value: engine.gaps.inner,
                    range: 0...32,
                    step: 1,
                    valueText: "\(Int(engine.gaps.inner)) pt",
                    set: { engine.setGaps(TilingGaps(inner: CGFloat($0), outer: engine.gaps.outer)) }
                )
                SettingsDivider()
                SettingsSliderRow(
                    Text("Outer Gap"),
                    value: engine.gaps.outer,
                    range: 0...32,
                    step: 1,
                    valueText: "\(Int(engine.gaps.outer)) pt",
                    set: { engine.setGaps(TilingGaps(inner: engine.gaps.inner, outer: CGFloat($0))) }
                )

                SettingsDivider()
                // The block inside the card keeps its own label, so the grouping survives the
                // merge without a second card (rule 5's three-section budget).
                Text("App Rules")
                    .font(.subheadline)
                SettingsNote(Text("One app per line by bundle identifier. A bare line floats the app. Add =tile to keep it tiled even after you move it, or =display:Name to tile it on that display (e.g. com.apple.Safari=display:LG UltraFine)."))
                TextEditor(text: Binding(
                    get: { floatingAppsDraft.isEmpty ? engine.policy.serializedPatterns : floatingAppsDraft },
                    set: {
                        floatingAppsDraft = $0
                        engine.setPolicy(TilingPolicy.parse(patterns: $0))
                    }
                ))
                .font(.system(.body, design: .monospaced))
                .frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                SettingsDivider()
                SettingsButtonRow(
                    Text("Re-tile Moved Windows"),
                    note: engine.releasedCount == 0
                        ? Text("No windows have been moved by hand.")
                        : Text("Windows you moved by hand stay put until you press this."),
                    action: { engine.retileAll() }
                )
                .disabled(engine.releasedCount == 0)
                if engine.overflowCount > 0 {
                    SettingsNote(Text("Some windows would end up too small, so the newest ones stay as they are."))
                }
            }

            // 53d's quit-on-last-window list is not a tiling setting: it now shares the app-rules
            // table on Settings › Shortcuts with the two SlowQuit lists (2026-10-25), so this page
            // no longer carries a field for it.
            SettingsDivider()
            // 54e — off by default: it moves another app's window without a click, so it is opt-in and
            // does nothing at all until Accessibility is granted.
            SettingsToggleRow(
                Text("Focus Follows the Mouse"),
                isOn: $focusFollow,
                note: Text("Raises the window under the pointer, at most once every 120 ms. It never acts while you drag, while a KatiKati panel has the keyboard, or for the app already in front. Needs Accessibility; off by default.")
            )
            .onChange(of: focusFollow) { _, on in FocusFollowService.shared.setEnabled(on) }
        }

        SettingsCard(Text("How It Works")) {
            SettingsNote(Text("New windows join the layout by themselves. Drag or resize a window and it is left alone until you press Re-tile. Apps in the floating list are never tiled. Full-screen windows are left alone, and windows that would end up too small stay as they are."))
            SettingsNote(Text("Snap zones (halves, quarters, thirds) move one window to a spot you pick. They work with tiling on or off; a snapped window stays where you put it."))
        }

        SettingsCard(Text("Snap Zones")) {
            SettingsNote(Text("Snap Maximize fills the screen without opening a new Space; press it again to put the window back."))
            if boundSnaps.isEmpty {
                SettingsNote(Text("No snap shortcut is set. Add one under Shortcuts → Snap Hotkeys."))
            } else {
                ForEach(boundSnaps, id: \.0) { action, keys in
                    SettingsRow(Text(verbatim: SettingsLayoutPane.shortcutActionName(action))) {
                        Text(verbatim: keys).font(.system(.body, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var axTrusted: Bool { AXIsProcessTrusted() }

    /// One picker tile: the solver's own picture, the badge, and the layout's name. The badge and the
    /// spelled-out name are technical terms, so they stay verbatim rather than going through translation.
    private func layoutTile(_ preset: TilingLayoutPreset) -> some View {
        let selected = engine.preset == preset
        return Button { engine.setPreset(preset) } label: {
            VStack(spacing: 4) {
                TilingLayoutThumbnail(preset: preset)
                    .frame(height: 38)
                HStack(spacing: 4) {
                    if !preset.localizedTitleKey.hasPrefix(preset.alias.abbreviation) {
                        Text(verbatim: preset.alias.abbreviation)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                    Text(preset.localizedTitleKey)
                        .font(.caption2)
                        .lineLimit(1)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.22),
                                  lineWidth: selected ? 1.5 : 0.75)
            )
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: preset.describedName))
        .accessibilityLabel(Text(verbatim: preset.describedName))
    }

    private var presetNote: Text {
        switch engine.preset {
        case .bsp: return Text("BSP: each new window takes half of the space left, so four windows form a grid.")
        case .mainStack: return Text("Main + Stack: the first window fills the left 55%; the rest stack on the right.")
        case .monocle: return Text("Monocle: every window is full size. Use Focus Next / Previous to flip between them.")
        case .grid: return Text("Grid: windows fill evenly sized rows and columns.")
        case .spiral: return Text("Spiral: each new window takes half of the space left, turning clockwise.")
        case .columns: return Text("Columns: windows sit side by side, full height.")
        case .rows: return Text("Rows: windows stack top to bottom, full width.")
        case .centeredMain: return Text("Centered Main: the first window sits in the middle; the rest flank it.")
        case .ribbon: return Text("Ribbon: windows sit in a row of columns. The strip scrolls to follow focus; ⌃⌥⇧R changes the focused column's width.")
        }
    }

    private var boundSnaps: [(ShortcutAction, String)] {
        SettingsLayoutPane.snapHotkeyGroups.flatMap { $0 }.compactMap { action in
            store.shortcutBindings[action].flatMap(Self.glyphs).map { (action, $0) }
        }
    }

    private static func glyphs(_ trigger: ShortcutTrigger) -> String? { trigger.displayGlyphs }
}

/// A layout's shape, drawn by the tiling solver itself so the thumbnail cannot describe something the
/// engine does not do.
private struct TilingLayoutThumbnail: View {
    let preset: TilingLayoutPreset

    var body: some View {
        GeometryReader { geo in
            let area = CGRect(origin: .zero, size: geo.size).insetBy(dx: 3, dy: 3)
            let rects = TilingPreview.rects(preset: preset, area: area, gap: 2)
            ZStack(alignment: .topLeading) {
                ForEach(Array(rects.enumerated()), id: \.offset) { _, rect in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.secondary.opacity(0.30))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.45), lineWidth: 0.5)
                        )
                        .frame(width: max(2, rect.width), height: max(2, rect.height))
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
    }
}
