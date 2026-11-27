import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Phase 12 — how the widget panes look (layout, colours, clock, glass, theme) and the style
/// presets that go with them. The dock's own list moved to the Dock Items tab, and the weather
/// rows to the Weather tab (2026-10-20 split).
/// Renders through the shared card/row system (`SettingsCard.swift`, `Docs/SETTINGS.md` rule 2) and
/// gives the page at most three sections (rule 5).
struct WidgetLookSettingsBlock: View {
    @ObservedObject var store: AppSettingsStore

    // Moved here from `SettingsLayoutPane` (2026-10-15): the style presets are appearance, and the
    // pane's extra card made the page four sections. Same keys, same controls.
    // These four came with the weather block (2026-10-15): they are about the widget tiles
    // themselves — the animation they use and whether the notes and stopwatch tiles exist — so they
    // sit with the rest of the appearance rows, not under the weather warning thresholds.
    @AppStorage(WidgetAnimationPreset.storageKey) private var widgetAnimation: WidgetAnimationPreset = .slide
    @AppStorage(NowPlayingOpenTap.doubleTapKey) private var openNeedsDoubleTap = false
    @AppStorage(NowPlayingArtworkAccent.key) private var artworkAccent = true
    @AppStorage(WidgetExtraPrefs.showNotesKey) private var showNotes = true
    @AppStorage(WidgetExtraPrefs.showStopwatchKey) private var showStopwatch = true
    @AppStorage(WidgetExtraPrefs.showYearKey) private var showYear = false
    @AppStorage(WidgetPanelController.keepBothOpenKey) private var keepBoth = false

