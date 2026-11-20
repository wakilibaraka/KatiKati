import AppKit
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
        Picker("Shortcuts", selection: $shortcutsSectionFilter) {
            Text("Keyboard").tag(ShortcutsSectionFilter.keyboard)
            Text("Mouse & Gestures").tag(ShortcutsSectionFilter.mouseAndGestures)
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        if shortcutsSectionFilter == .keyboard {
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
            SettingsRow(
                Text("Hold Time"),
                info: String(localized: "How long a Hold shortcut (such as hold fn) must be held before it fires.")
            ) {
                Stepper(value: $holdSeconds, in: ShortcutHold.range, step: 0.1) {
                    Text(verbatim: String(format: "%.1f s", holdSeconds))
                }
                .fixedSize()
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
                Text("Super / Hyper Key"),
                isOn: Binding(
                    get: { store.hyperkeyEnabled },
                    set: { on in
                        if on, !HyperkeyService.hasPermission { HyperkeyService.requestPermission() }
                        store.setHyperkeyEnabled(on)
                    }
                ),
                info: String(localized: "Remaps Caps Lock (or Right ⌘/⌥) into a Hyper (⌃⌥⇧⌘) or Super (⌃⌥⌘) modifier for KatiKati and all apps. Needs Input Monitoring, and restores your key when turned off or quit.")
            )
            if store.hyperkeyEnabled {
                SettingsDivider()
                DisclosureGroup("Super / Hyper Options") {
                    SettingsPickerRow(Text("Modifier Mode"), selection: Binding(
                        get: { store.hyperkeyModifierMode },
                        set: { store.setHyperkeyModifierMode($0) }
                    )) {
                        Text("Hyper (⌃⌥⇧⌘)").tag(HyperkeyModifierMode.hyper)
                        Text("Super (⌃⌥⌘)").tag(HyperkeyModifierMode.superKey)
                    }
                    SettingsDivider()
                    SettingsPickerRow(Text("Source Key"), selection: Binding(
                        get: { store.hyperkeySourceKey },
                        set: { store.setHyperkeySourceKey($0) }
                    )) {
                        Text("Caps Lock").tag(HyperkeySourceKey.capsLock)
                        Text("Right ⌘").tag(HyperkeySourceKey.rightCommand)
                        Text("Right ⌥").tag(HyperkeySourceKey.rightOption)
                    }
                    SettingsDivider()
                    SettingsPickerRow(Text("Tap if Alone"), selection: Binding(
                        get: { store.hyperkeyTapAction },
                        set: { store.setHyperkeyTapAction($0) }
                    )) {
                        Text("Off").tag(HyperkeyTapAction.off)
                        Text("Escape (⎋)").tag(HyperkeyTapAction.escape)
                        Text("Caps Lock (⇪)").tag(HyperkeyTapAction.capsLock)
                    }
                    if store.hyperkeyTapAction != .off {
                        SettingsDivider()
                        SettingsSliderRow(
                            Text("Tap Threshold"),
                            value: store.hyperkeyTapThreshold,
                            range: 0.08...0.50,
                            step: 0.02,
                            valueText: String(format: "%.2f s", store.hyperkeyTapThreshold),
                            set: { store.setHyperkeyTapThreshold($0) }
                        )
                    }
                    SettingsDivider()
                    SettingsToggleRow(
                        Text("Forward to All Apps"),
                        isOn: Binding(
                            get: { store.hyperkeyForwardToSystem },
                            set: { store.setHyperkeyForwardToSystem($0) }
                        ),
                        info: String(localized: "Sends ⌃⌥⇧⌘ or ⌃⌥⌘ to other apps (Raycast, VS Code, window managers) for keys not bound in KatiKati.")
                    )
                    SettingsDivider()
                    SettingsRow(Text("Excluded Apps"), note: Text("Comma-separated bundle IDs (e.g. com.apple.Terminal).")) {
                        TextField("com.apple.Terminal", text: Binding(
                            get: { store.hyperkeyExcludedApps },
                            set: { store.setHyperkeyExcludedApps($0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                    }
                }
            }
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
                info: String(localized: "Prevents accidental Caps Lock toggles. Hold briefly or double-tap to switch Caps Lock. Needs Accessibility to post the toggle, and is inert while Super/Hyper uses Caps Lock.")
            )
            if keyGuard.isCapsProtectionEnabled {
                SettingsDivider()
                DisclosureGroup("Caps Lock Protection Options") {
                    SettingsPickerRow(Text("Trigger Mode"), selection: Binding(
                        get: { keyGuard.capsProtectionMode },
                        set: { keyGuard.setCapsProtectionMode($0) }
                    )) {
                        Text("Hold to Toggle").tag(CapsLockProtectionMode.hold)
                        Text("Double-Tap to Toggle").tag(CapsLockProtectionMode.doubleTap)
                    }
                    if keyGuard.capsProtectionMode == .hold {
                        SettingsDivider()
                        SettingsSliderRow(
                            Text("Hold Duration"),
                            value: keyGuard.capsProtectionThreshold,
                            range: 0.10...0.50,
                            step: 0.05,
                            valueText: String(format: "%.2f s", keyGuard.capsProtectionThreshold),
                            set: { keyGuard.setCapsProtectionThreshold($0) }
                        )
                    }
                }
            }
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
                info: String(localized: "Protect ⌘Q with a hold or double-tap so accidental presses never quit an app. Apps listed below can skip or keep their own ⌘Q.")
            )
            if keyGuard.isSlowQuitEnabled {
                SettingsDivider()
                DisclosureGroup("SlowQuit Options") {
                    SettingsPickerRow(Text("Trigger Mode"), selection: Binding(
                        get: { keyGuard.slowQuitMode },
                        set: { keyGuard.setSlowQuitMode($0) }
                    )) {
                        Text("Hold ⌘Q").tag(SlowQuitMode.hold)
                        Text("Double-Tap ⌘Q").tag(SlowQuitMode.doubleTap)
                    }
                    if keyGuard.slowQuitMode == .hold {
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
                    SettingsDivider()
                    SettingsToggleRow(
                        Text("Show Confirmation Overlay"),
                        isOn: Binding(
                            get: { keyGuard.slowQuitShowOverlay },
                            set: { keyGuard.setSlowQuitShowOverlay($0) }
                        )
                    )
                    if keyGuard.slowQuitShowOverlay {
                        SettingsDivider()
                        SettingsPickerRow(Text("Overlay Style"), selection: Binding(
                            get: { keyGuard.slowQuitOverlayStyle },
                            set: { keyGuard.setSlowQuitOverlayStyle($0) }
                        )) {
                            Text("Ring").tag(SlowQuitOverlayStyle.ring)
                            Text("Bar").tag(SlowQuitOverlayStyle.bar)
                        }
                    }
                    SettingsDivider()
                    SettingsPickerRow(Text("App List Mode"), selection: Binding(
                        get: { keyGuard.slowQuitListMode },
                        set: { keyGuard.setSlowQuitListMode($0) }
                    )) {
                        Text("All Except Listed").tag(SlowQuitListMode.allExceptListed)
                        Text("Only Listed Apps").tag(SlowQuitListMode.onlyListedApps)
                    }
                }
            }
            SettingsDivider()
            DisclosureGroup("Quit on Close & Idle Apps") {
                QuitLifecycleOptionsView()
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
            if keyGuard.isPaused || keyGuard.isSlowQuitEnabled || keyGuard.isVisualizerEnabled
                || keyGuard.isCapsProtectionEnabled || keyGuard.isFinderKeysEnabled, !KeyGuardService.hasPermission {
                SettingsButtonRow(Text("Open Input Monitoring Settings")) { openInputMonitoringSettings() }
            }
        }
        } else {
        SettingsCard(Text("Mouse & Gestures")) {
            SettingsToggleRow(
                Text("Open Launcher with Pinch"),
                isOn: Binding(get: { store.launcherPinch }, set: { store.setLauncherPinch($0) }),
                info: String(localized: "Pinch four or more fingers together on the trackpad. Turn off Launchpad under System Settings > Trackpad > More Gestures, or macOS opens its own app list too.")
            )
            SettingsDivider()
            SettingsToggleRow(
                Text("Focus Follows the Mouse"),
                isOn: Binding(
                    get: { FocusFollowService.shared.isEnabled },
                    set: { FocusFollowService.shared.setEnabled($0) }
                ),
                info: String(localized: "Raises the window under the pointer, at most once every 120 ms. It never acts while you drag, while a KatiKati panel has the keyboard, or for the app already in front. Needs Accessibility; off by default.")
            )
            SettingsDivider()
            MultitouchGesturesSection()
            SettingsDivider()
            SettingsButtonRow(Text("Open Trackpad Settings")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.trackpad") { NSWorkspace.shared.open(url) }
            }
        }
        }
    }

    /// The Radial Dial page (split from Shortcuts, upgraded in SLICE RD-2 with slice customizer & triggers).
    @ViewBuilder
    var radialDialSections: some View {
        let duplicated = ShortcutConflicts.duplicated(store.shortcutBindings)
        SettingsCard(Text("Radial Dial")) {
            SettingsToggleRow(
                Text("Enable Radial Dial"),
                isOn: $dialEnabled,
                info: String(localized: "Summons a circular pie menu at your cursor for lightning-fast window snapping, app launching, and quick actions with spring physics.")
            )
            if dialEnabled {
                SettingsDivider()
                SettingsRow(Text("Keyboard Shortcut")) {
                    shortcutControls(.radialDial, duplicated: duplicated)
                }
                SettingsDivider()
                SettingsRowPair(
                    left: {
                        SettingsPickerRow(Text("Theme"), selection: Binding(
                            get: { RadialDialTheme(rawValue: dialThemeRaw) ?? .lilacGlass },
                            set: { dialThemeRaw = $0.rawValue }
                        )) {
                            ForEach(RadialDialTheme.allCases, id: \.self) { theme in
                                radialDialThemeTitle(theme).tag(theme)
                            }
                        }
                    },
                    right: {
                        SettingsPickerRow(Text("Trigger Mode"), selection: Binding(
                            get: { RadialTriggerMode(rawValue: dialTriggerModeRaw) ?? .tapToggle },
                            set: { dialTriggerModeRaw = $0.rawValue }
                        )) {
                            ForEach(RadialTriggerMode.allCases, id: \.self) { mode in
                                radialTriggerModeTitle(mode).tag(mode)
                            }
                        }
                    }
                )
                SettingsDivider()
                SettingsRowPair(
                    left: {
                        SettingsPickerRow(Text("Mouse Trigger"), selection: Binding(
                            get: { RadialMouseTrigger(rawValue: dialMouseTriggerRaw) ?? .off },
                            set: { dialMouseTriggerRaw = $0.rawValue }
                        )) {
                            ForEach(RadialMouseTrigger.allCases, id: \.self) { trigger in
                                radialMouseTriggerTitle(trigger).tag(trigger)
                            }
                        }
                    },
                    right: {
                        SettingsPickerRow(Text("Trackpad Edge"), selection: Binding(
                            get: { RadialTrackpadEdgeTrigger(rawValue: dialTrackpadTriggerRaw) ?? .off },
                            set: { dialTrackpadTriggerRaw = $0.rawValue }
                        )) {
                            ForEach(RadialTrackpadEdgeTrigger.allCases, id: \.self) { edge in
                                radialTrackpadTriggerTitle(edge).tag(edge)
                            }
                        }
                    }
                )
            }
        }

        if dialEnabled {
            SettingsCard(Text("Slices")) {
                HStack(spacing: SettingsMetrics.controlSpacing) {
                    if !dialEditPath.isEmpty {
                        Button { dialEditPath.removeLast() } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Text(verbatim: dialBreadcrumbTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { addRadialSlice() } label: { Text("Add") }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(currentEditableSlices.count >= 8)
                    Button { resetRadialSlices() } label: { Text("Reset") }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
                .padding(.vertical, 4)

                ForEach(Array(currentEditableSlices.enumerated()), id: \.element.id) { index, slice in
                    SettingsDivider()
                    radialSliceEditorRow(index: index, slice: slice)
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
            shortcutControls(action, duplicated: duplicated)
        }
    }

    /// Reusable trailing shortcut controls: conflict warning, registration status, menu picker, and Record button.
    func shortcutControls(_ action: ShortcutAction, duplicated: Set<ShortcutAction>) -> some View {
        ShortcutActionControls(store: store, action: action, duplicated: duplicated)
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
        case .hotkeyHold: return Text("Hotkey Hold & Release")
        }
    }

    func radialTrackpadTriggerTitle(_ edge: RadialTrackpadEdgeTrigger) -> Text {
        switch edge {
        case .off: return Text("Off")
        case .leftEdge: return Text("Left Edge")
        case .rightEdge: return Text("Right Edge")
        case .bottomEdge: return Text("Bottom Edge")
        }
    }

    private static let radialIconChoices = [
        "rectangle.split.2x1", "wrench.and.screwdriver", "square.grid.2x2",
        "playpause.fill", "doc.on.clipboard", "tray.and.arrow.down.fill",
        "camera.viewfinder", "rectangle.split.2x2", "macwindow",
        "viewfinder.text", "forward.fill", "backward.fill", "sparkles"
    ]

    private var dialBreadcrumbTitle: String {
        var titles = ["Main"]
        var nodes = dialNodes
        for id in dialEditPath {
            guard let found = nodes.first(where: { $0.id == id }) else { break }
            titles.append(found.title)
            nodes = found.children ?? []
        }
        return titles.joined(separator: " › ")
    }

    private var currentEditableSlices: [RadialSliceNode] {
        var nodes = dialNodes
        for id in dialEditPath {
            nodes = nodes.first(where: { $0.id == id })?.children ?? []
        }
        return nodes
    }

    private func updateEditableSlices(_ mutate: (inout [RadialSliceNode]) -> Void) {
        func apply(_ list: inout [RadialSliceNode], path: ArraySlice<String>) {
            guard let id = path.first, let idx = list.firstIndex(where: { $0.id == id }) else {
                mutate(&list)
                return
            }
            var children = list[idx].children ?? []
            apply(&children, path: path.dropFirst())
            list[idx].children = children
        }
        apply(&dialNodes, path: dialEditPath[...])
        RadialDialConfigStore.saveNodes(dialNodes)
    }

    private func addRadialSlice() {
        let newSlice = RadialSliceNode(
            id: "slice_\(UUID().uuidString.prefix(8))",
            title: String(localized: "Slice"),
            icon: .sfSymbol("sparkles"),
            accentHex: "#8B5CF6",
            action: .clipboard
        )
        updateEditableSlices { list in
            if list.count < 8 { list.append(newSlice) }
        }
    }

    private func resetRadialSlices() {
        dialEditPath = []
        RadialDialConfigStore.reset()
        dialNodes = RadialDialPresets.defaultRootNodes()
    }

    @ViewBuilder
    private func radialSliceEditorRow(index: Int, slice: RadialSliceNode) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: "\(index + 1)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Menu {
                ForEach(Self.radialIconChoices, id: \.self) { symbol in
                    Button {
                        updateEditableSlices { list in
                            if index < list.count { list[index].icon = .sfSymbol(symbol) }
                        }
                    } label: {
                        Label(symbol, systemImage: symbol)
                    }
                }
            } label: {
                radialSliceIconGlyph(slice.icon)
                    .frame(width: 22, height: 20)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            TextField("Slice", text: Binding(
                get: { index < currentEditableSlices.count ? currentEditableSlices[index].title : slice.title },
                set: { val in
                    updateEditableSlices { list in
                        if index < list.count { list[index].title = val }
                    }
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 150)

            Spacer(minLength: SettingsMetrics.rowMinimumLabelGap)

            Picker(selection: Binding(
                get: { sliceActionTag(for: slice) },
                set: { tag in applySliceActionTag(tag, at: index) }
            )) {
                Text("Submenu").tag("submenu")
                Divider()
                Text("Clipboard").tag("clipboard")
                Text("Shelf").tag("openShelf")
                Text("Capture").tag("captureArea")
                Text("Scan Text").tag("captureOCR")
                Text("Toggle Tiling").tag("toggleTiling")
                Divider()
                Text("Play").tag("mediaPlayPause")
                Text("Next Track").tag("mediaNext")
                Text("Previous Track").tag("mediaPrevious")
                Divider()
                Text("Maximize").tag("snapMaximize")
                Text("Left Half").tag("snapLeft")
                Text("Right Half").tag("snapRight")
                Text("Top Half").tag("snapTop")
                Text("Bottom Half").tag("snapBottom")
            } label: { EmptyView() }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()

            if slice.isSubmenu {
                Button { dialEditPath.append(slice.id) } label: {
                    HStack(spacing: 2) {
                        Text("Edit")
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                updateEditableSlices { list in
                    if list.count > 1, index < list.count { list.remove(at: index) }
                }
            } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(currentEditableSlices.count <= 1)
            .accessibilityLabel(Text("Remove"))
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func radialSliceIconGlyph(_ icon: RadialDialIcon) -> some View {
        switch icon {
        case .sfSymbol(let name), .system(let name): Image(systemName: name)
        case .app: Image(systemName: "app.fill")
        }
    }

    private static let sliceActionTable: [(tag: String, action: RadialDialActionType)] = [
        ("clipboard", .clipboard), ("openShelf", .openShelf), ("captureArea", .captureArea),
        ("captureOCR", .captureOCR), ("toggleTiling", .toggleTiling), ("mediaPlayPause", .mediaPlayPause),
        ("mediaNext", .mediaNext), ("mediaPrevious", .mediaPrevious), ("snapMaximize", .snap(.maximize)),
        ("snapLeft", .snap(.leftHalf)), ("snapRight", .snap(.rightHalf)),
        ("snapTop", .snap(.topHalf)), ("snapBottom", .snap(.bottomHalf))
    ]

    private func sliceActionTag(for slice: RadialSliceNode) -> String {
        if slice.isSubmenu { return "submenu" }
        return Self.sliceActionTable.first(where: { $0.action == slice.action })?.tag ?? "clipboard"
    }

    private func applySliceActionTag(_ tag: String, at index: Int) {
        updateEditableSlices { list in
            guard index < list.count else { return }
            if tag == "submenu" {
                if list[index].children?.isEmpty ?? true {
                    list[index].children = [
                        RadialSliceNode(id: "sub_\(UUID().uuidString.prefix(8))", title: String(localized: "Slice"), icon: .sfSymbol("sparkles"), action: .clipboard)
                    ]
                }
                return
            }
            if let mapped = Self.sliceActionTable.first(where: { $0.tag == tag }) {
                list[index].children = nil
                list[index].action = mapped.action
            }
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
                Menu {
                    Button(String(localized: "Default")) { quitOnClose.setIdleAction(nil, for: row.bundleID) }
                    Button(String(localized: "Keep")) { quitOnClose.setIdleAction(.keep, for: row.bundleID) }
                    Button(String(localized: "Notify")) { quitOnClose.setIdleAction(.notify, for: row.bundleID) }
                    Button(String(localized: "Hide")) { quitOnClose.setIdleAction(.hide, for: row.bundleID) }
                    Button(String(localized: "Quit")) { quitOnClose.setIdleAction(.quit, for: row.bundleID) }
                } label: {
                    Image(systemName: idleOverrideSymbol(for: row.bundleID))
                        .foregroundStyle(quitOnClose.idleAction(for: row.bundleID) == nil ? Color.secondary : Color.accentColor)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(Text("Idle App Rule"))
                .accessibilityLabel(Text("Idle App Rule"))
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

    private func idleOverrideSymbol(for bundleID: String) -> String {
        switch quitOnClose.idleAction(for: bundleID) {
        case .keep: return "lock.fill"
        case .notify: return "bell.fill"
        case .hide: return "eye.slash.fill"
        case .quit: return "power"
        case .off, nil: return "clock"
        }
    }
}

private struct QuitLifecycleOptionsView: View {
    @ObservedObject var quitService = QuitOnLastWindowService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsPickerRow(Text("Quit on Close"), selection: Binding(
                get: { quitService.mode },
                set: { quitService.setMode($0) }
            )) {
                Text("Off").tag(QuitOnCloseMode.off)
                Text("Selected Apps").tag(QuitOnCloseMode.selectedOnly)
                Text("All Except Excluded").tag(QuitOnCloseMode.allExceptExcluded)
            }
            if quitService.mode != .off {
                SettingsDivider()
                SettingsSliderRow(
                    Text("Close Delay"),
                    value: quitService.quitDelay,
                    range: 0.25...5.0,
                    step: 0.25,
                    valueText: String(format: "%.2fs", quitService.quitDelay),
                    set: { quitService.setQuitDelay($0) }
                )
            }
            SettingsDivider()
            SettingsPickerRow(Text("Idle Apps (Leaf / Quitter)"), selection: Binding(
                get: { quitService.idleThresholdSeconds > 0 ? quitService.idleAction : .off },
                set: { action in
                    if action == .off {
                        quitService.setIdleThresholdSeconds(0)
                    } else {
                        if quitService.idleThresholdSeconds <= 0 {
                            quitService.setIdleThresholdSeconds(1800)
                        }
                        quitService.setIdleAction(action)
                    }
                }
            )) {
                Text("Off").tag(IdleAppAction.off)
                Text("Notify to Quit").tag(IdleAppAction.notify)
                Text("Auto-Hide").tag(IdleAppAction.hide)
                Text("Auto-Quit").tag(IdleAppAction.quit)
            }
            if quitService.idleThresholdSeconds > 0 {
                SettingsDivider()
                SettingsPickerRow(Text("Idle After"), selection: Binding(
                    get: { quitService.idleThresholdSeconds },
                    set: { quitService.setIdleThresholdSeconds($0) }
                )) {
                    Text("15 min").tag(TimeInterval(900))
                    Text("30 min").tag(TimeInterval(1800))
                    Text("1 hour").tag(TimeInterval(3600))
                    Text("2 hours").tag(TimeInterval(7200))
                }
                SettingsDivider()
                SettingsPickerRow(Text("Minimum RAM"), selection: Binding(
                    get: { quitService.idleMinMemoryMB },
                    set: { quitService.setIdleMinMemoryMB($0) }
                )) {
                    Text("Any").tag(0)
                    Text("500 MB").tag(500)
                    Text("1 GB").tag(1024)
                    Text("2 GB").tag(2048)
                }
            }
        }
    }
}

private struct MultitouchGesturesSection: View {
    @ObservedObject var dispatcher = GestureDispatcher.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsToggleRow(
                Text("Multitouch Gestures"),
                isOn: Binding(get: { dispatcher.isEnabled }, set: { dispatcher.setEnabled($0) }),
                info: String(localized: "Map 2, 3, and 4-finger trackpad swipes, pinches, and taps to KatiKati actions.")
            )
            SettingsDivider()
            DisclosureGroup("Gesture Mapping & Live Visualizer") {
                GesturePreviewStage(dispatcher: dispatcher)
                SettingsDivider()
                SettingsSliderRow(
                    Text("Swipe Sensitivity"),
                    value: dispatcher.swipeThreshold,
                    range: 0.06...0.30,
                    step: 0.02,
                    valueText: String(format: "%.2f", dispatcher.swipeThreshold),
                    set: { dispatcher.setSwipeThreshold($0) }
                )
                SettingsDivider()
                SettingsSliderRow(
                    Text("Flick Velocity"),
                    value: dispatcher.flickVelocityThreshold,
                    range: 0.25...1.50,
                    step: 0.05,
                    valueText: String(format: "%.2f", dispatcher.flickVelocityThreshold),
                    set: { dispatcher.setFlickVelocityThreshold($0) }
                )
                HStack(spacing: 12) {
                    Button("Apply Clash-Free Preset") { dispatcher.applyClashFreePreset() }
                    Button("Open Trackpad Settings…") { openTrackpadSettings() }
                }
                .buttonStyle(.link)
                .padding(.vertical, 6)
                ForEach(MultitouchGestureKind.allCases) { kind in
                    SettingsDivider()
                    GestureBindingRow(dispatcher: dispatcher, kind: kind)
                }
            }
        }
        // The clash badges are advisory: read the live settings when the page opens, never poll.
        .onAppear { dispatcher.refreshTrackpadSettings() }
    }

}

private func gestureTitleFor(_ kind: MultitouchGestureKind) -> String {
    switch kind {
    case .threeFingerSwipeLeft: return String(localized: "3-Finger Swipe Left")
    case .threeFingerSwipeRight: return String(localized: "3-Finger Swipe Right")
    case .threeFingerSwipeUp: return String(localized: "3-Finger Swipe Up")
    case .threeFingerSwipeDown: return String(localized: "3-Finger Swipe Down")
    case .fourFingerSwipeLeft: return String(localized: "4-Finger Swipe Left")
    case .fourFingerSwipeRight: return String(localized: "4-Finger Swipe Right")
    case .fourFingerSwipeUp: return String(localized: "4-Finger Swipe Up")
    case .fourFingerSwipeDown: return String(localized: "4-Finger Swipe Down")
    case .pinchIn: return String(localized: "Pinch In")
    case .pinchOut: return String(localized: "Pinch Out")
    case .fourFingerTap: return String(localized: "4-Finger Tap")
    case .twoFingerRightEdgeSwipeLeft: return String(localized: "Right-Edge Swipe Left")
    case .threeFingerTipTapLeft: return String(localized: "3-Finger Tap Left")
    case .threeFingerTipTapRight: return String(localized: "3-Finger Tap Right")
    }
}

private func gestureActionTitle(_ action: GestureActionTarget) -> String {
    switch action {
    case .none: return String(localized: "None")
    case .toggleNotch: return String(localized: "Toggle Notch")
    case .commandBar: return String(localized: "Command Bar")
    case .launcher: return String(localized: "Launcher")
    case .spaceLeft: return String(localized: "Space Left")
    case .spaceRight: return String(localized: "Space Right")
    case .snapLeft: return String(localized: "Snap Left Half")
    case .snapRight: return String(localized: "Snap Right Half")
    case .snapCycleLeft: return String(localized: "Snap Left and Cycle Width")
    case .snapCycleRight: return String(localized: "Snap Right and Cycle Width")
    case .maximize: return String(localized: "Maximize")
    case .centerRestore: return String(localized: "Center")
    case .windowSwitcher: return String(localized: "Window Switcher")
    case .nextDisplay: return String(localized: "Next Display")
    case .previousDisplay: return String(localized: "Previous Display")
    case .toggleTiling: return String(localized: "Toggle Tiling")
    case .stripNext: return String(localized: "Focus Next Column")
    case .stripPrevious: return String(localized: "Focus Previous Column")
    case .stripCycleWidth: return String(localized: "Cycle Column Width")
    case .stripStack: return String(localized: "Stack Columns")
    case .stripTabs: return String(localized: "Toggle Column Tabs")
    case .stripSwapNext: return String(localized: "Swap With Next Column")
    case .stripSwapPrevious: return String(localized: "Swap With Previous Column")
    case .quickLayoutPicker: return String(localized: "Quick Layout Picker")
    }
}

private func openTrackpadSettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension") else { return }
    NSWorkspace.shared.open(url)
}

/// Three states, never two: a green dot only appears when the settings actually say the slot is free.
private struct GestureConflictBadge: View {
    let conflict: GestureConflict

    var body: some View {
        switch conflict {
        case .clear:
            Circle().fill(Color.green).frame(width: 7, height: 7)
                .accessibilityLabel(Text("Clear"))
        case .clash:
            Circle().fill(Color.orange).frame(width: 7, height: 7)
                .help(Text("Used by macOS"))
                .accessibilityLabel(Text("Used by macOS"))
        case .unverifiable:
            Circle().fill(Color.secondary.opacity(0.6)).frame(width: 7, height: 7)
                .help(Text("Could not verify"))
                .accessibilityLabel(Text("Could not verify"))
        }
    }
}

/// One gesture: what it does with tiling off, and what it does instead with tiling on.
private struct GestureBindingRow: View {
    @ObservedObject var dispatcher: GestureDispatcher
    let kind: MultitouchGestureKind

    private var rule: GestureBindingRule { dispatcher.rules[kind] ?? .off }
    private var conflict: GestureConflict {
        TrackpadConflictDetector.conflict(for: kind, settings: dispatcher.trackpadSettings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                GestureConflictBadge(conflict: conflict)
                Text(verbatim: gestureTitleFor(kind)).font(.callout)
                Spacer(minLength: 8)
                actionMenu(title: gestureActionTitle(rule.windowAction)) { action in
                    dispatcher.setAction(action, for: kind)
                }
            }
            HStack(spacing: 6) {
                Text("Window").font(.caption2).foregroundStyle(.secondary).frame(width: 46, alignment: .leading)
                Spacer(minLength: 8)
                actionMenu(title: rule.tilingAction.map(gestureActionTitle) ?? String(localized: "Same as Window")) { action in
                    dispatcher.setTilingAction(action, for: kind)
                }
            }
        }
        .padding(.vertical, 5)
    }

    private func actionMenu(title: String, set: @escaping (GestureActionTarget) -> Void) -> some View {
        Menu {
            ForEach(GestureActionTarget.allCases) { action in
                Button(gestureActionTitle(action)) { set(action) }
            }
        } label: {
            Text(verbatim: title)
                .font(.callout)
                .lineLimit(1)
                .frame(minWidth: 150, alignment: .trailing)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

/// Live fingers on the left, the resolved action drawn by the real solvers on the right.
private struct GesturePreviewStage: View {
    @ObservedObject var dispatcher: GestureDispatcher
    @ObservedObject private var engine = TilingEngine.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var picked: MultitouchGestureKind = .threeFingerSwipeLeft

    private var rule: GestureBindingRule { dispatcher.rules[picked] ?? .off }
    private var context: GestureContext { GestureContext(tilingEnabled: engine.isEnabled) }
    private var resolved: GestureActionTarget? { GestureRouter.target(for: rule, context: context) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                trackpadPane
                actionPane
            }
            .frame(height: 96)
            HStack(spacing: 6) {
                Menu {
                    ForEach(MultitouchGestureKind.allCases) { kind in
                        Button(gestureTitleFor(kind)) { picked = kind }
                    }
                } label: {
                    Text(verbatim: gestureTitleFor(picked)).font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Text(verbatim: "\u{2192}").font(.caption2).foregroundStyle(.tertiary)
                Text(verbatim: resolved.map(gestureActionTitle) ?? String(localized: "None"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if context.tilingEnabled { Text("Tiling").font(.caption2).foregroundStyle(.tertiary) }
            }
        }
        .padding(.vertical, 6)
        .onAppear { dispatcher.beginVisualizer() }
        .onDisappear { dispatcher.endVisualizer() }
        .onChange(of: dispatcher.lastGesture) { _, kind in if let kind { picked = kind } }
    }

    private var trackpadPane: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06))
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                if dispatcher.livePoints.isEmpty {
                    keyframeArt(in: geo.size)
                } else {
                    liveArt(in: geo.size)
                }
            }
        }
    }

    private func keyframeArt(in size: CGSize) -> some View {
        let points = Self.keyframe(for: picked)
        return ZStack {
            ForEach(Array(points.enumerated()), id: \.offset) { _, at in
                Circle().fill(Color.secondary.opacity(0.5))
                    .frame(width: 12, height: 12)
                    .position(x: at.x * size.width, y: (1 - at.y) * size.height)
            }
            Text(verbatim: Self.glyph(for: picked))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .position(x: size.width / 2, y: size.height * 0.82)
        }
    }

    private func liveArt(in size: CGSize) -> some View {
        let points = dispatcher.livePoints
        return ZStack {
            ForEach(points, id: \.id) { pt in
                Circle().fill(Color.accentColor.opacity(0.85))
                    .frame(width: 14, height: 14)
                    .position(x: min(max(8, pt.x * size.width), size.width - 8),
                              y: min(max(8, (1 - pt.y) * size.height), size.height - 8))
            }
        }
    }

    private var actionPane: some View {
        GeometryReader { geo in
            let area = CGRect(origin: .zero, size: geo.size).insetBy(dx: 8, dy: 8)
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                actionArt(in: area)
            }
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86), value: picked)
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86), value: engine.preset)
        }
    }

    @ViewBuilder
    private func actionArt(in area: CGRect) -> some View {
        if context.tilingEnabled, rule.tilingAction != nil {
            tilingArt(in: area)
        } else if let position = Self.snapPosition(for: resolved) {
            snapArt(position, in: area)
        } else {
            Image(systemName: Self.symbol(for: resolved))
                .font(.title3)
                .foregroundStyle(.secondary)
                .position(x: area.midX, y: area.midY)
        }
    }

    /// The engine's own solver, so the preview cannot drift from what tiling does.
    private func tilingArt(in area: CGRect) -> some View {
        let rects = TilingPreview.rects(preset: engine.preset, area: area, gap: engine.gaps.inner * 0.25)
        return ZStack {
            ForEach(Array(rects.enumerated()), id: \.offset) { _, r in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.white.opacity(0.5), lineWidth: 1))
                    .frame(width: max(2, r.width), height: max(2, r.height))
                    .position(x: r.midX, y: r.midY)
            }
        }
    }

    private func snapArt(_ position: SnapPosition, in area: CGRect) -> some View {
        let r = position.frame(in: area)
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.accentColor.opacity(0.28))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 1))
            .frame(width: max(2, r.width), height: max(2, r.height))
            .position(x: r.midX, y: r.midY)
    }

    private static func snapPosition(for action: GestureActionTarget?) -> SnapPosition? {
        switch action {
        case .snapLeft, .snapCycleLeft: return .leftHalf
        case .snapRight, .snapCycleRight: return .rightHalf
        case .maximize: return .maximize
        case .centerRestore: return .center
        default: return nil
        }
    }

    private static func symbol(for action: GestureActionTarget?) -> String {
        guard let action, action != .none else { return "questionmark" }
        switch action {
        case .windowSwitcher: return "rectangle.on.rectangle"
        case .nextDisplay, .previousDisplay: return "display.2"
        case .toggleTiling: return "square.grid.2x2"
        case .quickLayoutPicker, .stripStack, .stripTabs, .stripCycleWidth,
             .stripSwapNext, .stripSwapPrevious, .stripNext, .stripPrevious: return "rectangle.split.3x1"
        case .commandBar: return "circle.hexagongrid"
        case .launcher: return "square.grid.3x3"
        case .toggleNotch: return "menubar.rectangle"
        case .spaceLeft, .spaceRight: return "rectangle.split.2x1"
        case .none, .snapLeft, .snapRight, .snapCycleLeft, .snapCycleRight, .maximize, .centerRestore: return "macwindow"
        }
    }

    private static func keyframe(for kind: MultitouchGestureKind) -> [CGPoint] {
        let count = Self.fingerCount(kind)
        let spacing = 0.09
        return (0..<count).map { i in
            CGPoint(x: 0.5 + (CGFloat(i) - CGFloat(count - 1) / 2) * spacing, y: 0.5)
        }
    }

    private static func fingerCount(_ kind: MultitouchGestureKind) -> Int {
        switch kind {
        case .twoFingerRightEdgeSwipeLeft: return 2
        case .threeFingerSwipeLeft, .threeFingerSwipeRight, .threeFingerSwipeUp, .threeFingerSwipeDown,
             .threeFingerTipTapLeft, .threeFingerTipTapRight: return 3
        default: return 4
        }
    }

    private static func glyph(for kind: MultitouchGestureKind) -> String {
        switch kind {
        case .threeFingerSwipeLeft, .fourFingerSwipeLeft, .twoFingerRightEdgeSwipeLeft: return "\u{2190}"
        case .threeFingerSwipeRight, .fourFingerSwipeRight: return "\u{2192}"
        case .threeFingerSwipeUp, .fourFingerSwipeUp: return "\u{2191}"
        case .threeFingerSwipeDown, .fourFingerSwipeDown: return "\u{2193}"
        case .pinchIn: return "\u{2192}\u{2190}"
        case .pinchOut: return "\u{2190}\u{2192}"
        case .fourFingerTap: return "\u{25CF}"
        case .threeFingerTipTapLeft: return "\u{2022}\u{2190}"
        case .threeFingerTipTapRight: return "\u{2192}\u{2022}"
        }
    }
}

