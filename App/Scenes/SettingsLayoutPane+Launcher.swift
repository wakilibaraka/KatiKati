import SwiftUI

// The Launcher mode of `SettingsLayoutPane`; state lives in the main file.
extension SettingsLayoutPane {
    @ViewBuilder
    var launcherSections: some View {
            SettingsCard(Text("Launcher")) {
                SettingsRow(Text("Scroll Direction")) {
                    Picker("Scroll Direction", selection: Binding(
                        get: { store.launcherScrollDirection },
                        set: { store.setLauncherScrollDirection($0) }
                    )) {
                        Text("Sideways").tag(LauncherScrollDirection.horizontal)
                        Text("Down").tag(LauncherScrollDirection.vertical)
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                }
                // 57b: how the launcher takes the screen. Fullscreen is the old behaviour and stays the default.
                SettingsRow(Text("Presentation")) {
                    Picker("Presentation", selection: Binding(
                        get: { store.launcherPresentation },
                        set: { store.setLauncherPresentation($0) }
                    )) {
                        Text("Fullscreen").tag(LauncherPresentation.fullscreen)
                        Text("Centred").tag(LauncherPresentation.centred)
                        Text("Popover").tag(LauncherPresentation.popover)
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                }
                // 57c: the orb that floats over other windows and opens the launcher on a click.
                SettingsToggleRow(Text("Floating Orb"), isOn: Binding(
                    get: { store.launcherOrbEnabled },
                    set: { store.setLauncherOrbEnabled($0) }
                ), note: Text("A small glass orb over your windows; click it to open the launcher, drag it anywhere."))
                // Two narrow rows, one line (`Docs/SETTINGS.md` rule 5): the count/button row and
                // the reset button were two lines, which with the rest of the page ran it 20 pt
                // past the window (measured live 2026-10-15).
                SettingsRowPair(
                    left: {
                        SettingsRow(Text("Hidden Apps")) {
                            Text(verbatim: "\(launcherHiddenCount)").foregroundStyle(.secondary)
                            Button("Show All Hidden Apps") { updateLauncherState { $0.hidden = [] } }
                                .disabled(launcherHiddenCount == 0)
                        }
                    },
                    right: {
                        SettingsButtonRow(Text("Reset App Order")) { updateLauncherState { $0.order = [] } }
                    }
                )
                DisclosureGroup("Hide Rarely Used Apps") {
                    HStack {
                        Button("Hide All Suggested") { updateLauncherState { $0.hidden = LauncherHidePresets.hidingAll($0.hidden) } }
                        Button("Restore Suggested") { updateLauncherState { $0.hidden = LauncherHidePresets.restoringAll($0.hidden) } }
                    }
                    SettingsGrid(LauncherHidePresets.entries, id: \.bundleID) { entry in
                        SettingsCheckboxRow(Text(verbatim: entry.name), isOn: Binding(
                            get: { launcherHiddenIDs.contains(entry.bundleID) },
                            set: { _ in updateLauncherState { $0.hidden = LauncherOrdering.toggleHidden($0.hidden, entry.bundleID) } }
                        ))
                    }
                }
                SettingsRowPair(
                    left: {
                        SettingsPickerRow(Text("Search Position"), selection: Binding(
                            get: { store.launcherSearchPosition },
                            set: { store.setLauncherSearchPosition($0) }
                        )) {
                            Text("Top").tag(LauncherSearchPosition.top)
                            Text("Bottom").tag(LauncherSearchPosition.bottom)
                            Text("Left").tag(LauncherSearchPosition.left)
                            Text("Right").tag(LauncherSearchPosition.right)
                        }
                    },
                    right: {
                        SettingsPickerRow(Text("Theme"), selection: Binding(
                            get: { store.launcherTheme },
                            set: { store.setLauncherTheme($0) }
                        )) {
                            Text("System").tag(LauncherTheme.system)
                            Text("Light").tag(LauncherTheme.light)
                            Text("Dark").tag(LauncherTheme.dark)
                            Text("Glass").tag(LauncherTheme.glass)
                            Text("Desktop Picture").tag(LauncherTheme.desktop)
                        }
                    }
                )
                SettingsDivider()
                SettingsRow(Text("Tint")) {
                    Picker("Tint", selection: Binding(get: { store.launcherTint }, set: { store.setLauncherTint($0) })) {
                        Text("None").tag(LauncherTint.none)
                        Text("Blue").tag(LauncherTint.blue)
                        Text("Purple").tag(LauncherTint.purple)
                        Text("Pink").tag(LauncherTint.pink)
                        Text("Orange").tag(LauncherTint.orange)
                        Text("Green").tag(LauncherTint.green)
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                SettingsRow(Text("Launcher Icon")) {
                    ForEach(LauncherIconStyle.allCases, id: \.self) { style in
                        Button { store.setLauncherIcon(style) } label: {
                            VStack(spacing: 4) {
                                LauncherIconView(style: style, size: 38)
                                iconName(style).font(.caption)
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: store.launcherIcon == style ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
    }

    /// Custom layout: one row per shown item, Left / Right / Hidden.
    func iconName(_ style: LauncherIconStyle) -> Text {
        switch style {
        case .liquidBento: return Text("Liquid Bento")
        case .visionMono: return Text("Vision Mono")
        case .starburstAperture: return Text("Starburst")
        case .glass: return Text("Glass")
        case .orbit: return Text("Orbit")
        case .tiles: return Text("Tiles")
        case .petal: return Text("Petal")
        case .themed: return Text("Themed")
        }
    }

    /// Edits the launcher's saved arrangement (hidden apps, custom order); the launcher re-reads it each time it opens.
    func updateLauncherState(_ edit: (inout LauncherState) -> Void) {
        let launcherStore = LauncherStore(url: LauncherStore.defaultURL)
        var state = launcherStore.load()
        edit(&state)
        try? launcherStore.save(state)
        launcherHiddenCount = state.hidden.count
        launcherHiddenIDs = Set(state.hidden)
    }
}
