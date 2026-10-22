import SwiftUI

// The Widgets mode of `SettingsLayoutPane`; state lives in the main file.
extension SettingsLayoutPane {
    @ViewBuilder
    var widgetSections: some View {
        // The widget-look block is composed by the Widgets tab instead: its controls live in the
        // app-only `SettingsWindowView`, and this pane also compiles into the test target.
        SettingsCard(Text("Dock Items")) {
            List {
                ForEach(store.widgetLayout.order, id: \.self) { widget in
                    widgetRow(widget)
                        .listRowInsets(EdgeInsets())
                }
                .onMove { store.setWidgetLayout(store.widgetLayout.moving(from: $0, to: $1)) }
            }
            .listStyle(.plain)
            // Close-out F1 (2026-10-15): the list is a control inside a card, so it may not paint its
            // own well (luminance 35 across 816 × 186 pt against the card's 42) and its rows may not
            // sit off the grid (label ink at 50.5 pt against the page's 42, 38 pt pitch against 41).
            // The reorder itself (`.onMove` above) stays — it is the reason this is still a `List`.
            .scrollContentBackground(.hidden)
            // A `List` lays its rows out in an `NSOutlineView`, which reserves 8 pt of leading
            // indentation that `.listRowInsets` cannot reach (measured on the running app: the row
            // labels at 50 pt against the page's 42) — the list is pulled back by that much.
            .padding(.horizontal, -Self.listRowChromeInset)
            .frame(height: Self.widgetListHeight(count: store.widgetLayout.order.count))
            // The preset row and the switch that arms the context presets are one line (2026-10-18):
            // two lines of controls were 21 pt this page did not have. The context rows it opens stay
            // under it.
            HStack(spacing: SettingsMetrics.controlSpacing) {
                presetControls
                Spacer(minLength: SettingsMetrics.controlSpacing)
                contextPresetsToggle
            }
            contextPresetRows
            // Phase 32b's dock motion, moved here from the widget-look block (2026-10-20): it is
            // how the dock widgets move, so it belongs with the dock's own list.
            SettingsDivider()
            SettingsRow(Text("Dock Motion")) {
                Picker("Dock Motion", selection: $dockMotion) {
                    ForEach(WidgetMotionPreset.allCases, id: \.self) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            .help(Text("How the dock widgets' readings move when they change."))
            // The menu-bar menu's four switches moved here (2026-10-21).
            SettingsDivider()
            SettingsToggleRow(Text("Control Centre on the right"), isOn: Binding(
                get: { store.controlCentreTrailing },
                set: { store.setControlCentreTrailing($0) }
            ))
            SettingsDivider()
            SettingsToggleRow(Text("Show Shelf"), isOn: Binding(
                get: { store.showShelf },
                set: { store.setShowShelf($0) }
            ))
            SettingsDivider()
            SettingsToggleRow(Text("Show Trash"), isOn: Binding(
                get: { store.showTrash },
                set: { store.setShowTrash($0) }
            ))
            SettingsDivider()
            SettingsToggleRow(Text("Show app name on hover"), isOn: Binding(
                get: { store.hoverStyle.isExpressive },
                set: { store.setHoverStyle($0 ? .standard : .quiet) }
            ))
            SettingsDivider()
            SettingsToggleRow(Text("Keep windows above the taskbar"), isOn: Binding(
                get: { store.windowLiftEnabled },
                set: { store.setWindowLiftEnabled($0) }
            ))
        }

        // The style presets moved to `WidgetLookSettingsBlock` (2026-10-15): they are appearance, and
        // keeping them here made the page four sections where `Docs/SETTINGS.md` rule 5 allows three.
        // Same keys, same controls.
    }

    func widgetLabel(_ widget: BarSection) -> Text {
        switch widget {
        case .weather: return Text("Weather")
        case .media: return Text("Now Playing")
        case .launcher: return Text("Launcher")
        case .apps: return Text("Apps")
        case .widgets: return Text("Widgets")
        case .clock: return Text("Clock")
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

    /// One reorderable row: name, S/M/L (sizable widgets only), show/hide (never for Apps).
    func widgetRow(_ widget: BarSection) -> some View {
        let instance = store.widgetLayout.instance(for: widget)
        return HStack(spacing: 10) {
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
                    store.setWidgetLayout(store.widgetLayout.updating(widget) { $0.isVisible.toggle() })
                } label: {
                    Image(systemName: instance.isVisible ? "eye" : "eye.slash")
                }
                .buttonStyle(.borderless)
                .help(instance.isVisible ? Text("Hide") : Text("Show"))
            }
        }
        .frame(height: Self.widgetRowHeight)
    }
}