    @AppStorage(WidgetLook.storageKey) private var lookRaw = WidgetLook.default.rawValue
    @AppStorage("com.katikati.clock.preset") private var clockPresetRaw: String = ClockPreset.stackedCard.rawValue
    @AppStorage("com.katikati.media.preset") private var mediaPresetRaw: String = NowPlayingPreset.accentCard.rawValue
    @AppStorage(CalendarLookaheadHorizon.defaultsKey) private var lookaheadRaw: Int = CalendarLookaheadHorizon.defaultPreset.rawValue
    @AppStorage(CalendarDockAction.singleClickKey) private var calendarSingleClick: CalendarDockAction = .togglePanel
    @AppStorage(CalendarDockAction.doubleClickKey) private var calendarDoubleClick: CalendarDockAction = .openCalendarApp
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            SettingsCard(Text("Widget Appearance")) {
                // Menus and switches, two rows per line (`Docs/SETTINGS.md` rule 5): this card was
                // ten rows deep, one narrow control each.
                SettingsPickerRow(Text("Widget Look"), selection: $lookRaw) {
                    Text("Classic").tag(WidgetLook.classic.rawValue)
                    Text("Tiles").tag(WidgetLook.tiles.rawValue)
                }
                SettingsDivider()
                SettingsRowPair(
                    left: { SettingsRow(Text("Widget Layout")) { CalendarLayoutPicker() } },
                    right: { SettingsRow(Text("Widget Colors")) { CalendarPalettePicker() } }
                )
                SettingsDivider()
                SettingsRowPair(
                    // Not the dock clock's preset (that is "Clock Style" further down): this one is
                    // the clock *tile*'s look. Two rows with one name was a defect, not a style choice.
                    left: { SettingsRow(Text("Clock Tile Style")) { CalendarClockStylePicker() } },
                    right: { SettingsRow(Text("Glass")) { GlassTilesToggle().accessibilityLabel(Text("Glass")) } }
                )
                SettingsDivider()
                SettingsRow(Text("Now Playing Click")) {
                    Picker("Now Playing Click", selection: $store.nowPlayingTapPreset) {
                        ForEach(NowPlayingTapPreset.allCases, id: \.self) { Text($0.displayTitle) }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                SettingsDivider()
                SettingsRow(Text(verbatim: "Open Player App: Double-Click")) {
                    Toggle(isOn: $openNeedsDoubleTap) { Text(verbatim: "Open Player App: Double-Click") }.labelsHidden()
                }
                SettingsDivider()
                SettingsRow(Text(verbatim: "Accent From Artwork")) {
                    Toggle(isOn: $artworkAccent) { Text(verbatim: "Accent From Artwork") }.labelsHidden()
                }
                SettingsDivider()
                SettingsRowPair(
                    left: {
                        SettingsRow(Text("Now Playing Theme")) {
                            Picker("Now Playing Theme", selection: $store.nowPlayingTheme) {
                                ForEach(NowPlayingTheme.allCases, id: \.self) { Text($0.displayTitle) }
                            }
                            .labelsHidden().pickerStyle(.menu).fixedSize()
                        }
                    },
                    right: {
                        SettingsPickerRow(Text("Widget Animation"), selection: $widgetAnimation) {
                            Text("Instant").tag(WidgetAnimationPreset.instant)
                            Text("Slide").tag(WidgetAnimationPreset.slide)
                            Text("Spring Pop").tag(WidgetAnimationPreset.springPop)
                        }
                    }
                )
                SettingsDivider()
                SettingsRowPair(
                    left: { SettingsToggleRow(Text("Show Notes Widget"), isOn: $showNotes) },
                    right: { SettingsToggleRow(Text("Show Stopwatch & Countdown"), isOn: $showStopwatch) }
                )
                SettingsDivider()
                SettingsToggleRow(Text("Show Year Progress (Tall layout)"), isOn: $showYear)
                SettingsDivider()
                SettingsToggleRow(Text("Keep Both Widgets Open"), isOn: $keepBoth)
                SettingsDivider()
                // The group's name with its ⓘ beside it, as a sub-header rather than a row
                // (2026-10-15): it carries no control, and a label spending a whole 41 pt row was
                // 41 pt of a page that has to fit the window. The explanation is unchanged.
                HStack(spacing: 6) {
                    Text("Widget Styles & Presets").font(.subheadline)
                    SettingsInfoButton(text: String(localized: "Switch between custom Phase 32 pods and legacy widget presets. You can also switch styles by right-clicking each widget on the dock."))
                }
                SettingsRowPair(
                    left: {
                        SettingsRow(Text("Clock Style")) {
                            Picker("Clock Style", selection: $clockPresetRaw) {
                                ForEach(ClockPreset.allCases, id: \.rawValue) { preset in
                                    Text(preset.title).tag(preset.rawValue)
                                }
                            }
                            .labelsHidden().pickerStyle(.menu).fixedSize()
                        }
                    },
                    right: {
                        SettingsRow(Text("Now Playing Style")) {
                            Picker("Now Playing Style", selection: $mediaPresetRaw) {
                                ForEach(NowPlayingPreset.allCases, id: \.rawValue) { preset in
                                    Text(preset.title).tag(preset.rawValue)
                                }
                            }
                            .labelsHidden().pickerStyle(.menu).fixedSize()
                        }
                    }
                )
                SettingsDivider()
                SettingsRow(Text("Calendar Lookahead (1–3)")) {
                    Picker("Calendar Lookahead", selection: $lookaheadRaw) {
                        ForEach(CalendarLookaheadHorizon.allCases) { h in
                            Text(verbatim: h.localizedTitle).tag(h.rawValue)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                    .onChange(of: lookaheadRaw) { _ in
                        ProductivityServices.shared.calendar.refreshUpcoming()
                    }
                }
                SettingsDivider()
                SettingsRowPair(
                    left: {
                        SettingsRow(Text("Calendar Click")) {
                            Picker("Calendar Click", selection: $calendarSingleClick) {
                                ForEach(CalendarDockAction.allCases) { a in Text(verbatim: a.localizedTitle).tag(a) }
                            }
                            .labelsHidden().pickerStyle(.menu).fixedSize()
                        }
                    },
                    right: {
                        SettingsRow(Text("Calendar Double-Click")) {
                            Picker("Calendar Double-Click", selection: $calendarDoubleClick) {
                                ForEach(CalendarDockAction.allCases) { a in Text(verbatim: a.localizedTitle).tag(a) }
                            }
                            .labelsHidden().pickerStyle(.menu).fixedSize()
                        }
                    }
                )
            }
        }
    }
}

/// Dedicated Widget Wings tab (`Dock II Wings & Widgets` + Floating Widget Stack configuration sheet).
struct WidgetWingsSettingsBlock: View {
    @ObservedObject var store: AppSettingsStore
    @State private var showDockIISheet = false
    @State private var selectedDisplayUUID: String?

    var body: some View {
        SettingsCard(Text("Dock II Wings & Widgets")) {
            if NSScreen.screens.count > 1 {
                SettingsRow(Text("Desktop")) {
                    Picker("Desktop", selection: $selectedDisplayUUID) {
                        Text("All").tag(String?.none)
                        ForEach(NSScreen.screens, id: \.self) { screen in
                            Text(screen.localizedName).tag(DisplayIdentity.uuidString(for: screen))
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                SettingsDivider()
            }
            wingConfigRow(Text("Left Wing"), placement: .leftWing)
            SettingsDivider()
            wingConfigRow(Text("Right Wing"), placement: .rightWing)
            SettingsDivider()
            SettingsSliderRow(
                Text("Wing Spacing"),
                value: store.dockWings.gap,
                range: DockWingsConfiguration.minGap...DockWingsConfiguration.maxGap,
                step: 1
            ) {
                store.setDockWingGap($0)
            }
            SettingsDivider()
            SettingsRow(Text("Pins, Friends & Integrations")) {
                HStack(spacing: 8) {
                    Button("Configure…") {
                        showDockIISheet = true
                    }
                    .controlSize(.small)
                    if store.dockWings.hasAnyActiveWing {
                        Button("Reset Wings") {
                            store.resetDockWings()
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .sheet(isPresented: $showDockIISheet) {
            DockIIConfigureSheet(store: store)
        }
    }

    private func wingConfigRow(_ label: Text, placement: DockWingPlacement) -> some View {
        let slot = selectedDisplayUUID == nil
            ? store.dockWings.slot(for: placement)
            : store.dockWings.resolved(displayUUID: selectedDisplayUUID).slot(for: placement)
        return SettingsRow(label) {
            HStack(spacing: 8) {
                Picker("Preset", selection: Binding(
                    get: { slot.preset },
                    set: { store.setDockWing($0, placement: placement, forDisplay: selectedDisplayUUID) }
                )) {
                    ForEach(DockWidgetPresetType.allCases) { preset in
                        Text(verbatim: preset.localizedTitle).tag(preset)
                    }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()

                Picker("Size", selection: Binding(
                    get: { slot.size },
                    set: { store.setDockWingSize($0, placement: placement, forDisplay: selectedDisplayUUID) }
                )) {
                    Text("Small").tag(WidgetSize.small)
                    Text("Medium").tag(WidgetSize.medium)
                    Text("Large").tag(WidgetSize.large)
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
                .disabled(!slot.preset.isAssigned)
            }
        }
    }
}

/// Dedicated App Icons & Hover tab: instance presets, symmetrical spacing, anti-overflow resizing,
/// Dock App Groups, icon animations/running indicators, hover previews, and Pin-as-App-Icon menu toggle.
struct AppIconsSettingsBlock: View {
    @ObservedObject var store: AppSettingsStore
    @ObservedObject private var appGroupStore = DockAppGroupStore.shared
    @State private var newGroupName = ""
    @AppStorage(DockHoverAnimationStyle.defaultsKey) private var hoverAnimationRaw = DockHoverAnimationStyle.none.rawValue
    @AppStorage(DockPressAnimationStyle.defaultsKey) private var pressAnimationRaw = DockPressAnimationStyle.tactileSquish.rawValue
    @AppStorage(DockRunningIndicatorStyle.defaultsKey) private var runningIndicatorRaw = DockRunningIndicatorStyle.macDot.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            SettingsCard(Text("Icon Studio")) {
                SettingsButtonRow(
                    Text("Custom & Live Icons"),
                    note: Text("Style Dock and Command-Tab icons with custom artwork, shaders, badge effects, and live data.")
                ) {
                    IconStudioWindowController.shared.open()
                }
            }

            SettingsCard(Text("App Icon Presets")) {
                SettingsPickerRow(
                    Text("Running Apps Style"),
                    selection: Binding(get: { store.appIconPreset }, set: { store.setAppIconPreset($0) }),
                    note: Text("Vertical docks automatically default to Icons Only unless you pick a preset.")
                ) {
                    ForEach(AppIconPresentationPreset.allCases) { preset in
                        Text(verbatim: preset.localizedTitle).tag(preset)
                    }
                }
            }

            SettingsCard(Text("Spacing & Dynamic Resizing")) {
                SettingsSliderRow(
                    Text("Icon Spacing"),
                    value: store.dockSpacingConfig.iconSpacing,
                    range: DockSpacingConfig.iconSpacingRange,
                    step: 1,
                    valueText: "\(Int(store.dockSpacingConfig.iconSpacing)) pt"
                ) { val in
                    var cfg = store.dockSpacingConfig
                    cfg.iconSpacing = val
                    store.setDockSpacingConfig(cfg)
                }
                SettingsDivider()
                SettingsSliderRow(
                    Text("Section Spacing"),
                    value: store.dockSpacingConfig.sectionSpacing,
                    range: DockSpacingConfig.sectionSpacingRange,
                    step: 1,
                    valueText: "\(Int(store.dockSpacingConfig.sectionSpacing)) pt"
                ) { val in
                    var cfg = store.dockSpacingConfig
                    cfg.sectionSpacing = val
                    store.setDockSpacingConfig(cfg)
                }
                SettingsDivider()
                SettingsToggleRow(
                    Text("Dynamic Anti-Overflow Resizing"),
                    isOn: Binding(
                        get: { store.dockSpacingConfig.dynamicCompressionEnabled },
                        set: { enabled in
                            var cfg = store.dockSpacingConfig
                            cfg.dynamicCompressionEnabled = enabled
                            store.setDockSpacingConfig(cfg)
                        }
                    ),
                    note: Text("Automatically trims labels, gaps, and icon scale when many windows are open to reduce scrolling.")
                )
                SettingsDivider()
                HStack {
                    Spacer()
                    Button(LocalizedStringKey("Reset to Default")) {
                        store.setDockSpacingConfig(.default)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(store.dockSpacingConfig == .default)
                }
            }

            SettingsCard(Text("App Groups")) {
                SettingsToggleRow(
                    Text("Enable App Groups"),
                    isOn: Binding(get: { appGroupStore.isEnabled }, set: { appGroupStore.setEnabled($0) })
                )
                SettingsDivider()
                SettingsToggleRow(
                    Text("Sync with Launcher Folders"),
                    isOn: Binding(get: { appGroupStore.syncWithLauncherFolders }, set: { appGroupStore.setSyncWithLauncher($0) })
                )
                SettingsDivider()
                SettingsButtonRow(
                    Text("Auto-Group Installed Apps"),
                    note: Text("Organizes installed apps into Dock folders by category.")
                ) {
                    appGroupStore.autoGroupInstalledApps()
                }
                SettingsDivider()
                HStack(spacing: 8) {
                    TextField(String(localized: "New group name"), text: $newGroupName)
                        .textFieldStyle(.roundedBorder)
                    Button(String(localized: "Add Group")) {
                        let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                        appGroupStore.createGroup(name: name.isEmpty ? String(localized: "Workspace") : name)
                        newGroupName = ""
                    }
                    .controlSize(.small)
                }
                ForEach(appGroupStore.groups) { group in
                    SettingsDivider()
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            TextField(
                                String(localized: "Group Name"),
                                text: Binding(
                                    get: { group.name },
                                    set: { appGroupStore.renameGroup(group.id, to: $0) }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 160)
                            Picker(String(localized: "Icon Grid"), selection: Binding(
                                get: { group.iconGrid },
                                set: { appGroupStore.setIconGrid($0, for: group.id) }
                            )) {
                                Text(verbatim: "2×2").tag(DockAppGroupIconGrid.grid2x2)
                                Text(verbatim: "3×3").tag(DockAppGroupIconGrid.grid3x3)
                            }
                            .labelsHidden().pickerStyle(.segmented).fixedSize()
                            Spacer(minLength: 4)
                            Button(role: .destructive) {
                                appGroupStore.deleteGroup(group.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Delete Group"))
                        }
                        if !group.appIDs.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(group.appIDs, id: \.self) { appID in
                                        HStack(spacing: 4) {
                                            Text(verbatim: appID.components(separatedBy: ".").last ?? appID)
                                                .font(.caption2)
                                            Button {
                                                appGroupStore.removeApp(appID, from: group.id)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                                    }
                                }
                            }
                        }
                    }
                }
            }

            SettingsCard(Text("Icon Feedback & Hover")) {
                SettingsSegmentedRow(Text("Icon Set"), selection: Binding(get: { store.iconSet }, set: store.setIconSet)) {
                    Text("System").tag(IconSet.system)
                    Text("Modern").tag(IconSet.modern)
                    Text("Classic").tag(IconSet.classic)
                }
                SettingsDivider()
                SettingsRow(Text("Hover Animation")) {
                    Picker("Hover Animation", selection: $hoverAnimationRaw) {
                        ForEach(DockHoverAnimationStyle.allCases) { style in
                            SettingsLayoutPane.hoverAnimationTitle(style).tag(style.rawValue)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                SettingsDivider()
                SettingsRow(Text("Click Effect")) {
                    Picker("Click Effect", selection: $pressAnimationRaw) {
                        ForEach(DockPressAnimationStyle.allCases) { style in
                            SettingsLayoutPane.pressAnimationTitle(style).tag(style.rawValue)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                SettingsDivider()
                SettingsRow(Text("Running Indicator")) {
                    Picker("Running Indicator", selection: $runningIndicatorRaw) {
                        ForEach(DockRunningIndicatorStyle.allCases) { style in
                            SettingsLayoutPane.runningIndicatorTitle(style).tag(style.rawValue)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                SettingsDivider()
                SettingsToggleRow(
                    Text("Show app name on hover"),
                    isOn: Binding(get: { store.hoverStyle.isExpressive }, set: { store.setHoverStyle($0 ? .standard : .quiet) })
                )
                SettingsDivider()
                SettingsToggleRow(
                    Text("Show window previews on hover"),
                    isOn: Binding(get: { store.chipPreviewEnabled }, set: { store.setChipPreviewEnabled($0) })
                )
            }

            SettingsCard(Text("App Context Menu")) {
                SettingsToggleRow(
                    Text("Show 'Pin as App Icon' in app menus"),
                    isOn: Binding(get: { store.showPinAsAppIcon }, set: { store.setShowPinAsAppIcon($0) }),
                    note: Text("Keep in Dock is the default. Enable this legacy option to also show separate icon pinning.")
                )
            }
        }
    }
}

private struct DockIIConfigureSheet: View {
    @ObservedObject var store: AppSettingsStore
    @ObservedObject private var friendsStore = DockFriendsStore.shared
    @ObservedObject private var spotifyAuth = SpotifyAuthService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSurface: WidgetSurfaceKind = .drawer
    @State private var newFriendName = ""
    @State private var newFriendHandle = ""
    @State private var newFriendApp: DockFriendAppKind = .messages
    @State private var contactQuery = ""
    @State private var contactResults: [DockFriendsStore.ImportedContactCandidate] = []
    @State private var spotifyClientIDDraft = SpotifyAuthService.shared.clientID

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Dock II Widgets Configuration")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    surfacePinsSection
                    Divider()
                    friendsSection
                    Divider()
                    integrationsSection
                }
                .padding(.vertical, 4)
            }
        }
        .padding(18)
        .frame(width: 540, height: 560)
    }

    private var surfacePinsSection: some View {
        let surfaces: [WidgetSurfaceKind] = [.drawer, .shelfCard, .backgroundAppsPopup, .floatingStack]
        let items = store.surfaceWidgets.attachments(for: selectedSurface)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Surface Pins")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker("Surface", selection: $selectedSurface) {
                    ForEach(surfaces) { surface in
                        Text(verbatim: surface.localizedTitle).tag(surface)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }

            HStack(spacing: 6) {
                ForEach(DockWidgetPresetType.allCases.filter(\.isAssigned)) { preset in
                    let isPinned = store.surfaceWidgets.isPinned(preset, on: selectedSurface)
                    Button {
                        if isPinned {
                            store.unpinSurfaceWidget(preset, from: selectedSurface)
                        } else {
                            store.pinSurfaceWidget(preset, size: .medium, to: selectedSurface)
                        }
                    } label: {
                        Label(preset.localizedTitle, systemImage: isPinned ? "checkmark.circle.fill" : "plus.circle")
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }
            }

            if items.isEmpty {
                Text("No widgets pinned to this surface yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 8) {
                        Image(systemName: item.preset.symbolName)
                            .frame(width: 16)
                        Text(verbatim: item.preset.localizedTitle)
                        Spacer()
                        Picker("Size", selection: Binding(
                            get: { item.size },
                            set: { store.setSurfaceWidgetSize($0, for: item.preset, on: selectedSurface) }
                        )) {
                            Text("Small").tag(WidgetSize.small)
                            Text("Medium").tag(WidgetSize.medium)
                            Text("Large").tag(WidgetSize.large)
                        }
                        .labelsHidden().pickerStyle(.segmented).fixedSize()

                        Button {
                            store.toggleSurfaceWidgetCollapsed(for: item.preset, on: selectedSurface)
                        } label: {
                            Image(systemName: item.isCollapsed ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        }
                        .buttonStyle(.borderless)

                        Button {
                            guard index > 0 else { return }
                            store.moveSurfaceWidgets(on: selectedSurface, from: IndexSet(integer: index),
                                                     to: index - 1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)

                        Button {
                            guard index < items.count - 1 else { return }
                            store.moveSurfaceWidgets(on: selectedSurface, from: IndexSet(integer: index),
                                                     to: index + 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == items.count - 1)

                        if selectedSurface != .floatingStack {
                            Button("Float") {
                                store.tearOffSurfaceWidget(item.preset, from: selectedSurface)
                            }
                            .controlSize(.small)
                        }

                        Button {
                            store.unpinSurfaceWidget(item.preset, from: selectedSurface)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Friends HUD Contacts")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                TextField("Name", text: $newFriendName)
                    .textFieldStyle(.roundedBorder)
                TextField("Phone, email, or handle", text: $newFriendHandle)
                    .textFieldStyle(.roundedBorder)
                Picker("App", selection: $newFriendApp) {
                    ForEach(DockFriendAppKind.allCases) { app in
                        Text(verbatim: app.localizedTitle).tag(app)
                    }
                }
                .labelsHidden().fixedSize()
                Button("Add") {
                    let trimmed = newFriendName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    friendsStore.addFriend(DockFriendContact(
                        displayName: trimmed,
                        handle: newFriendHandle.trimmingCharacters(in: .whitespacesAndNewlines),
                        preferredApp: newFriendApp,
                        accentIndex: friendsStore.friends.count
                    ))
                    newFriendName = ""
                    newFriendHandle = ""
                }
                .disabled(newFriendName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if store.dockWingFriendsContactsEnabled {
                HStack(spacing: 8) {
                    TextField("Search macOS Contacts", text: $contactQuery)
                        .textFieldStyle(.roundedBorder)
                    Button("Import Contacts") {
                        Task {
                            contactResults = await friendsStore.searchSystemContacts(query: contactQuery)
                        }
                    }
                    .controlSize(.small)
                }
                if !contactResults.isEmpty {
                    ForEach(contactResults.prefix(5)) { candidate in
                        HStack {
                            Text(verbatim: candidate.displayName)
                            Text(verbatim: candidate.handle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Add") {
                                friendsStore.addFriend(
                                    DockFriendContact(
                                        displayName: candidate.displayName,
                                        handle: candidate.handle,
                                        preferredApp: .messages,
                                        accentIndex: friendsStore.friends.count
                                    ),
                                    avatarData: candidate.thumbnailData
                                )
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }

            ForEach(friendsStore.friends) { friend in
                HStack(spacing: 8) {
                    Text(verbatim: friend.displayName)
                        .font(.body.weight(.medium))
                    Text(verbatim: friend.preferredApp.localizedTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Speaking", isOn: Binding(
                        get: { friend.isSpeaking },
                        set: {
                            var copy = friend
                            copy.isSpeaking = $0
                            friendsStore.updateFriend(copy)
                        }
                    ))
                    .toggleStyle(.checkbox)
                    Button {
                        friendsStore.removeFriend(id: friend.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var integrationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Opt-In Integrations")
                .font(.subheadline.weight(.semibold))

            Toggle("VPN City & Flag Lookup (GeoIP)", isOn: Binding(
                get: { store.dockWingGeoIPEnabled },
                set: { store.setDockWingGeoIPEnabled($0) }
            ))

            Toggle("Apple Silicon Thermal Sensors (IOHID)", isOn: Binding(
                get: { store.dockWingTelemetryIOHIDEnabled },
                set: { store.setDockWingTelemetryIOHIDEnabled($0) }
            ))

            Toggle("Contacts Access (Friends HUD)", isOn: Binding(
                get: { store.dockWingFriendsContactsEnabled },
                set: { store.setDockWingFriendsContactsEnabled($0) }
            ))

            Toggle("Spotify Library Like (OAuth PKCE)", isOn: Binding(
                get: { store.dockWingSpotifyOAuthEnabled },
                set: { store.setDockWingSpotifyOAuthEnabled($0) }
            ))

            if store.dockWingSpotifyOAuthEnabled {
                HStack(spacing: 8) {
                    TextField("Spotify Client ID", text: $spotifyClientIDDraft)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: spotifyClientIDDraft) { spotifyAuth.clientID = $0 }
                    if spotifyAuth.isSignedIn {
                        Button("Sign Out") { spotifyAuth.signOut() }
                            .controlSize(.small)
                    } else {
                        Button("Sign In") {
                            spotifyAuth.clientID = spotifyClientIDDraft
                            spotifyAuth.signIn()
                        }
                        .controlSize(.small)
                        .disabled(spotifyClientIDDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if let err = spotifyAuth.lastError {
                    Text(verbatim: err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

// MARK: - IS-5.1 Icon Studio Window & 3-Column Stage

enum IconStudioBackdropMode: String, CaseIterable, Identifiable {
    case light, dark, wallpaper
    var id: String { rawValue }
}

@MainActor
final class IconStudioWindowController: NSObject, ObservableObject {
    static let shared = IconStudioWindowController()
    @Published var selectedBundleID: String = LiveIconKind.claude.defaultBundleID
    private var window: NSWindow?

    func open(selectedBundleID: String? = nil) {
        if let selectedBundleID, !selectedBundleID.isEmpty { self.selectedBundleID = selectedBundleID }
        if let existing = window { existing.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let win = NSWindow(contentViewController: NSHostingController(rootView: IconStudioWindowView(controller: self)))
        win.title = String(localized: "Icon Studio")
        win.setContentSize(NSSize(width: 960, height: 660))
        win.minSize = NSSize(width: 820, height: 560)
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.isReleasedWhenClosed = false
        win.center(); win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }
}

struct IconStudioWindowView: View {
    @ObservedObject var controller: IconStudioWindowController
    @ObservedObject private var studio = IconStudioController.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""
    @State private var backdrop: IconStudioBackdropMode = .dark
    @State private var showMiniDock = false
    @State private var useExamplePct = false
    @State private var examplePct: Double = 65
    @State private var isDropTargeted = false
    @State private var showPrefsPopover = false
    @State private var apiKeyDraft = UserDefaults.standard.string(forKey: IconStudioDefaultsKeys.macOSIconsAPIKey) ?? ""

    private var filteredLive: [LiveIconKind] {
        LiveIconKind.allCases.filter {
            searchText.isEmpty || AppDisplayNameResolver.displayName(for: $0.defaultBundleID).localizedCaseInsensitiveContains(searchText)
                || $0.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var customBundleIDs: [String] {
        let liveSet = Set(LiveIconKind.allCases.map(\.defaultBundleID))
        return studio.state.looksByBundleID.keys
            .filter { !liveSet.contains($0) && (searchText.isEmpty || AppDisplayNameResolver.displayName(for: $0).localizedCaseInsensitiveContains(searchText)) }
            .sorted()
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebarColumn.frame(width: 218)
            Divider()
            stageColumn.frame(minWidth: 340, maxWidth: .infinity)
            Divider()
            IconStudioInspectorColumn(bundleID: controller.selectedBundleID, studio: studio, examplePct: useExamplePct ? examplePct : nil)
                .frame(width: 332)
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(.windowBackground)
        .onChange(of: useExamplePct) { on in studio.liveOverrides[controller.selectedBundleID] = on ? examplePct : nil }
        .onChange(of: examplePct) { val in if useExamplePct { studio.liveOverrides[controller.selectedBundleID] = val } }
    }

    private var sidebarColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
                TextField("Search apps", text: $searchText).textFieldStyle(.plain).font(.system(size: 12))
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(10)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Text("Live").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1.5)
                                .background(Color(red: 0.92, green: 0.22, blue: 0.22), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            Text("Live icons").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        ForEach(filteredLive) { kind in
                            sidebarRow(bundleID: kind.defaultBundleID, subtitle: kind.supportsOptInActivityProbe ? String(localized: "Opt-in activity") : String(localized: "Live data"))
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Custom icons").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 8)
                        if customBundleIDs.isEmpty {
                            Text("Drop artwork or click + Add App to style any app icon.")
                                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 6)
                        } else {
                            ForEach(customBundleIDs, id: \.self) { sidebarRow(bundleID: $0, subtitle: String(localized: "Customized")) }
                        }
                    }
                }
                .padding(.horizontal, 6).padding(.bottom, 10)
            }
            Divider()
            HStack {
                Button { pickAppFromDisk() } label: { Label("Add App", systemImage: "plus").font(.system(size: 12, weight: .medium)) }.buttonStyle(.borderless)
                Spacer()
                Button { showPrefsPopover.toggle() } label: { Image(systemName: "gearshape").font(.system(size: 12)) }.buttonStyle(.borderless)
                    .popover(isPresented: $showPrefsPopover, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("macOSicons API Key (Optional)").font(.system(size: 12, weight: .semibold))
                            SecureField("x-api-key", text: $apiKeyDraft).textFieldStyle(.roundedBorder).frame(width: 240)
                                .onChange(of: apiKeyDraft) { UserDefaults.standard.set($0, forKey: IconStudioDefaultsKeys.macOSIconsAPIKey) }
                            Text("Required only for online macOSicons search. PNG, ICNS, and .icon drop work offline.")
                                .font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 240, alignment: .leading)
                        }
                        .padding(12)
                    }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.03))
    }

    private func sidebarRow(bundleID: String, subtitle: String) -> some View {
        let selected = controller.selectedBundleID == bundleID
        return Button { controller.selectedBundleID = bundleID } label: {
            HStack(spacing: 8) {
                IconStudioIconView(bundleID: bundleID, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: AppDisplayNameResolver.displayName(for: bundleID)).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(verbatim: subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? Color.accentColor.opacity(0.18) : .clear))
        }
        .buttonStyle(.plain)
    }

    private var stageColumn: some View {
        let bid = controller.selectedBundleID
        let hasLook = studio.look(for: bid) != nil
        return VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: AppDisplayNameResolver.displayName(for: bid)).font(.system(size: 20, weight: .bold))
            ZStack(alignment: .topTrailing) {
                stageCanvasBackdrop
                    .overlay {
                        VStack(spacing: 14) {
                            IconStudioIconView(
                                bundleID: bid, size: 152, isHovered: true,
                                badgeText: studio.previewBadgeOverride ? "8" : nil,
                                previewPercentOverride: useExamplePct ? examplePct : nil
                            )
                            .overlay(alignment: .topTrailing) {
                                if studio.previewBadgeOverride { ChipBadgeView(text: "8", scale: 2.2, effect: studio.badgeEffect(for: bid)) }
                            }
                            HStack(spacing: 10) {
                                IconStudioIconView(
                                    bundleID: bid, size: 40, isHovered: true,
                                    badgeText: studio.previewBadgeOverride ? "8" : nil,
                                    previewPercentOverride: useExamplePct ? examplePct : nil
                                )
                                if showMiniDock {
                                    HStack(spacing: 6) {
                                        ForEach([LiveIconKind.claude.defaultBundleID, bid, LiveIconKind.spotify.defaultBundleID], id: \.self) {
                                            IconStudioIconView(bundleID: $0, size: 28)
                                        }
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(isDropTargeted ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isDropTargeted ? 2 : 1))
                    .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in handleDrop(providers, for: bid) }

                Button { exportCurrentIconPNG(bundleID: bid) } label: {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 12, weight: .medium)).padding(7).background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain).help(Text("Export PNG")).padding(10)
            }
            .frame(maxWidth: .infinity, minHeight: 270, maxHeight: 330)

            Text("Drop a PNG, ICNS, or .icon here").font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center)
            Picker("Stage Backdrop", selection: $backdrop) {
                Text("Light").tag(IconStudioBackdropMode.light)
                Text("Dark").tag(IconStudioBackdropMode.dark)
                Text("Wallpaper").tag(IconStudioBackdropMode.wallpaper)
            }
            .labelsHidden().pickerStyle(.segmented).frame(maxWidth: 260).frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Show Dock and Command-Tab", isOn: $showMiniDock).toggleStyle(.checkbox).font(.system(size: 12))
                HStack(spacing: 8) {
                    Toggle("Try an example percentage", isOn: $useExamplePct).toggleStyle(.checkbox).font(.system(size: 12))
                    if useExamplePct {
                        Slider(value: $examplePct, in: 0...100, step: 1).frame(width: 110)
                        Text(verbatim: "\(Int(examplePct))%").font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                Toggle("Show Dock badge", isOn: $studio.previewBadgeOverride).toggleStyle(.checkbox).font(.system(size: 12))
            }
            Spacer(minLength: 0)
            Button("Restore Original Icon") { studio.restoreOriginal(for: bid) }.controlSize(.small).disabled(!hasLook)
        }
        .padding(16)
    }

    @ViewBuilder
    private var stageCanvasBackdrop: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        switch backdrop {
        case .light: shape.fill(Color(white: 0.94))
        case .dark: shape.fill(Color(white: 0.08))
        case .wallpaper:
            if let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen), let ns = NSImage(contentsOf: url) {
                Image(nsImage: ns).resizable().aspectRatio(contentMode: .fill).clipShape(shape)
            } else {
                shape.fill(LinearGradient(colors: [.indigo.opacity(0.65), .purple.opacity(0.45), .black], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
    }

    private func pickAppFromDisk() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let bid = Bundle(url: url)?.bundleIdentifier else { return }
        if studio.look(for: bid) == nil { studio.setLook(IconLook(shader: IconShaderSpec(preset: .gloss, strength: 0.5)), for: bid) }
        controller.selectedBundleID = bid
    }

    private func handleDrop(_ providers: [NSItemProvider], for bundleID: String) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in _ = studio.importArtwork(from: url, for: bundleID) }
        }
        return true
    }

    private func exportCurrentIconPNG(bundleID: String) {
        let view = IconStudioIconView(bundleID: bundleID, size: 512, isHovered: true, previewPercentOverride: useExamplePct ? examplePct : nil)
        let renderer = ImageRenderer(content: view); renderer.scale = 1
        guard let cg = renderer.cgImage, let png = IconAssetLoader.pngData(from: cg) else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "\(AppDisplayNameResolver.displayName(for: bundleID))-Icon.png"
        if panel.runModal() == .OK, let url = panel.url { try? png.write(to: url, options: .atomic) }
    }
}

struct IconStudioInspectorColumn: View {
    let bundleID: String
    @ObservedObject var studio: IconStudioController
    let examplePct: Double?

    @State private var openSections: Set<String> = ["live"]
    @State private var showSaveLook = false
    @State private var lookNameDraft = ""
    @State private var showMacOSIcons = false
    @State private var tintColor: Color = .accentColor

    private var look: IconLook { studio.look(for: bundleID) ?? IconLook() }
    private var liveKind: LiveIconKind? { LiveIconKind.allCases.first { $0.defaultBundleID == bundleID } }

    private func updateLook(_ mutate: (inout IconLook) -> Void) {
        var next = look
        mutate(&next)
        studio.setLook(next, for: bundleID)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let kind = liveKind { liveHeaderCard(kind) }

                    HStack {
                        Text("Appearance").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button("Save Look…") { lookNameDraft = ""; showSaveLook = true }
                            .controlSize(.small)
                            .popover(isPresented: $showSaveLook) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Save Look Preset").font(.system(size: 12, weight: .semibold))
                                    TextField("Preset name", text: $lookNameDraft).textFieldStyle(.roundedBorder).frame(width: 200)
                                    HStack {
                                        Spacer()
                                        Button("Save") {
                                            studio.savePreset(name: lookNameDraft, from: look)
                                            showSaveLook = false
                                        }
                                        .keyboardShortcut(.defaultAction).controlSize(.small)
                                    }
                                }
                                .padding(12)
                            }
                        Menu("Looks") {
                            if studio.state.savedPresets.isEmpty {
                                Text("No saved looks")
                            } else {
                                ForEach(studio.state.savedPresets) { preset in
                                    Button(preset.name) { studio.applyPreset(preset, to: bundleID) }
                                }
                                Divider()
                                Menu("Delete Look") {
                                    ForEach(studio.state.savedPresets) { preset in
                                        Button(preset.name, role: .destructive) { studio.deletePreset(id: preset.id) }
                                    }
                                }
                            }
                        }
                        .menuStyle(.borderedButton).controlSize(.small).fixedSize()
                    }

                    inspectorSection("badges", title: String(localized: "Badges"), summary: look.badgeEffect.kind == .none ? String(localized: "Off") : look.badgeEffect.kind.rawValue.capitalized) {
                        Picker("Effect", selection: Binding(get: { look.badgeEffect.kind }, set: { val in updateLook { $0.badgeEffect.kind = val } })) {
                            ForEach(IconBadgeEffectKind.allCases) { Text($0.rawValue.capitalized).tag($0) }
                        }
                        .pickerStyle(.menu)
                        if look.badgeEffect.kind != .none {
                            Stepper("Min unread: \(look.badgeEffect.minUnreadCount)", value: Binding(get: { look.badgeEffect.minUnreadCount }, set: { val in updateLook { $0.badgeEffect.minUnreadCount = max(1, val) } }), in: 1...99)
                                .font(.system(size: 11).monospacedDigit())
                        }
                    }

                    inspectorSection("artwork", title: String(localized: "Artwork"), summary: look.artwork.isCustom ? String(localized: "Custom") : String(localized: "Original")) {
                        HStack(spacing: 8) {
                            Button("Choose Image…") { pickCustomImage() }.controlSize(.small)
                            Button("Search macOSicons…") { showMacOSIcons = true }.controlSize(.small)
                            if look.artwork.isCustom {
                                Button("Reset") { updateLook { $0.artwork = .original } }.controlSize(.small)
                            }
                        }
                    }

                    inspectorSection("color", title: String(localized: "Color"), summary: look.recolor.isIdentity ? String(localized: "Original") : look.recolor.mode.rawValue.capitalized) {
                        Picker("Mode", selection: Binding(get: { look.recolor.mode }, set: { m in updateLook { $0.recolor.mode = m; if m != .original && $0.recolor.intensity == 0 { $0.recolor.intensity = 0.65 } } })) {
                            ForEach(IconRecolorSpec.Mode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        if look.recolor.mode != .original {
                            HStack {
                                ColorPicker("Tint", selection: $tintColor, supportsOpacity: false)
                                    .onChange(of: tintColor) { c in
                                        if let hex = hexString(from: c) { updateLook { $0.recolor.primaryHex = hex } }
                                    }
                                Slider(value: Binding(get: { look.recolor.intensity }, set: { v in updateLook { $0.recolor.intensity = v } }), in: 0...1)
                            }
                        }
                    }

                    inspectorSection("shaders", title: String(localized: "Shaders"), summary: look.shader.preset == .none ? String(localized: "None") : look.shader.preset.rawValue) {
                        Picker("Finish", selection: Binding(get: { look.shader.preset }, set: { p in updateLook { $0.shader.preset = p } })) {
                            ForEach(IconShaderPreset.allCases) { Text($0.rawValue).tag($0) }
                        }
                        if look.shader.preset != .none {
                            Slider(value: Binding(get: { look.shader.strength }, set: { v in updateLook { $0.shader.strength = v } }), in: 0...1) { Text("Strength") }
                            if look.shader.preset.isAnimated {
                                Picker("Animate", selection: Binding(get: { look.shader.trigger }, set: { t in updateLook { $0.shader.trigger = t } })) {
                                    Text("Hover").tag(IconAnimationTrigger.hover)
                                    Text("Active").tag(IconAnimationTrigger.active)
                                    Text("Off").tag(IconAnimationTrigger.off)
                                }.pickerStyle(.segmented)
                            }
                        }
                    }

                    inspectorSection("dressup", title: String(localized: "Dress Up"), summary: look.decorations.isEmpty ? String(localized: "None") : "\(look.decorations.count)") {
                        HStack(spacing: 6) {
                            ForEach(IconDecorationKind.allCases) { kind in
                                let active = look.decorations.contains { $0.kind == kind }
                                Button(kind.rawValue) {
                                    updateLook {
                                        if active { $0.decorations.removeAll { $0.kind == kind } }
                                        else { $0.decorations.append(IconDecoration(kind: kind, anchorX: 0.5, anchorY: kind == .stringLights ? 0.16 : 0.22)) }
                                    }
                                }
                                .buttonStyle(.borderedProminent).tint(active ? .accentColor : .secondary.opacity(0.35)).controlSize(.small)
                            }
                        }
                        if let first = look.decorations.first {
                            Slider(value: Binding(get: { first.anchorY }, set: { y in updateLook { if !$0.decorations.isEmpty { $0.decorations[0].anchorY = y } } }), in: 0.05...0.95) { Text("Vertical") }
                            if first.kind == .stringLights {
                                Slider(value: Binding(get: { first.spacing }, set: { sp in updateLook { if !$0.decorations.isEmpty { $0.decorations[0].spacing = sp } } }), in: 0...1) { Text("Spacing") }
                            }
                        }
                    }

                    if let kind = liveKind {
                        let liveCfg = look.live ?? LiveIconConfig.default(for: kind)
                        inspectorSection("live", title: String(localized: "Live Activity"), summary: look.live?.isEnabled == true ? String(localized: "Active") : String(localized: "Off")) {
                            Toggle("Enable Live Icon", isOn: Binding(get: { look.live?.isEnabled == true }, set: { on in updateLook { $0.live = on ? (look.live ?? .default(for: kind)) : nil } }))
                            if look.live?.isEnabled == true {
                                liveKindControls(kind: kind, cfg: liveCfg)
                            }
                        }
                    }
                }
                .padding(14)
            }
            Divider()
            HStack {
                if look.live != nil {
                    Button("Remove Live Icon") { updateLook { $0.live = nil } }.controlSize(.small)
                }
                Spacer()
                Button("Open App") {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    }
                }
                .controlSize(.small)
            }
            .padding(12)
        }
        .sheet(isPresented: $showMacOSIcons) {
            MacOSIconsSearchSheet(bundleID: bundleID, studio: studio)
        }
    }

    @ViewBuilder
    private func liveHeaderCard(_ kind: LiveIconKind) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: AppDisplayNameResolver.displayName(for: bundleID)).font(.system(size: 12, weight: .semibold))
                Text(kind.supportsOptInActivityProbe ? "Opt-in activity source" : "Local activity source")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if kind == .claude || kind == .codex || kind == .cursor {
                Button { AgentUsageService.shared.refreshAsync() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func liveKindControls(kind: LiveIconKind, cfg: LiveIconConfig) -> some View {
        switch kind {
        case .claude, .codex, .cursor:
            Picker("Allowance", selection: Binding(get: { cfg.usageMode }, set: { v in updateLook { var c = $0.live ?? cfg; c.usageMode = v; $0.live = c } })) {
                Text("None").tag(LiveIconUsageMode.none); Text("Used").tag(LiveIconUsageMode.used); Text("Remaining").tag(LiveIconUsageMode.remaining)
            }.pickerStyle(.segmented)
            Picker("Style", selection: Binding(get: { cfg.usageStyle }, set: { v in updateLook { var c = $0.live ?? cfg; c.usageStyle = v; $0.live = c } })) {
                Text("Color fill").tag(LiveIconUsageStyle.colorFill); Text("Water").tag(LiveIconUsageStyle.water)
                Text("Fade tide").tag(LiveIconUsageStyle.fadeTide); Text("Tracer").tag(LiveIconUsageStyle.glyphTracer)
            }
            Toggle("Show percentage", isOn: Binding(get: { cfg.showPercentage }, set: { v in updateLook { var c = $0.live ?? cfg; c.showPercentage = v; $0.live = c } }))
            Toggle("Show weekly reset", isOn: Binding(get: { cfg.showWeeklyReset }, set: { v in updateLook { var c = $0.live ?? cfg; c.showWeeklyReset = v; $0.live = c } }))
        case .appleMusic, .spotify:
            Picker("Style", selection: Binding(get: { cfg.musicStyle }, set: { v in updateLook { var c = $0.live ?? cfg; c.musicStyle = v; $0.live = c } })) {
                Text("Vinyl").tag(LiveIconMusicStyle.vinyl); Text("CD jewel case").tag(LiveIconMusicStyle.cdJewelCase); Text("Prismatic").tag(LiveIconMusicStyle.prismaticDisc)
            }
            Toggle("Show countdown", isOn: Binding(get: { cfg.showCountdown }, set: { v in updateLook { var c = $0.live ?? cfg; c.showCountdown = v; $0.live = c } }))
        case .finder:
            let f = cfg.finderStyle ?? FinderCompanionStyle()
            Picker("Nose", selection: Binding(get: { f.noseStyle }, set: { n in updateLook { var c = $0.live ?? cfg; var st = c.finderStyle ?? f; st.noseStyle = n; c.finderStyle = st; $0.live = c } })) {
                ForEach(FinderCompanionStyle.NoseStyle.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            Picker("Mouth", selection: Binding(get: { f.mouthStyle }, set: { m in updateLook { var c = $0.live ?? cfg; var st = c.finderStyle ?? f; st.mouthStyle = m; c.finderStyle = st; $0.live = c } })) {
                ForEach(FinderCompanionStyle.MouthStyle.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            Toggle("Opt-in file copy focus", isOn: Binding(get: { cfg.optInActivityProbe }, set: { v in updateLook { var c = $0.live ?? cfg; c.optInActivityProbe = v; $0.live = c } }))
        case .mail, .messages, .safari, .chrome:
            Toggle("Enable opt-in live probe", isOn: Binding(get: { cfg.optInActivityProbe }, set: { v in updateLook { var c = $0.live ?? cfg; c.optInActivityProbe = v; $0.live = c } }))
            Text("Requires opt-in Accessibility or Automation consent only when active.").font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func inspectorSection<Content: View>(_ id: String, title: String, summary: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        let isOpen = openSections.contains(id)
        DisclosureGroup(isExpanded: Binding(get: { isOpen }, set: { on in if on { openSections.insert(id) } else { openSections.remove(id) } })) {
            VStack(alignment: .leading, spacing: 8) { content() }.padding(.top, 6)
        } label: {
            HStack { Text(verbatim: title).font(.system(size: 12, weight: .semibold)); Spacer(); Text(verbatim: summary).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func pickCustomImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .icns, .tiff, .jpeg]
        if panel.runModal() == .OK, let url = panel.url { _ = studio.importArtwork(from: url, for: bundleID) }
    }

    private func hexString(from color: Color) -> String? {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int((ns.redComponent * 255).rounded()), Int((ns.greenComponent * 255).rounded()), Int((ns.blueComponent * 255).rounded()))
    }
}

struct MacOSIconsSearchSheet: View {
    let bundleID: String
    @ObservedObject var studio: IconStudioController
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var apiKey = UserDefaults.standard.string(forKey: IconStudioDefaultsKeys.macOSIconsAPIKey) ?? ""
    @State private var results: [MacOSIconsResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Search macOSicons").font(.headline)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 8) {
                    SecureField("Paste macOSicons x-api-key", text: $apiKey).textFieldStyle(.roundedBorder)
                        .onChange(of: apiKey) { UserDefaults.standard.set($0, forKey: IconStudioDefaultsKeys.macOSIconsAPIKey) }
                    Text("Free key via macosicons.com").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                TextField("App name", text: $query).textFieldStyle(.roundedBorder).onSubmit { runSearch() }
                Button("Search") { runSearch() }.buttonStyle(.borderedProminent).disabled(isLoading)
            }
            if let errorMessage {
                Text(verbatim: errorMessage).font(.caption).foregroundStyle(.red)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
                    if isLoading {
                        ForEach(0..<8, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.08)).frame(height: 88)
                        }
                    } else if results.isEmpty {
                        Text("Enter an app name to search community icons, or drop local artwork onto the stage.")
                            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                    } else {
                        ForEach(results) { item in
                            Button { applyResult(item) } label: {
                                VStack(spacing: 4) {
                                    AsyncImage(url: URL(string: item.pngURL)) { img in
                                        img.resizable().aspectRatio(contentMode: .fit)
                                    } placeholder: { RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.08)) }
                                    .frame(width: 56, height: 56)
                                    Text(verbatim: item.appName).font(.system(size: 10)).lineLimit(1)
                                }.padding(6).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(width: 460, height: 280)
        }
        .padding(18)
        .onAppear { if query.isEmpty { query = AppDisplayNameResolver.displayName(for: bundleID) } }
    }

    private func runSearch() {
        errorMessage = nil
        do {
            let req = try MacOSIconsQuery.makeSearchRequest(query: query, apiKey: apiKey)
            isLoading = true
            Task {
                do {
                    let (data, resp) = try await URLSession.shared.data(for: req)
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    let decoded = try MacOSIconsQuery.decodeSearchResponse(data, statusCode: code)
                    await MainActor.run { results = decoded; isLoading = false }
                } catch {
                    await MainActor.run { errorMessage = error.localizedDescription; isLoading = false }
                }
            }
        } catch MacOSIconsError.missingAPIKey {
            errorMessage = String(localized: "Enter your macOSicons API key first.")
        } catch MacOSIconsError.emptyQuery {
            errorMessage = String(localized: "Enter an app name to search.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyResult(_ item: MacOSIconsResult) {
        guard let url = URL(string: item.pngURL) else { return }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            await MainActor.run {
                if studio.importRemotePNG(data, iconID: item.id, for: bundleID) { dismiss() }
            }
        }
    }
}
