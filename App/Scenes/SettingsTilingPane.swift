import AppKit
import ApplicationServices
import IOKit.hid
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
                    // Every tile carries its badge, so the nine captions share one rhythm; the
                    // title is dropped only when it would repeat the badge word for word (BSP).
                    Text(verbatim: preset.alias.abbreviation)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    if preset.localizedTitleKey != preset.alias.abbreviation {
                        Text(preset.localizedTitleKey)
                            .font(.caption2)
                            .lineLimit(1)
                    }
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

// MARK: - Mission Control (MC-4)

/// Settings › Mission Control: the naming, framing, colouring and action rules the overlay reads,
/// plus a readiness panel that names a missing permission instead of failing silently. Every edit is
/// written immediately, so the stage beside the page redraws from the same stored configuration.
struct SettingsMissionControlPane: View {
    @State private var configuration = MissionControlSettings.load()
    @AppStorage(MissionControlSettings.enabledKey) private var enabled = false
    @State private var readiness = MissionControlReadiness.unknown
    /// Supplied by the App-only caller (the test target compiles this pane but not `ManagedSpaceLayoutReader`).
    var spaces: [(id: String, index: Int)] = []
    @State private var newBundleID = ""
    @State private var newRuleColor = MissionControlColor.orange

    var body: some View {
        SettingsPane {
            statusCard
            researchNote
            namingCard
            framingCard
            presentationCard
            colouringCard
            actionsCard
        }
        .onAppear {
            configuration = MissionControlSettings.load()
            refreshReadiness()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshReadiness()
        }
    }

    // MARK: Status

    private var statusCard: some View {
        SettingsCard(Text(verbatim: "Mission Control (Experimental)")) {
            SettingsNote(Text(verbatim: "Experimental. The overlay reads undocumented WindowServer/overview behaviour and has only been verified on one display without Stage Manager. Keyboard navigation, type-to-filter, hover key shortcuts and the border overlay are off by default; naming, colours and mouse/window actions do not depend on them."))
            SettingsDivider()
            SettingsToggleRow(
                Text("Show overlays in Mission Control"),
                isOn: Binding(
                    get: { enabled },
                    set: {
                        enabled = $0
                        MissionControlSettings.setEnabled($0)
                        NotificationCenter.default.post(name: MissionControlSettings.changedNotification, object: nil)
                    }
                ),
                note: Text("Names, borders, colours and hover actions are drawn only while the overview is open. Detection is event-driven, so nothing polls or uses CPU while Mission Control is closed.")
            )
            SettingsDivider()
            statusRow(
                Text("Accessibility"),
                state: readiness.accessibility,
                note: Text("Close, minimize, zoom, hide and quit act on the hovered window through its own Accessibility buttons.")
            )
            SettingsDivider()
            statusRow(
                Text("Input Monitoring"),
                state: readiness.inputMonitoring,
                note: Text("Tab, the arrow keys, Return, Escape, type-to-filter and the hover key shortcuts listen to the keyboard globally, which macOS guards behind Input Monitoring. The overlay and its mouse actions still work without it.")
            )
            SettingsDivider()
            statusRow(
                Text("Screen Recording"),
                state: readiness.screenRecording,
                note: Text("Optional: only the thumbnail tint wash needs it. Borders, badges and actions work without it.")
            )
            SettingsDivider()
            statusRow(
                Text("Dock observation"),
                state: readiness.detection,
                note: Text("macOS exposes no Mission Control API. KatiKati watches the Dock's overview window; when this macOS shows nothing to observe, the overlay reports unavailable instead of pretending to work.")
            )
        }
    }

