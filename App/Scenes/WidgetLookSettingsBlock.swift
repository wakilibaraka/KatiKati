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
    @AppStorage(DockHoverAnimationStyle.defaultsKey) private var hoverAnimationRaw = DockHoverAnimationStyle.none.rawValue
    @AppStorage(DockPressAnimationStyle.defaultsKey) private var pressAnimationRaw = DockPressAnimationStyle.tactileSquish.rawValue
    @AppStorage(DockRunningIndicatorStyle.defaultsKey) private var runningIndicatorRaw = DockRunningIndicatorStyle.macDot.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
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
    var body: some View { Color.clear }
}
