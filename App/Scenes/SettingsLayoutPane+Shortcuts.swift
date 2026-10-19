import SwiftUI

// The Shortcuts mode of `SettingsLayoutPane`; state lives in the main file.
extension SettingsLayoutPane {
    /// The Shortcuts page (Phase 12 A4). Every key assignment lives in the first card — a find
    /// field, the feature actions, then the fifteen snap zones; the keyboard behaviours that change
    /// how typing reaches apps are the second; the dial is the third. Three sections is the page's
    /// budget (`Docs/SETTINGS.md` rule 5) and the long first one is why it carries a filter: 26
    /// assignment rows is more than a reader should have to scroll through to find one.
    @ViewBuilder
    var shortcutSections: some View {
        let duplicated = ShortcutConflicts.duplicated(store.shortcutBindings)
        SettingsCard(
            // Headerless: the two disclosure groups below carry the names (the page's toolbar tab
            // already says "Shortcuts"), so no new string was needed for the grouping.
            note: Text("Double-tap shortcuts need the Accessibility permission. ⌃Space may also switch input sources.")
        ) {
            SettingsRow(
                Text("Search Shortcuts"),
                info: String(localized: "Pick a shortcut from the list, or press Record and type a key combination with ⌃, ⌥, ⇧ or ⌘.")
            ) {
                TextField("Search Shortcuts", text: $shortcutFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .accessibilityLabel(Text("Search Shortcuts"))
            }
            SettingsDivider()
            // One assignment per line (an assignment is a name, a menu and a Record button, and a
            // half of the card cannot hold three controls — measured live 2026-10-15), and the run
            // starts collapsed so the page fits the window.
            DisclosureGroup(isExpanded: expandedWhileFiltering($showsFeatureShortcuts)) {
                ForEach(filteredFeatureShortcuts, id: \.self) { action in
                    shortcutRow(action, duplicated: duplicated)
                    SettingsDivider()
                }
            } label: {
                Text("Shortcuts").font(.headline)
            }
            if hasVisibleSnapHotkeys {
                SettingsDivider()
                DisclosureGroup(isExpanded: expandedWhileFiltering($showsSnapHotkeys)) {
                    snapHotkeyGroup(title: Text("Halves"), actions: Self.snapHotkeyGroups[0], duplicated: duplicated)
                    snapHotkeyGroup(title: Text("Quarters"), actions: Self.snapHotkeyGroups[1], duplicated: duplicated)
                    snapHotkeyGroup(title: Text("Thirds"), actions: Self.snapHotkeyGroups[2], duplicated: duplicated)
                    snapHotkeyGroup(title: Text("Full"), actions: Self.snapHotkeyGroups[3], duplicated: duplicated)
                } label: {
                    // The group's own name, and its explanation stays behind the ⓘ where it was.
                    HStack(spacing: 6) {
                        Text("Snap Hotkeys").font(.headline)
                        SettingsInfoButton(text: String(localized: "Snap hotkeys default to Off, except Maximize (⌃⌥M). Press Record and type a key combination with ⌃, ⌥, ⇧ or ⌘."))
                    }
                }
            }
            if !filteredTilingShortcuts.isEmpty {
                SettingsDivider()
                DisclosureGroup(isExpanded: expandedWhileFiltering($showsTilingShortcuts)) {
                    ForEach(filteredTilingShortcuts, id: \.self) { action in
                        shortcutRow(action, duplicated: duplicated)
                        SettingsDivider()
                    }
                } label: {
                    Text("Tiling Shortcuts").font(.headline)
                }
            }
            if filteredFeatureShortcuts.isEmpty, !hasVisibleSnapHotkeys, filteredTilingShortcuts.isEmpty {
                SettingsNote(Text("No shortcuts match."))
            }
        }

        SettingsCard(Text("Keyboard")) {
            SettingsToggleRow(
                Text("Use Caps Lock as Hyper Key"),
                isOn: Binding(
                    get: { store.hyperkeyEnabled },
                    set: { on in
                        if on, !HyperkeyService.hasPermission { HyperkeyService.requestPermission() }
                        store.setHyperkeyEnabled(on)
                    }
                ),
                info: String(localized: "Hyper turns Caps Lock into ⌃⌥⇧⌘. It listens to keyboard events only, needs the Input Monitoring permission, and Caps Lock is restored when you turn it off or quit.")
            )
            if store.hyperkeyEnabled, !HyperkeyService.hasPermission {
                SettingsButtonRow(Text("Open Input Monitoring Settings")) { openInputMonitoringSettings() }
            }
            SettingsDivider()
            SettingsToggleRow(
                Text("Pause Keyboard"),
                isOn: Binding(
                    get: { keyGuard.isPaused },
                    set: { on in
                        if on, !KeyGuardService.hasPermission { KeyGuardService.requestPermission() }
                        keyGuard.setPaused(on)
                    }
                ),
                info: String(localized: "While paused, key presses are ignored (the mouse still works). Press ⌃⌥⌘P to unpause. Needs the Input Monitoring permission.")
            )
            SettingsDivider()
            SettingsRow(Text("Clean Keyboard"), note: Text("Keys are off for 60 seconds. Press ⌃⌥⌘P to unlock sooner.")) {
                Button("Lock for 60 Seconds") { KeyGuardService.shared.startCleaningLock() }
                    .buttonStyle(SettingsGelButtonStyle())
            }
            SettingsDivider()
            SettingsToggleRow(
                Text("Hold ⌘Q to Quit"),
                isOn: Binding(
                    get: { keyGuard.isSlowQuitEnabled },
                    set: { on in
                        if on, !KeyGuardService.hasPermission { KeyGuardService.requestPermission() }
                        keyGuard.setSlowQuit(on)
                    }
                ),
                info: String(localized: "Press and hold ⌘Q for a moment to quit an app; releasing early cancels it. Apps listed below quit instantly instead.")
            )
            if keyGuard.isSlowQuitEnabled {
                SettingsSliderRow(
                    Text("Hold duration"),
                    value: keyGuard.slowQuitDuration,
                    range: 0.2...3,
                    step: 0.1,
                    valueText: String(format: "%.1fs", keyGuard.slowQuitDuration),
                    set: { keyGuard.setSlowQuitDuration($0) }
                )
                SettingsRow(Text("Quit instantly, no hold (bundle IDs)")) {
                    TextField("Quit instantly, no hold (bundle IDs)", text: Binding(
                        get: { keyGuard.slowQuitExceptions },
                        set: { keyGuard.setSlowQuitExceptions($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                }
            }
            SettingsDivider()
            SettingsToggleRow(
                Text("Show Keys You Type"),
                isOn: Binding(
                    get: { keyGuard.isVisualizerEnabled },
                    set: { on in
                        if on, !KeyGuardService.hasPermission { KeyGuardService.requestPermission() }
                        keyGuard.setVisualizer(on)
                    }
                ),
                info: String(localized: "Shows the keys you press in a small overlay. It displays what you type — treat it as a screen-sharing risk. Nothing is logged or saved, and it hides itself a moment after you stop typing.")
            )
            SettingsDivider()
            SettingsToggleRow(
                Text("Open Launcher with Pinch"),
                isOn: Binding(get: { store.launcherPinch }, set: { store.setLauncherPinch($0) }),
                info: String(localized: "Pinch four or more fingers together on the trackpad. Turn off Launchpad under System Settings > Trackpad > More Gestures, or macOS opens its own app list too.")
            )
            if keyGuard.isPaused || keyGuard.isSlowQuitEnabled || keyGuard.isVisualizerEnabled, !KeyGuardService.hasPermission {
                SettingsButtonRow(Text("Open Input Monitoring Settings")) { openInputMonitoringSettings() }
            }
            SettingsButtonRow(Text("Open Trackpad Settings")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.trackpad") { NSWorkspace.shared.open(url) }
            }
        }
    }

    /// The Radial Dial page (split from Shortcuts, Phase 1 of the settings redesign).
    @ViewBuilder
    var radialDialSections: some View {
        SettingsCard(
            Text("Radial Dial"),
            note: Text("You can also summon the Radial Dial with the shortcut assigned in the Shortcuts section above.")
        ) {
            SettingsToggleRow(
                Text("Enable Radial Dial"),
                isOn: $dialEnabled,
                info: String(localized: "Summons a circular pie menu at your cursor for lightning-fast window snapping, app launching, and quick actions with spring physics.")
            )
            if dialEnabled {
                SettingsDivider()
                SettingsPickerRow(Text("Theme"), selection: Binding(
                    get: { RadialDialTheme(rawValue: dialThemeRaw) ?? .lilacGlass },
                    set: { dialThemeRaw = $0.rawValue }
                )) {
                    ForEach(RadialDialTheme.allCases, id: \.self) { theme in
                        radialDialThemeTitle(theme).tag(theme)
                    }
                }
                SettingsDivider()
                SettingsPickerRow(Text("Mouse Trigger"), selection: Binding(
                    get: { RadialMouseTrigger(rawValue: dialMouseTriggerRaw) ?? .off },
                    set: { dialMouseTriggerRaw = $0.rawValue }
                )) {
                    ForEach(RadialMouseTrigger.allCases, id: \.self) { trigger in
                        radialMouseTriggerTitle(trigger).tag(trigger)
                    }
                }
                SettingsDivider()
                SettingsPickerRow(Text("Trigger Mode"), selection: Binding(
                    get: { RadialTriggerMode(rawValue: dialTriggerModeRaw) ?? .tapToggle },
                    set: { dialTriggerModeRaw = $0.rawValue }
                )) {
                    ForEach(RadialTriggerMode.allCases, id: \.self) { mode in
                        radialTriggerModeTitle(mode).tag(mode)
                    }
                }
            }
        }
    }

    /// The thirteen feature shortcuts (every action that neither snaps nor tiles), filtered by the
    /// find field. Declaration order is the menu order, so the page never reorders itself.
    var filteredFeatureShortcuts: [ShortcutAction] {
        ShortcutAction.allCases
            .filter { $0.snapPosition == nil && !$0.isTilingAction }
            .filter(matchesFilter)
    }

    /// The six tiling shortcuts, consolidated here from Window Management so every keyboard
    /// shortcut is searchable and editable in one place.
    var filteredTilingShortcuts: [ShortcutAction] {
        ShortcutAction.allCases
            .filter(\.isTilingAction)
            .filter(matchesFilter)
    }

    var hasVisibleSnapHotkeys: Bool {
        Self.snapHotkeyGroups.contains { $0.contains(where: matchesFilter) }
    }

    func matchesFilter(_ action: ShortcutAction) -> Bool {
        Self.shortcutMatches(Self.shortcutActionName(action), query: shortcutFilter)
    }

    /// A collapsed group opens as soon as the find field has a query, so the filter still reaches
    /// the rows it hides (the collapsed state is what makes the page fit the window).
    func expandedWhileFiltering(_ expanded: Binding<Bool>) -> Binding<Bool> {
        Binding(get: { expanded.wrappedValue || !shortcutFilter.isEmpty },
                set: { expanded.wrappedValue = $0 })
    }

    /// One assignment: the action's name, its warning glyph when two actions share a shortcut, the
    /// current binding and the Record button. Through the row system, so the label/control columns
    /// match every other page (`Docs/SETTINGS.md` rules 3 and 6).
    func shortcutRow(_ action: ShortcutAction, duplicated: Set<ShortcutAction>) -> some View {
        SettingsRow(Text(verbatim: Self.shortcutActionName(action))) {
            HStack(spacing: SettingsMetrics.controlSpacing) {
                if duplicated.contains(action) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        .help(Text("Another action uses the same shortcut"))
                }
                shortcutPicker(action)
                ShortcutRecorderButton { store.setShortcut(action, .key($0)) }
            }
        }
    }

    /// The binding menu. Its own label is hidden, so the row carries the name for VoiceOver too.
    func shortcutPicker(_ action: ShortcutAction) -> some View {
        Picker(selection: Binding(get: { store.shortcutBindings[action] ?? .off },
                                  set: { store.setShortcut(action, $0) })) {
            Text("Off").tag(ShortcutTrigger.off)
            Divider()
            ForEach(ShortcutChord.allCases, id: \.self) { Text(verbatim: $0.glyphs).tag(ShortcutTrigger.chord($0)) }
            Divider()
            ForEach(ShortcutTapKey.allCases, id: \.self) { key in
                (Text("Double-tap") + Text(verbatim: " \(key.glyph) (\(key.isRight ? "R" : "L"))")).tag(ShortcutTrigger.doubleTap(key))
            }
            if case let .key(custom) = store.shortcutBindings[action] ?? .off {
                Divider()
                Text(verbatim: custom.glyphs).tag(ShortcutTrigger.key(custom))
            }
            if store.hyperkeyEnabled {
                Divider()
                ForEach(ShortcutKeyNames.hyperChoices, id: \.self) { code in
                    Text(verbatim: "Hyper+" + (ShortcutKeyNames.name(for: code) ?? "?")).tag(ShortcutTrigger.hyper(code))
                }
            }
        } label: { EmptyView() }
        .pickerStyle(.menu)
        .fixedSize()
        .accessibilityLabel(Text(verbatim: Self.shortcutActionName(action)))
    }

    /// One snap group. The caption and its rows both disappear when the find field excludes them,
    /// so an empty group never leaves a stray heading.
    @ViewBuilder
    func snapHotkeyGroup(title: Text, actions: [ShortcutAction],
                                 duplicated: Set<ShortcutAction>) -> some View {
        let matching = actions.filter(matchesFilter)
        if !matching.isEmpty {
            title.font(.caption).foregroundStyle(.secondary).padding(.top, 2)
            ForEach(matching, id: \.self) { action in
                shortcutRow(action, duplicated: duplicated)
            }
        }
    }

    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    func radialDialThemeTitle(_ theme: RadialDialTheme) -> Text {
        switch theme {
        case .lilacGlass: return Text("Lilac Glass")
        case .darkObsidian: return Text("Dark Obsidian")
        case .systemFrosted: return Text("System Frosted")
        case .neonCyber: return Text("Neon Cyber")
        }
    }

    func radialMouseTriggerTitle(_ trigger: RadialMouseTrigger) -> Text {
        switch trigger {
        case .off: return Text("Off")
        case .middleClick: return Text("Middle Click")
        case .controlRightClick: return Text("Control + Right Click")
        case .optionRightClick: return Text("Option + Right Click")
        case .commandRightClick: return Text("Command + Right Click")
        case .button4: return Text("Mouse Button 4")
        case .button5: return Text("Mouse Button 5")
        }
    }

    func radialTriggerModeTitle(_ mode: RadialTriggerMode) -> Text {
        switch mode {
        case .tapToggle: return Text("Tap / Click to Toggle")
        case .holdRelease: return Text("Hold & Release")
        }
    }
}