    /// The reviewed landscape behind the experimental label, kept in the app so the decision is not
    /// folklore: several Mission Control tools died on SIP-off injection, while the survivors act only
    /// through Accessibility and Apple's own shortcuts.
    private var researchNote: some View {
        SettingsCard(Text(verbatim: "Why experimental?")) {
            SettingsNote(Text(verbatim: "A narrow action layer on top of Mission Control is proven — Mission Control Plus and the open-source CloseUp both do it through Accessibility and have survived macOS updates. Products that injected code into the Dock or required disabling SIP (TotalSpaces) did not survive Apple Silicon. Stable Space names need private WindowServer calls and cannot ship in the App Store. KatiKati therefore never injects, never asks for SIP changes, keeps the fragile keyboard/filter paths opt-in, and labels this section experimental."))
        }
    }

    @ViewBuilder
    private func statusRow(_ label: Text, state: MissionControlPermission, note: Text) -> some View {
        SettingsRow(label, note: note) {
            HStack(spacing: 6) {
                Circle()
                    .fill(colour(for: state))
                    .frame(width: 7, height: 7)
                Text(verbatim: statusText(for: state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if state == .denied {
                    Button("Open Settings") { openPrivacyPane(for: label) }
                        .buttonStyle(.link)
                }
            }
        }
    }

    private func colour(for state: MissionControlPermission) -> Color {
        switch state {
        case .granted: return .green
        case .denied: return .orange
        case .unsupported: return .red
        case .unknown: return .secondary
        }
    }

    private func statusText(for state: MissionControlPermission) -> String {
        switch state {
        case .granted: return String(localized: "Granted")
        case .denied: return String(localized: "Not granted")
        case .unsupported: return String(localized: "Unavailable on this macOS")
        case .unknown: return String(localized: "Not checked")
        }
    }

    private func openPrivacyPane(for label: Text) {
        let title = label.searchableTitle ?? ""
        let anchor: String
        if title.contains("Accessibility") {
            anchor = "Privacy_Accessibility"
        } else if title.contains("Input Monitoring") {
            anchor = "Privacy_ListenEvent"
        } else {
            anchor = "Privacy_ScreenCapture"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Naming

    private var namingCard: some View {
        SettingsCard(Text("Naming")) {
            SettingsToggleRow(Text("Space titles"), isOn: bind(\.naming.showsSpaceTitles),
                              note: Text("A pill at the top of the overview with this Space's name and its position."))
            SettingsDivider()
            SettingsToggleRow(Text(verbatim: "Keyboard navigation and hover keys"), isOn: bind(\.naming.keyboardEnabled),
                              note: Text(verbatim: "Experimental, off by default. Needs Input Monitoring, and Mission Control does not forward every key to a background app; the overlay still works with the mouse."))
            SettingsDivider()
            SettingsRowPair {
                SettingsToggleRow(Text("Window badges"), isOn: bind(\.naming.showsWindowBadges))
            } right: {
                SettingsToggleRow(Text("Filter while typing"), isOn: bind(\.naming.filterEnabled))
                    .disabled(!configuration.naming.keyboardEnabled)
            }
            SettingsDivider()
            SettingsRowPair {
                SettingsToggleRow(Text("App name in badge"), isOn: bind(\.naming.showsAppIcon))
            } right: {
                SettingsToggleRow(Text("Document title in badge"), isOn: bind(\.naming.showsWindowTitle))
            }
            SettingsDivider()
            if spaces.isEmpty {
                SettingsNote(Text("Space names appear once a display layout is readable. Each name is stored against the Space's own ID, so it survives a restart and reordering."))
                SettingsDivider()
                spaceLabelRow(id: "1", index: 1)
            } else {
                ForEach(spaces, id: \.id) { space in
                    SettingsDivider()
                    spaceLabelRow(id: space.id, index: space.index)
                }
            }
        }
    }

    private func spaceLabelRow(id: String, index: Int) -> some View {
        SettingsRow(Text(verbatim: String(format: String(localized: "Space %lld"), index))) {
            HStack(spacing: 8) {
                TextField(
                    "Name this Space",
                    text: Binding(
                        get: { configuration.naming.spaceLabels[id] ?? "" },
                        set: {
                            configuration.naming.spaceLabels[id] = $0
                            save()
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 170)
                ColorPicker(selection: Binding(
                    get: {
                        Color(mission: configuration.colouring.spaceAccents[id] ?? configuration.presentation.accentFallback)
                    },
                    set: {
                        configuration.colouring.spaceAccents[id] = $0.missionColor
                        save()
                    }
                ), supportsOpacity: false) {
                    Text("Space colour")
                }
                .labelsHidden()
                .frame(width: 44)
                .accessibilityLabel(Text("Space colour"))
            }
        }
    }

    // MARK: Look

    private var presentationCard: some View {
        SettingsCard(Text("Look & Layout")) {
            SettingsPickerRow(Text(verbatim: "Appearance"), selection: bind(\.presentation.appearance)) {
                ForEach(MissionControlAppearance.allCases, id: \.self) {
                    Text(verbatim: $0.label).tag($0)
                }
            }
            SettingsNote(Text(verbatim: "Traffic Light is the default: colourful category accents, real app names and window titles, and red/yellow/green action dots, with the border overlay off. Colourful Everything turns the borders up; Liquid Glass and Paper are alternative materials."))
            SettingsDivider()
            SettingsSliderRow(
                Text("Border width"),
                value: configuration.presentation.borderWidth,
                range: 1...6,
                step: 0.5,
                valueText: String(format: "%.1f pt", configuration.presentation.borderWidth),
                set: {
                    configuration.presentation.borderWidth = $0
                    save()
                }
            )
            SettingsDivider()
            SettingsSliderRow(
                Text("Corner radius"),
                value: configuration.presentation.cornerRadius,
                range: 0...28,
                step: 1,
                valueText: "\(Int(configuration.presentation.cornerRadius)) pt",
                set: {
                    configuration.presentation.cornerRadius = $0
                    save()
                }
            )
            SettingsDivider()
            SettingsSliderRow(
                Text("Badge opacity"),
                value: configuration.presentation.badgeOpacity * 100,
                range: 20...100,
                step: 5,
                valueText: "\(Int((configuration.presentation.badgeOpacity * 100).rounded()))%",
                set: {
                    configuration.presentation.badgeOpacity = $0 / 100
                    save()
                }
            )
            SettingsDivider()
            SettingsSliderRow(
                Text("Group padding"),
                value: configuration.presentation.groupPadding,
                range: 0...32,
                step: 2,
                valueText: "\(Int(configuration.presentation.groupPadding)) pt",
                set: {
                    configuration.presentation.groupPadding = $0
                    save()
                }
            )
            SettingsDivider()
            SettingsRowPair {
                SettingsPickerRow(Text("Space title position"), selection: bind(\.presentation.spaceTitlePlacement)) {
                    ForEach(MissionControlPlacement.allCases, id: \.self) {
                        Text(verbatim: $0.rawValue.capitalized).tag($0)
                    }
                }
            } right: {
                SettingsPickerRow(Text("Badge position"), selection: bind(\.presentation.badgePlacement)) {
                    ForEach(MissionControlPlacement.allCases, id: \.self) {
                        Text(verbatim: $0.rawValue.capitalized).tag($0)
                    }
                }
            }
            SettingsDivider()
            SettingsRowPair {
                SettingsToggleRow(Text("Filter readout"), isOn: bind(\.presentation.showsFilterChip),
                                  note: Text("Shows the query and how many windows match while you type."))
            } right: {
                SettingsRow(Text("Accent colour")) {
                    ColorPicker(selection: Binding(
                        get: { Color(mission: configuration.presentation.accentFallback) },
                        set: {
                            configuration.presentation.accentFallback = $0.missionColor
                            save()
                        }
                    ), supportsOpacity: false) {
                        Text("Accent colour")
                    }
                    .labelsHidden()
                    .frame(width: 44)
                }
            }
        }
    }

    // MARK: Framing

    private var framingCard: some View {
        SettingsCard(Text("Framing")) {
            SettingsToggleRow(Text("Focus and hover frames"), isOn: bind(\.framing.isEnabled),
                              note: Text("The keyboard-targeted window takes the focus border; the window under the pointer takes the hover border."))
            if configuration.framing.isEnabled {
                SettingsDivider()
                SettingsRowPair {
                    SettingsPickerRow(Text("Focus border"), selection: bind(\.framing.focusStyle)) {
                        ForEach(MissionControlBorderStyle.allCases, id: \.self) {
                            Text(verbatim: $0.rawValue.capitalized).tag($0)
                        }
                    }
                } right: {
                    SettingsPickerRow(Text("Hover border"), selection: bind(\.framing.hoverStyle)) {
                        ForEach(MissionControlBorderStyle.allCases, id: \.self) {
                            Text(verbatim: $0.rawValue.capitalized).tag($0)
                        }
                    }
                }
                SettingsDivider()
                SettingsToggleRow(Text("Group frame around windows of one app"), isOn: bind(\.framing.showsGroupFrame))
                if configuration.framing.showsGroupFrame {
                    SettingsPickerRow(Text("Group border"), selection: bind(\.framing.groupStyle)) {
                        ForEach(MissionControlBorderStyle.allCases, id: \.self) {
                            Text(verbatim: $0.rawValue.capitalized).tag($0)
                        }
                    }
                }
                SettingsDivider()
                Text("Window state borders")
                    .font(.subheadline)
                ForEach(MissionControlWindowState.allCases, id: \.self) { state in
                    SettingsRow(Text(verbatim: state.rawValue.capitalized)) {
                        HStack(spacing: 8) {
                            Picker(selection: Binding(
                                get: { configuration.framing.stateStyles[state] ?? .none },
                                set: {
                                    configuration.framing.stateStyles[state] = $0
                                    save()
                                }
                            )) {
                                ForEach(MissionControlBorderStyle.allCases, id: \.self) {
                                    Text(verbatim: $0.rawValue.capitalized).tag($0)
                                }
                            } label: {
                                Text(verbatim: state.rawValue.capitalized)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            ColorPicker(selection: Binding(
                                get: { Color(mission: configuration.colouring.stateColors[state] ?? configuration.colouring.defaultColor) },
                                set: {
                                    configuration.colouring.stateColors[state] = $0.missionColor
                                    save()
                                }
                            ), supportsOpacity: false) {
                                Text(verbatim: state.rawValue.capitalized)
                            }
                            .labelsHidden()
                            .frame(width: 44)
                        }
                    }
                }
            }
        }
    }

    // MARK: Colouring

    private var colouringCard: some View {
        SettingsCard(Text("Colouring")) {
            SettingsToggleRow(Text("Colour borders by app"), isOn: bind(\.colouring.isEnabled),
                              note: Text("Custom bundle-ID rules beat category colours, which beat the neutral default."))
            if configuration.colouring.isEnabled {
                SettingsDivider()
                SettingsToggleRow(Text("Assign colours by app category"), isOn: bind(\.colouring.autoAssignCategories),
                                  note: Text("On by default: browsers, code editors and terminals, comms, notes and media each start with their own colour. Change any category below, or add a bundle-ID rule that wins over it."))
                SettingsDivider()
                Text("Categories")
                    .font(.subheadline)
                ForEach(MissionControlAppCategory.allCases, id: \.self) { category in
                    SettingsRow(Text(verbatim: category.rawValue.capitalized)) {
                        ColorPicker(
                            selection: Binding(
                                get: { Color(mission: colour(for: category)) },
                                set: {
                                    setCategoryColour($0.missionColor, for: category)
                                }
                            ),
                            supportsOpacity: false
                        ) {
                            Text(verbatim: category.rawValue.capitalized)
                        }
                        .labelsHidden()
                    }
                }
                SettingsDivider()
                SettingsSliderRow(
                    Text("Thumbnail tint"),
                    value: configuration.colouring.tintOpacity * 100,
                    range: 0...50,
                    step: 1,
                    valueText: "\(Int((configuration.colouring.tintOpacity * 100).rounded()))%",
                    note: Text("A low-opacity wash over each thumbnail. It needs Screen Recording; without it, borders and badges still draw."),
                    set: {
                        configuration.colouring.tintOpacity = $0 / 100
                        save()
                    }
                )
                SettingsDivider()
                Text("Custom bundle-ID rules")
                    .font(.subheadline)
                ForEach(configuration.colouring.rules) { rule in
                    SettingsRow(Text(verbatim: ruleLabel(rule))) {
                        HStack(spacing: 8) {
                            ColorPicker(
                                selection: Binding(
                                    get: { Color(mission: rule.color) },
                                    set: {
                                        guard let index = configuration.colouring.rules.firstIndex(where: { $0.id == rule.id })
                                        else { return }
                                        configuration.colouring.rules[index].color = $0.missionColor
                                        save()
                                    }
                                ),
                                supportsOpacity: false
                            ) {
                                Text(verbatim: ruleLabel(rule))
                            }
                            .labelsHidden()
                            Button {
                                configuration.colouring.rules.removeAll { $0.id == rule.id }
                                save()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Remove rule"))
                        }
                    }
                }
                SettingsDivider()
                SettingsRow(Text("Add a bundle-ID rule")) {
                    HStack(spacing: 8) {
                        TextField("com.example.app", text: $newBundleID)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                        ColorPicker("Rule colour", selection: Binding(
                            get: { Color(mission: newRuleColor) },
                            set: { newRuleColor = $0.missionColor }
                        ), supportsOpacity: false)
                        .labelsHidden()
                        .accessibilityLabel(Text("Rule colour"))
                        Button("Add") {
                            let id = newBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !id.isEmpty else { return }
                            configuration.colouring.rules.append(
                                MissionControlColorRule(match: .bundleID(id), color: newRuleColor)
                            )
                            newBundleID = ""
                            save()
                        }
                        .buttonStyle(SettingsGelButtonStyle())
                        .disabled(newBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                SettingsDivider()
                SettingsToggleRow(Text("Colour the Space title pill"), isOn: bind(\.colouring.showsSpaceAccents))
            }
        }
    }

    private func colour(for category: MissionControlAppCategory) -> MissionControlColor {
        configuration.colouring.rules.first {
            if case .category(let wanted) = $0.match { return wanted == category }
            return false
        }?.color ?? category.defaultColor
    }

    private func setCategoryColour(_ colour: MissionControlColor, for category: MissionControlAppCategory) {
        if let index = configuration.colouring.rules.firstIndex(where: {
            if case .category(let wanted) = $0.match { return wanted == category }
            return false
        }) {
            configuration.colouring.rules[index].color = colour
        } else {
            configuration.colouring.rules.append(
                MissionControlColorRule(match: .category(category), color: colour)
            )
        }
        save()
    }

    private func ruleLabel(_ rule: MissionControlColorRule) -> String {
        switch rule.match {
        case .bundleID(let id): return id
        case .category(let category): return category.rawValue.capitalized
        }
    }

    // MARK: Actions

    private var actionsCard: some View {
        SettingsCard(Text("Actions, Keys & Mouse")) {
            Text("Hover buttons")
                .font(.subheadline)
            ForEach(MissionControlWindowAction.allCases, id: \.self) { action in
                SettingsCheckboxRow(
                    Text(verbatim: actionLabel(action)),
                    isOn: Binding(
                        get: { configuration.actions.buttons.isVisible(action) },
                        set: {
                            configuration.actions.buttons.visible[action] = $0
                            save()
                        }
                    )
                )
            }
            SettingsDivider()
            SettingsToggleRow(Text("Show the cluster only while hovering"), isOn: bind(\.actions.buttons.showsOnHover))
            SettingsDivider()
            SettingsToggleRow(Text("Hover keyboard shortcuts"), isOn: bind(\.actions.hoverKeys.isEnabled),
                              note: Text("The keys act on the window under the pointer without leaving the overview. A shortcut is taken only with exactly these modifiers, so the app's own ⌘⇧ shortcuts still work."))
            if configuration.actions.hoverKeys.isEnabled {
                SettingsDivider()
                Text("Modifiers")
                    .font(.subheadline)
                HStack(spacing: 14) {
                    ForEach(MissionControlModifier.allCases, id: \.self) { modifier in
                        Toggle(isOn: Binding(
                            get: { configuration.actions.hoverKeys.modifiers.contains(modifier) },
                            set: { on in
                                if on { configuration.actions.hoverKeys.modifiers.insert(modifier) }
                                else { configuration.actions.hoverKeys.modifiers.remove(modifier) }
                                save()
                            }
                        )) {
                            Text(verbatim: modifier.rawValue.capitalized)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                ForEach(MissionControlWindowAction.allCases, id: \.self) { action in
                    SettingsRow(Text(verbatim: actionLabel(action))) {
                        TextField(
                            "Key",
                            text: Binding(
                                get: { configuration.actions.hoverKeys.keys[action] ?? action.defaultKey },
                                set: {
                                    configuration.actions.hoverKeys.keys[action] =
                                        String($0.suffix(1)).lowercased()
                                    save()
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(width: 44)
                    }
                }
            }
            SettingsDivider()
            SettingsRowPair {
                SettingsPickerRow(Text("Right-click action"), selection: bind(\.actions.mouse.rightClick)) {
                    ForEach(MissionControlMouseBindings.Binding.allCases, id: \.self) {
                        Text(verbatim: $0.rawValue.capitalized).tag($0)
                    }
                }
            } right: {
                SettingsPickerRow(Text("Middle-click action"), selection: bind(\.actions.mouse.middleClick)) {
                    ForEach(MissionControlMouseBindings.Binding.allCases, id: \.self) {
                        Text(verbatim: $0.rawValue.capitalized).tag($0)
                    }
                }
            }
            SettingsDivider()
            SettingsButtonRow(Text("Reset Mission Control Settings")) {
                configuration = MissionControlConfiguration()
                save()
            }
        }
    }

    private func actionLabel(_ action: MissionControlWindowAction) -> String {
        switch action {
        case .close: return String(localized: "Close")
        case .minimize: return String(localized: "Minimize")
        case .zoom: return String(localized: "Zoom")
        case .hide: return String(localized: "Hide")
        case .quit: return String(localized: "Quit")
        }
    }

    // MARK: Plumbing

    private func bind<Value>(_ keyPath: WritableKeyPath<MissionControlConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: { configuration[keyPath: keyPath] },
            set: {
                configuration[keyPath: keyPath] = $0
                save()
            }
        )
    }

    private func save() {
        MissionControlSettings.save(configuration)
    }

    private func refreshReadiness() {
        let probe = MissionControlDockProbe.probe()
        let listenAccess = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        readiness = MissionControlReadiness(
            accessibility: AXIsProcessTrusted() ? .granted : .denied,
            screenRecording: CGPreflightScreenCaptureAccess() ? .granted : .denied,
            detection: probe.dockReadable ? .granted : .unsupported,
            inputMonitoring: {
                switch listenAccess {
                case kIOHIDAccessTypeGranted: return .granted
                case kIOHIDAccessTypeDenied: return .denied
                default: return .unknown
                }
            }()
        )
    }

}

private extension Color {
    init(mission: MissionControlColor) {
        self.init(.sRGB, red: mission.red, green: mission.green, blue: mission.blue, opacity: mission.alpha)
    }
}

private extension Color {
    var missionColor: MissionControlColor {
        let resolved = NSColor(self).usingColorSpace(.sRGB) ?? .systemOrange
        return MissionControlColor(
            red: Double(resolved.redComponent),
            green: Double(resolved.greenComponent),
            blue: Double(resolved.blueComponent),
            alpha: Double(resolved.alphaComponent)
        )
    }
}
