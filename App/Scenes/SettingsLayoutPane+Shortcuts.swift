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
                Text("Protect Caps Lock"),
                isOn: Binding(
                    get: { keyGuard.isCapsProtectionEnabled },
                    set: { on in
                        if on, !KeyGuardService.hasPermission { KeyGuardService.requestPermission() }
                        keyGuard.setCapsProtection(on)
                    }
                ),
                info: String(localized: "A quick tap on Caps Lock does nothing; hold it briefly to switch Caps Lock. It needs the Accessibility permission to send the toggle, and does nothing while Hyper Key is on because Caps Lock then becomes F18.")
            )
            SettingsDivider()
            SettingsToggleRow(
                Text("Finder Keys"),
                isOn: Binding(
                    get: { keyGuard.isFinderKeysEnabled },
                    set: { on in
                        if on, !KeyGuardService.hasPermission { KeyGuardService.requestPermission() }
                        keyGuard.setFinderKeys(on)
                    }
                ),
                info: String(localized: "In Finder, ⌘X copies the selection and marks it for moving, and ⌘V then moves it to the current folder.")
            )
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
                SettingsDivider()
                SettingsSliderRow(
                    Text("Hold duration"),
                    value: keyGuard.slowQuitDuration,
                    range: 0.2...3,
                    step: 0.1,
                    valueText: String(format: "%.1fs", keyGuard.slowQuitDuration),
                    set: { keyGuard.setSlowQuitDuration($0) }
                )
            }
            // 24c, 53d and 53i used to be four comma-separated fields on two pages; they are one
            // table now, and it stays visible whether or not the hold is on, because the
            // quit-on-close column does not depend on it.
            SettingsDivider()
            QuitAppRulesTable()
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
            if keyGuard.isPaused || keyGuard.isSlowQuitEnabled || keyGuard.isVisualizerEnabled
                || keyGuard.isCapsProtectionEnabled || keyGuard.isFinderKeysEnabled, !KeyGuardService.hasPermission {
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
        case .shiftRightClick: return Text("Shift + Right Click")
        case .optionMiddleClick: return Text("Option + Middle Click")
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

/// The quitting table: one row per app, three columns. It replaces four comma-separated fields that
/// lived on two pages (24c's instant-quit list, 53i's pass-through list and 53d's quit-on-close list)
/// and each failed silently on a typo — nothing said "that is not an app".
///
/// The columns *are* the three stored lists, read through `QuitAppRules`, so the table and the key tap
/// cannot disagree; every edit writes all three back through `apply`. A table rather than a row per app
/// because three switches and a remove button do not fit a row's trailing column, and the column
/// captions have to stay above the columns they name (the row-content exemption in `Docs/SETTINGS.md`
/// rule 3, as with `AppearanceModeCards`).
struct QuitAppRulesTable: View {
    @ObservedObject var keyGuard = KeyGuardService.shared
    @ObservedObject var quitOnClose = QuitOnLastWindowService.shared
    /// The typed bundle ID. Only ever a candidate: nothing is written until Add.
    @State private var draft = ""

    /// Wide enough for the longest caption ("Quit on Close") at `.caption`, so the header and its
    /// switches share one centre line.
    private static let columnWidth: CGFloat = 92
    private static let removeWidth: CGFloat = 16

    private struct Candidate: Identifiable {
        let bundleID: String
        let name: String
        var id: String { bundleID }
    }

    private var rules: QuitAppRules {
        .parse(skipHold: keyGuard.slowQuitExceptions,
               ownQuitKey: keyGuard.passthroughApps,
               quitOnClose: quitOnClose.apps)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowNoteSpacing) {
            header
            if rules.rows.isEmpty {
                SettingsNote(Text("No apps yet. Add one below to change how it quits."))
            }
            ForEach(rules.rows) { row in
                SettingsDivider()
                appRow(row)
            }
            SettingsDivider()
            addRow
        }
        .padding(.vertical, SettingsMetrics.rowVerticalPadding)
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: SettingsMetrics.controlSpacing) {
            HStack(spacing: 6) {
                Text("Apps")
                SettingsInfoButton(text: Self.explanation)
            }
            Spacer(minLength: SettingsMetrics.rowMinimumLabelGap)
            HStack(spacing: SettingsMetrics.controlSpacing) {
                ForEach(QuitAppRules.Option.allCases) { option in
                    Text(verbatim: Self.caption(option))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: Self.columnWidth)
                }
            }
            Color.clear.frame(width: Self.removeWidth)
        }
        .accessibilityElement(children: .contain)
        // The page's find field and the sidebar search both walk row titles; the table's rows have
        // none of their own, so the table answers to its header.
        .settingsFindable(Text("Apps"))
    }

    // MARK: rows

    private func appRow(_ row: QuitAppRules.Row) -> some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowNoteSpacing) {
            HStack(spacing: SettingsMetrics.controlSpacing) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: Self.displayName(for: row.bundleID))
                        .lineLimit(1)
                    Text(verbatim: row.bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: SettingsMetrics.rowMinimumLabelGap)
                ForEach(QuitAppRules.Option.allCases) { option in
                    toggle(option, row: row)
                }
                Button {
                    apply { $0.remove(row.bundleID) }
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: Self.removeWidth)
                .help(Text("Remove"))
                .accessibilityLabel(Text("Remove"))
                // The label is the same on every row; the app it belongs to is the hint.
                .accessibilityHint(Text(verbatim: Self.displayName(for: row.bundleID)))
            }
            // Rule 7: a disabled control says why on its own row, not only in the ⓘ above.
            if !QuitOnLastWindowPolicy.allowsQuitOnClose(row.bundleID) {
                SettingsNote(Text("Finder, the Dock and KatiKati itself are always left alone."))
            }
        }
        .padding(.vertical, SettingsMetrics.rowVerticalPadding)
    }

    /// One switch. The tooltip and the VoiceOver label are the caption above it, so a column can never
    /// be named one thing in the header and another to a screen reader (rule 9).
    private func toggle(_ option: QuitAppRules.Option, row: QuitAppRules.Row) -> some View {
        let caption = Self.caption(option)
        return Toggle(isOn: Binding(
            get: { rules.row(row.bundleID)?.isOn(option) ?? false },
            set: { on in apply { $0.set(option, for: row.bundleID, to: on) } }
        )) {
            Text(verbatim: caption)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .labelsHidden()
        .frame(width: Self.columnWidth)
        .disabled(option == .quitOnClose && !QuitOnLastWindowPolicy.allowsQuitOnClose(row.bundleID))
        .help(Text(verbatim: caption))
        .accessibilityLabel(Text(verbatim: caption))
    }

    // MARK: adding

    private var addRow: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowNoteSpacing) {
            HStack(spacing: SettingsMetrics.controlSpacing) {
                HStack(spacing: 6) {
                    Text("Add App")
                    SettingsInfoButton(text: Self.addition)
                }
                Spacer(minLength: SettingsMetrics.rowMinimumLabelGap)
                TextField("Bundle ID", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)
                    .accessibilityLabel(Text("Bundle ID"))
                Button("Add") { add(draft) }
                    .buttonStyle(SettingsGelButtonStyle())
                    .disabled(!QuitAppRules.isPlausibleBundleID(draft))
                // Running apps carry their real names, which is the point: a bundle ID is not
                // something to remember. Apps that are not running are added by bundle ID above.
                Menu {
                    ForEach(runningApps) { app in
                        Button { add(app.bundleID) } label: { Text(verbatim: app.name) }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(runningApps.isEmpty)
                .help(Text("Running Apps"))
                .accessibilityLabel(Text("Running Apps"))
            }
            if !draft.isEmpty, !QuitAppRules.isPlausibleBundleID(draft) {
                SettingsNote(Text("That is not a bundle ID. Use the form com.company.AppName."))
            }
        }
        .padding(.vertical, SettingsMetrics.rowVerticalPadding)
    }

    private func add(_ raw: String) {
        guard QuitAppRules.isPlausibleBundleID(raw) else { return }
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 53i: a new app starts in Own ⌘Q — its ⌘Q exactly as macOS has it — because every other
        // column changes something. The ⓘ says so, and the switches are one click away.
        apply { $0.set(.ownQuitKey, for: id, to: true) }
        draft = ""
    }

    /// One write path: read the three lists, change the table, write all three back. Writing one
    /// column on its own would leave the table and the services disagreeing about an app.
    private func apply(_ edit: (inout QuitAppRules) -> Void) {
        var updated = rules
        edit(&updated)
        keyGuard.setSlowQuitExceptions(updated.skipHoldList)
        keyGuard.setPassthroughApps(updated.ownQuitKeyList)
        quitOnClose.setApps(updated.quitOnCloseList)
    }

    // MARK: names

    /// The app's own name when the system can find it, its bundle ID when it cannot — an app that is
    /// not installed still has to be recognisable in the list.
    static func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return url.deletingPathExtension().lastPathComponent
    }

    /// One string per column, shared by the caption, the tooltip and the VoiceOver label.
    static func caption(_ option: QuitAppRules.Option) -> String {
        switch option {
        case .skipHold: return String(localized: "Skip Hold")
        case .ownQuitKey: return String(localized: "Own ⌘Q")
        case .quitOnClose: return String(localized: "Quit on Close")
        }
    }

    private var runningApps: [Candidate] {
        let known = Set(rules.rows.map(\.bundleID))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> Candidate? in
                guard let id = app.bundleIdentifier, !known.contains(id),
                      QuitAppRules.isPlausibleBundleID(id) else { return nil }
                return Candidate(bundleID: id, name: app.localizedName ?? Self.displayName(for: id))
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: explanations (rule 4: a row's note stays one line, the rest is behind the ⓘ)

    private static var explanation: String {
        String(localized: "Skip Hold quits that app the moment you press ⌘Q. Own ⌘Q leaves its own ⌘Q alone, for remote desktops and virtual machines, and cannot be on at the same time as Skip Hold. Quit on Close ends the app after its last window closes; it asks the app to quit, so a save prompt still runs, and it needs the Accessibility permission. Pausing the keyboard does not stop it.")
    }

    private static var addition: String {
        String(localized: "Pick a running app, or type the bundle ID of one that is not running. A new app starts in Own ⌘Q — its ⌘Q unchanged — so switch on the column you want, and turn that one off if the app should need the hold.")
    }
}
