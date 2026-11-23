import SwiftUI

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