/// Orange stop sign on a row whose binding could not be registered; the previous binding is gone, so say so.
struct ShortcutFailureIcon: View {
    let action: ShortcutAction
    @ObservedObject private var state = ShortcutRegistrationState.shared
    var body: some View {
        if let why = state.failures[action] {
            Image(systemName: "xmark.octagon.fill").foregroundColor(.red).help(Text(verbatim: why))
        }
    }
}

/// Reusable trailing shortcut controls (conflict icon, failure status, trigger menu, and key recorder).
struct ShortcutActionControls: View {
    @ObservedObject var store: AppSettingsStore
    let action: ShortcutAction
    let duplicated: Set<ShortcutAction>

    var body: some View {
        HStack(spacing: SettingsMetrics.controlSpacing) {
            if case .warn(let why) = ShortcutValidator.check(store.shortcutBindings[action] ?? .off, for: action, among: store.shortcutBindings) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    .help(Text(verbatim: why))
            } else if duplicated.contains(action) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    .help(Text("Another action uses the same shortcut"))
            }
            ShortcutFailureIcon(action: action)
            Picker(selection: Binding(get: { store.shortcutBindings[action] ?? .off },
                                      set: { store.setShortcut(action, $0) })) {
                Text("Off").tag(ShortcutTrigger.off)
                Divider()
                ForEach(ShortcutChord.allCases, id: \.self) { Text(verbatim: $0.glyphs).tag(ShortcutTrigger.chord($0)) }
                Divider()
                ForEach(ShortcutTapKey.allCases, id: \.self) { key in
                    (Text("Double-tap") + Text(verbatim: key == .fn ? " fn" : " \(key.glyph) (\(key.isRight ? "R" : "L"))")).tag(ShortcutTrigger.doubleTap(key))
                }
                Divider()
                ForEach(ShortcutTapKey.allCases, id: \.self) { key in
                    (Text("Hold") + Text(verbatim: key == .fn ? " fn" : " \(key.glyph) (\(key.isRight ? "R" : "L"))")).tag(ShortcutTrigger.hold(key))
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
            .accessibilityLabel(Text(verbatim: SettingsLayoutPane.shortcutActionName(action)))
            ShortcutRecorderButton { store.setShortcut(action, .key($0)) }
        }
    }
}
