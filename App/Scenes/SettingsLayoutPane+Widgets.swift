import SwiftUI

/// Slice B (OpenTaskbar behavior, MIT): the app injects the Dock-pin importer once at the Settings root, so this
/// pane (which also compiles into the test target) never needs `KeptAppStore` — nil hides the row.
struct SettingsImportDockPinsKey: EnvironmentKey {
    static let defaultValue: (() -> Int)? = nil
}

extension EnvironmentValues {
    var importDockPins: (() -> Int)? {
        get { self[SettingsImportDockPinsKey.self] }
        set { self[SettingsImportDockPinsKey.self] = newValue }
    }
}

struct DockProfileActions {
    var summaries: () -> [BarProfileSummary]
    var save: (String) -> BarProfile?
    var apply: (String) -> Void
    var delete: (String) -> Void
}

private struct DockProfilesCard: View {
    let actions: DockProfileActions
    @State private var name = ""
    @State private var profiles: [BarProfileSummary] = []

    var body: some View {
        SettingsCard(Text("Dock Profiles")) {
            if profiles.isEmpty {
                Text("None").foregroundStyle(.secondary)
            } else {
                ForEach(profiles) { profile in
                    SettingsRow(Text(verbatim: profile.name)) {
                        Button("Apply") { actions.apply(profile.id) }.controlSize(.small)
                        Button("Delete") {
                            actions.delete(profile.id)
                            profiles = actions.summaries()
                        }.controlSize(.small)
                    }
                    SettingsDivider()
                }
            }
            SettingsDivider()
            SettingsRow(Text("New Profile")) {
                TextField("Name", text: $name).textFieldStyle(.roundedBorder).frame(width: 160)
                Button("Save") {
                    if actions.save(name) != nil {
                        name = ""
                        profiles = actions.summaries()
                    }
                }
                .controlSize(.small)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear { profiles = actions.summaries() }
    }
}

private struct DockProfileActionsKey: EnvironmentKey {
    static let defaultValue: DockProfileActions? = nil
}

extension EnvironmentValues {
    var dockProfileActions: DockProfileActions? {
        get { self[DockProfileActionsKey.self] }
        set { self[DockProfileActionsKey.self] = newValue }
    }
}

// The Widgets mode of `SettingsLayoutPane`; state lives in the main file.
extension SettingsLayoutPane {
    @ViewBuilder
    var widgetSections: some View {
        // The dock's own four choices, in one card (2026-10-26, Dockey-shaped): position, hide,
        // reveal delay and animation speed used to be spread over Appearance, the status menu's
        // auto-hide slider and this page's motion row. Same setters, no new engine — the dock is on
        // screen and relayouts on every one of these `@Published` writes, so the card is its own
        // live preview. "Reset" puts back a fresh install's four values.
        SettingsCard(Text("Dock")) {
            SettingsSegmentedRow(Text("Position"), selection: Binding(
                get: { store.stripPlacementMap.global },
                set: { store.setStripPlacement($0) }
            )) {
                Text("Bottom").tag(StripPlacement.bottom)
                Text("Left").tag(StripPlacement.left)
                Text("Right").tag(StripPlacement.right)
            }
            SettingsDivider()
            // Hide/Show rather than a toggle: the same pair Dockey shows, and the value is the
            // store's own `edgeAutoHideEnabled` (delay == neverHide), never a copy of it.
            SettingsSegmentedRow(Text("Hide Dock"), selection: Binding(
                get: { store.edgeAutoHideEnabled },
                set: { hidden in
                    if hidden != store.edgeAutoHideEnabled { store.toggleEdgeAutoHideMode() }
                }
            )) {
                Text("Hide").tag(true)
                Text("Show").tag(false)
            }
            SettingsDivider()
            // Delay only exists while the dock hides; while it is always visible the row would
            // write a delay nothing reads, so it is disabled instead.
            SettingsSegmentedRow(Text("Animation Delay"), selection: Binding(
                get: { DockRevealDelayPreset.matching(store.lastEnabledEdgeAutoHideDelay) ?? .none },
                set: { store.setEdgeAutoHideDelay($0.seconds) }
            )) {
                ForEach(DockRevealDelayPreset.allCases, id: \.self) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .disabled(!store.edgeAutoHideEnabled)
            SettingsDivider()
            SettingsSegmentedRow(Text("Animation Speed"), selection: $dockMotion) {
                ForEach(Self.dockSpeedOrder, id: \.self) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .help(Text("How the dock widgets' readings move when they change."))
            SettingsDivider()
            SettingsRow(Text("Restore")) {
                Button {
                    store.setStripPlacement(.bottom)
                    store.setEdgeAutoHideDelay(AppSettingsStore.firstRunEdgeAutoHideDelay)
                    dockMotion = .default
                } label: {
                    Text("Reset")
                }
                .controlSize(.small)
            }
        }

        if let actions = dockProfileActions {
            DockProfilesCard(actions: actions)
        }

        // The widget-look block is composed by the Widgets tab instead: its controls live in the
        // app-only `SettingsWindowView`, and this pane also compiles into the test target.
        SettingsCard(Text("Dock Layout")) {
            if !stageVisible {
                DockLivePreviewStrip(
                    mode: store.barLayoutMode,
                    visibleOrder: store.widgetLayout.visibleOrder,
                    wings: store.dockWings,
                    placement: store.stripPlacementMap.global
                )
                SettingsDivider()
            }
            SettingsRow(Text("Detached Capsule")) {
                Picker("Detached Capsule", selection: Binding<DockSlotItem?>(
                    get: { store.dockSlotLayout.trailingCapsule },
                    set: { store.setTrailingCapsule($0) }
                )) {
                    Text(DockSlotItem.controlCenter.title).tag(DockSlotItem?.some(.controlCenter))
                    Text(DockSlotItem.backgroundApps.title).tag(DockSlotItem?.some(.backgroundApps))
                    Text(DockSlotItem.trash.title).tag(DockSlotItem?.some(.trash))
                    Text(DockSlotItem.launcher.title).tag(DockSlotItem?.some(.launcher))
                    Text(DockSlotItem.shelf.title).tag(DockSlotItem?.some(.shelf))
                    Text("Off").tag(DockSlotItem?.none)
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            SettingsDivider()
            SettingsRow(Text("Background & Activity Icon")) {
                Picker("Background & Activity Icon", selection: Binding(
                    get: { store.backgroundActivityIconMode },
                    set: { store.setBackgroundActivityIconMode($0) }
                )) {
                    ForEach(BackgroundActivityIconMode.allCases) { iconMode in
                        Text(verbatim: iconMode.localizedTitle).tag(iconMode)
                    }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            SettingsDivider()
            SettingsToggleRow(
                Text("Mid-Dock Utilities"),
                isOn: Binding(
                    get: { store.dockSlotLayout.groupAdjacentUtilities },
                    set: { store.setDockSlotLayout(DockSlotLayout(
                        items: store.dockSlotLayout.items,
                        trailingCapsule: store.dockSlotLayout.trailingCapsule,
                        groupAdjacentUtilities: $0
                    )) }
                )
            )
            let slotEntries = store.dockSlotLayout.items.filter { $0.item != .drawer }
            ForEach(Array(slotEntries.enumerated()), id: \.element.item) { index, entry in
                SettingsDivider()
                HStack(spacing: SettingsMetrics.controlSpacing) {
                    Text(entry.item.title)
                    Spacer(minLength: SettingsMetrics.controlSpacing)
                    Toggle(isOn: Binding(
                        get: { !(store.dockSlotLayout.items.first { $0.item == entry.item }?.isHidden ?? false) },
                        set: { store.setDockSlotItem(entry.item, hidden: !$0) }
                    )) {
                        EmptyView()
                    }
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(Text(entry.item.title))
                    Button {
                        let items = store.dockSlotLayout.items
                        if let raw = items.firstIndex(where: { $0.item == entry.item }),
                           let target = items[..<raw].lastIndex(where: { $0.item != .drawer }) {
                            store.moveDockSlotItem(entry.item, by: target - raw)
                        }
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                    Button {
                        let items = store.dockSlotLayout.items
                        if let raw = items.firstIndex(where: { $0.item == entry.item }),
                           let target = items.indices.dropFirst(raw + 1).first(where: { items[$0].item != .drawer }) {
                            store.moveDockSlotItem(entry.item, by: target - raw)
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == slotEntries.count - 1)
                }
            }
            // Slice B: the system Dock's pinned apps, adopted into the bar's kept list.
            if let importDockPins {
                SettingsDivider()
                SettingsRow(Text("Import from Dock")) {
                    Button {
                        importedDockPinCount = importDockPins()
                    } label: {
                        if importedDockPinCount > 0 {
                            Text("Imported")
                        } else {
                            Text("Import")
                        }
                    }
                    .controlSize(.small)
                    .disabled(importedDockPinCount > 0)
                }
            }
            SettingsDivider()
            SettingsRow(Text("Utility Popups")) {
                HStack(spacing: 8) {
                    Picker("Flyout Style", selection: Binding(
                        get: { store.dockUtilities.flyoutPreset },
                        set: { store.setUtilityFlyoutPreset($0) }
                    )) {
                        ForEach(UtilityFlyoutPreset.allCases) { preset in
                            Text(verbatim: preset.localizedTitle).tag(preset)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                    Picker("Popup Placement", selection: Binding(
                        get: { store.dockUtilities.popoverPlacement },
                        set: { store.setUtilityPopoverPlacement($0) }
                    )) {
                        ForEach(UtilityPopoverPlacement.allCases) { mode in
                            Text(verbatim: mode.localizedTitle).tag(mode)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                    Picker("Dismissal", selection: Binding(
                        get: { store.dockUtilities.dismissalBehavior },
                        set: { store.setUtilityDismissalBehavior($0) }
                    )) {
                        ForEach(UtilityDismissalBehavior.allCases) { rule in
                            Text(verbatim: rule.localizedTitle).tag(rule)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
            }
            SettingsDivider()
            SettingsToggleRow(Text("Keep windows above the taskbar"), isOn: Binding(
                get: { store.windowLiftEnabled },
                set: { store.setWindowLiftEnabled($0) }
            ))
        }
    }

    @ViewBuilder
    var barWidgetSections: some View {
        SettingsCard(Text("Bar Widgets")) {
            SettingsRow(Text("Search widgets")) {
                TextField("Search widgets", text: $widgetQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
            }
            SettingsDivider()
            if widgetQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                List {
                    ForEach(store.widgetLayout.order, id: \.self) { widget in
                        widgetRow(widget)
                            .listRowInsets(EdgeInsets())
                    }
                    .onMove { store.setWidgetLayout(store.widgetLayout.moving(from: $0, to: $1)) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, -Self.listRowChromeInset)
                .frame(height: min(Self.widgetListHeight(count: store.widgetLayout.order.count),
                                   widgetListCap))
                .clipped()
            } else {
                widgetCatalogList
                    .clipped()
            }
            SettingsDivider()
            HStack(spacing: SettingsMetrics.controlSpacing) {
                presetControls
                Spacer(minLength: SettingsMetrics.controlSpacing)
                contextPresetsToggle
            }
            contextPresetRows
            SettingsDivider()
            SettingsRow(Text("Right FAB Style")) {
                Picker("Right FAB Style", selection: $fabStyleRaw) {
                    Text("Dynamic Gauge").tag("gauge")
                    Text("Classic Glyph").tag("classic")
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            .help(Text("The dock's right button: a live gauge or a single glyph."))
        }
    }

    /// Fast → slow. `WidgetMotionPreset.allCases` is storage order (Fluid first, Slow last), which
    /// is not a scale; the row is.
    static let dockSpeedOrder: [WidgetMotionPreset] = [.instant, .snappy, .fluid, .slow]

    func widgetLabel(_ widget: BarSection) -> Text {
        switch widget {
        case .weather: return Text("Weather")
        case .media: return Text("Now Playing")
        case .utilities: return Text("Utilities")
        case .launcher: return Text("Launcher")
        case .apps: return Text("Apps")
        case .widgets: return Text("Widgets")
        case .clock: return Text("Clock")
        case .calendar: return Text("Calendar")
        case .system: return Text("System")
        case .devices: return Text("Devices")
        case .drives: return Text("Drives")
        case .dictionary: return Text("Dictionary")
        case .terminal: return Text("Terminal")
        case .ai: return Text("AI")
        }
    }

    /// 10a-7: the switch that arms the time-window presets. It shares its line with the preset row
    /// above (`widgetSections`); the rows it opens are `contextPresetRows`.
    var contextPresetsToggle: some View {
        Toggle(isOn: Binding(get: { store.contextPresetsEnabled }, set: store.setContextPresetsEnabled)) {
            Text("Context Presets")
        }
        .accessibilityLabel("Context Presets")
    }

    /// 10a-7: pick a preset per time window; fixed windows (Work Hours Mon–Fri 09:00–17:00, Evening 18:00–23:00).
    @ViewBuilder
    var contextPresetRows: some View {
        if store.contextPresetsEnabled {
            // One compact line (2026-10-18): the two menus as a house pair plus a caption under them
            // were 43 pt, and with the presets armed this page had 32 pt more than the window has.
            // Both menus, the windows' fixed hours and every option are unchanged.
            HStack(spacing: 16) {
                contextPicker(Text("Work Hours"), selection: store.contextWorkPresetID, set: store.setContextWorkPreset)
                contextPicker(Text("Evening"), selection: store.contextEveningPresetID, set: store.setContextEveningPreset)
                Spacer(minLength: 8)
                Text(verbatim: "Mon–Fri 09:00–17:00 · 18:00–23:00")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    func contextPicker(_ label: Text, selection: String, set: @escaping (String) -> Void) -> some View {
        HStack {
            label
            Spacer(minLength: 8)
            Picker("Presets", selection: Binding(get: { selection }, set: set)) {
                Text("None").tag("")
                ForEach(WidgetPresets.builtIns + store.userWidgetPresets) { Text($0.localizedTitle).tag($0.id) }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    var presetControls: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(WidgetPresets.builtIns) { preset in
                    Button(preset.localizedTitle) { store.applyWidgetPreset(preset) }
                }
                if !store.userWidgetPresets.isEmpty {
                    Divider()
                    ForEach(store.userWidgetPresets) { preset in
                        Button(preset.name) { store.applyWidgetPreset(preset) }
                    }
                    Divider()
                    Menu("Delete") {
                        ForEach(store.userWidgetPresets) { preset in
                            Button(preset.name) { store.deleteWidgetPreset(id: preset.id) }
                        }
                    }
                }
            } label: {
                Text("Presets")
            }
            .fixedSize()
            TextField("Name", text: $newPresetName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 160)
            Button("Save Current Layout") {
                store.saveCurrentWidgetLayout(as: newPresetName)
                newPresetName = ""
            }
            .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    /// The list's height bound. Arming Context Presets adds a row under the list, so the list hands that
    /// row its 41 pt back and the page stays inside the 1074 pt clamp either way (measured 1061 pt with
    /// the presets off, `DOCK_SETTINGS_PAGE_HEIGHT`).
    var widgetListCap: CGFloat {
        let searchRow = Self.widgetRowHeight + 4
        return max(Self.widgetRowHeight * 4, Self.widgetListMaxHeight - searchRow
            - (store.contextPresetsEnabled ? Self.widgetRowHeight + 4 : 0))
    }

    static func hoverAnimationTitle(_ style: DockHoverAnimationStyle) -> Text {
        switch style {
        case .none: return Text("None")
        case .magnification: return Text("Magnification")
        case .springLift: return Text("Spring Lift")
        case .jiggle: return Text("Jiggle")
        case .colorAura: return Text("Color Aura")
        case .slidingPill: return Text("Sliding Pill")
        case .magneticPull: return Text("Magnetic Pull")
        }
    }

    static func pressAnimationTitle(_ style: DockPressAnimationStyle) -> Text {
        switch style {
        case .tactileSquish: return Text("Tactile Squish")
        case .launchBounce: return Text("Launch Bounce")
        case .ripple: return Text("Ripple")
        case .flip3D: return Text("Flip 3D")
        }
    }

    static func runningIndicatorTitle(_ style: DockRunningIndicatorStyle) -> Text {
        switch style {
        case .macDot: return Text("Dot")
        case .windowsPill: return Text("Windows Pill")
        case .latteBrandLine: return Text("Brand Line")
        }
    }

    /// SF Symbol per module, so a row reads as an icon + title like the dock's own tiles.
    func widgetSymbol(_ widget: BarSection) -> String {
        switch widget {
        case .launcher: return "square.grid.2x2"
        case .weather: return "cloud.sun"
        case .apps: return "rectangle.on.rectangle"
        case .media: return "music.note"
        case .utilities: return "square.grid.2x2.fill"
        case .clock: return "clock"
        case .calendar: return "calendar"
        case .system: return "cpu"
        case .devices: return "headphones"
        case .drives: return "internaldrive"
        case .dictionary: return "character.book.closed"
        case .terminal: return "terminal"
        case .ai: return "sparkles"
        case .widgets: return "slider.horizontal.3"
        }
    }

    /// One reorderable row: drag handle, module icon + name, S/M/L (sizable widgets only), show/hide
    /// (never for Apps). Same shape for every module, whatever the module is.
    func widgetRow(_ widget: BarSection) -> some View {
        let instance = store.widgetLayout.instance(for: widget)
        return HStack(spacing: 10) {
            // The `List`'s drag is the whole row; the handle says so without adding a second gesture.
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Image(systemName: widgetSymbol(widget))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 14)
                .accessibilityHidden(true)
            widgetLabel(widget)
                .foregroundStyle(instance.isVisible ? .primary : .secondary)
            Spacer(minLength: 8)
            if widget.supportsWidgetSizes {
                Picker("Size", selection: Binding(
                    get: { instance.size },
                    set: { store.setWidgetSize($0, for: widget) }
                )) {
                    Text("Small").tag(WidgetSize.small)
                    Text("Medium").tag(WidgetSize.medium)
                    Text("Large").tag(WidgetSize.large)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                .disabled(!instance.isVisible)
            }
            if widget != .apps {
                Button {
                    store.setWidgetVisible(!instance.isVisible, for: widget)
                } label: {
                    Image(systemName: instance.isVisible ? "eye" : "eye.slash")
                }
                .buttonStyle(.borderless)
                .help(instance.isVisible ? Text("Hide") : Text("Show"))
            }
        }
        .frame(height: Self.widgetRowHeight)
    }

    // MARK: - Slice G: the widget catalog

    /// Reads the same layout and `show…` values the dock reads, so a row's installed state and the bar can
    /// never disagree.
    var widgetCatalogItems: [WidgetCatalogItem] {
        WidgetCatalog.items(layout: store.widgetLayout,
                            utilities: WidgetCatalogUtilities(shelf: store.showShelf, trash: store.showTrash,
                                                              drawer: store.showDrawer,
                                                              backgroundApps: store.showBackgroundApps),
                            userPresets: store.userWidgetPresets)
    }

    var widgetCatalogMatches: [WidgetCatalogItem] {
        WidgetCatalog.search(widgetQuery, in: widgetCatalogItems)
    }

    /// Replaces the module list while a query is typed: same height budget, so the page never grows.
    var widgetCatalogList: some View {
        let matches = widgetCatalogMatches
        return List {
            if matches.isEmpty {
                SettingsRow(Text("No matches")) { Spacer(minLength: 0) }
                    .listRowInsets(EdgeInsets())
            }
            ForEach(matches) { item in
                widgetCatalogRow(item)
                    .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, -Self.listRowChromeInset)
        .frame(height: min(Self.widgetListHeight(count: max(matches.count, 1)), widgetListCap))
    }

    /// One result: its localized title, its state, and the buttons that state offers (Install, Hide, Remove).
    func widgetCatalogRow(_ item: WidgetCatalogItem) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: item.title)
                .foregroundStyle(item.isInstalled ? .primary : .secondary)
            Spacer(minLength: 8)
            ForEach(WidgetCatalog.actions(for: item), id: \.self) { action in
                Button {
                    performCatalogAction(action, on: item)
                } label: {
                    catalogActionLabel(action)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .frame(height: Self.widgetRowHeight)
    }

    func catalogActionLabel(_ action: WidgetCatalogAction) -> Text {
        switch action {
        case .install: return Text("Install")
        case .hide: return Text("Hide")
        case .remove: return Text("Remove")
        }
    }

    /// Every action edits the preference that already owns the value: the widget layout, the `show…` keys, or
    /// the stored presets.
    func performCatalogAction(_ action: WidgetCatalogAction, on item: WidgetCatalogItem) {
        switch action {
        case .install:
            switch item.target {
            case .section(let section):
                store.setWidgetVisible(true, for: section)
            case .utility(let utility):
                setCatalogUtility(utility, to: true)
            case .preset(let id):
                if let preset = (WidgetPresets.builtIns + store.userWidgetPresets).first(where: { $0.id == id }) {
                    store.applyWidgetPreset(preset)
                }
            }
        case .hide:
            switch item.target {
            case .section(let section):
                store.setWidgetVisible(false, for: section)
            case .utility(let utility):
                setCatalogUtility(utility, to: false)
            case .preset:
                break
            }
        case .remove:
            if case .preset(let id) = item.target { store.deleteWidgetPreset(id: id) }
        }
    }

    func setCatalogUtility(_ utility: WidgetCatalogUtility, to value: Bool) {
        switch utility {
        case .shelf: store.setShowShelf(value)
        case .trash: store.setShowTrash(value)
        case .drawer: store.setShowDrawer(value)
        case .backgroundApps: store.setShowBackgroundApps(value)
        }
    }
}
