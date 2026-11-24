import SwiftUI

// The Launcher mode of `SettingsLayoutPane`; state lives in the main file.
extension SettingsLayoutPane {
    @ViewBuilder
    var launcherSections: some View {
        SettingsCard(Text("Preset & Placement")) {
            SettingsRow(Text("Preset")) {
                HStack(spacing: 8) {
                    presetCard(.windowsStart, symbol: "square.grid.2x2.topleft.filled", title: Text("Windows Start"))
                    presetCard(.linuxMenu, symbol: "rectangle.split.2x1", title: Text("Linux Menu"))
                    presetCard(.drawer, symbol: "rectangle.bottomthird.inset.filled", title: Text("Drawer"))
                    presetCard(.centred, symbol: "macwindow", title: Text("Centered"))
                    presetCard(.fullscreen, symbol: "rectangle.inset.filled", title: Text("Fullscreen"))
                }
            }
            SettingsRowPair(
                left: {
                    SettingsPickerRow(Text("Anchor"), selection: prefsBinding(\.anchorMode)) {
                        Text("Above Launcher Icon").tag(LauncherAnchorMode.aboveIcon)
                        Text("Screen Center").tag(LauncherAnchorMode.screenCenter)
                        Text("Follow Mouse").tag(LauncherAnchorMode.followMouse)
                    }
                },
                right: {
                    SettingsToggleRow(Text("Floating Orb"), isOn: Binding(
                        get: { store.launcherOrbEnabled },
                        set: { store.setLauncherOrbEnabled($0) }
                    ), note: Text("A small glass orb over your windows; click it to open the launcher, drag it anywhere."))
                }
            )
            SettingsRow(Text("Launcher Icon")) {
                HStack(spacing: 6) {
                    ForEach(LauncherIconStyle.allCases, id: \.self) { style in
                        Button { store.setLauncherIcon(style) } label: {
                            VStack(spacing: 4) {
                                LauncherIconView(style: style, size: 36)
                                iconName(style).font(.caption)
                            }
                            .padding(5)
                            .background(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: store.launcherIcon == style ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        SettingsCard(Text("Grid, Sections & Footer")) {
            SettingsRowPair(
                left: {
                    SettingsSegmentedRow(Text("Navigation"), selection: Binding(
                        get: { store.launcherScrollDirection },
                        set: { store.setLauncherScrollDirection($0) }
                    )) {
                        Text("Vertical Scroll").tag(LauncherScrollDirection.vertical)
                        Text("Paged Dots").tag(LauncherScrollDirection.horizontal)
                    }
                },
                right: {
                    SettingsSegmentedRow(Text("View Mode"), selection: prefsBinding(\.viewMode)) {
                        Text("Grid").tag(LauncherViewMode.grid)
                        Text("List").tag(LauncherViewMode.list)
                    }
                }
            )
            SettingsRowPair(
                left: {
                    SettingsPickerRow(Text("Density"), selection: prefsBinding(\.density)) {
                        Text("Compact").tag(LauncherDensity.compact)
                        Text("Standard").tag(LauncherDensity.standard)
                        Text("Spacious").tag(LauncherDensity.spacious)
                    }
                },
                right: {
                    SettingsPickerRow(Text("Columns"), selection: prefsBinding(\.columns)) {
                        Text("Auto").tag(0)
                        ForEach(LauncherPrefs.columnRange, id: \.self) { Text(verbatim: "\($0)").tag($0) }
                    }
                }
            )
            SettingsSliderRow(Text("Icon Size"), value: launcherPrefs.iconScale, range: LauncherPrefs.iconScaleRange, step: 0.05,
                              valueText: "\(Int((launcherPrefs.iconScale * 100).rounded()))%") {
                launcherPrefs.iconScale = $0; launcherPrefs.save()
            }
            SettingsRowPair(
                left: {
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
                },
                right: {
                    SettingsPickerRow(Text("Tint"), selection: Binding(
                        get: { store.launcherTint },
                        set: { store.setLauncherTint($0) }
                    )) {
                        Text("None").tag(LauncherTint.none)
                        Text("Blue").tag(LauncherTint.blue)
                        Text("Purple").tag(LauncherTint.purple)
                        Text("Pink").tag(LauncherTint.pink)
                        Text("Orange").tag(LauncherTint.orange)
                        Text("Green").tag(LauncherTint.green)
                    }
                }
            )
            SettingsDivider()
            SettingsGrid(LauncherToggleOption.allCases, id: \.self) { option in
                SettingsCheckboxRow(option.label, isOn: toggleBinding(for: option))
            }
        }

        SettingsCard(Text("Search & Curation")) {
            SettingsGrid(LauncherScopeOption.allCases, id: \.self) { scope in
                SettingsCheckboxRow(scope.label, isOn: scopeBinding(for: scope))
            }
            LauncherDockGroupSyncRow()
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
            DisclosureGroup("Hidden Apps Manager") {
                HStack {
                    Button("Hide Clutter & Helpers") {
                        Task { @MainActor in
                            let scanned = await Task.detached(priority: .utility) { LauncherIndexer.scanDirectories() }.value
                            updateLauncherState {
                                let withPresets = LauncherHidePresets.hidingAll($0.hidden)
                                $0.hidden = LauncherClutterFilter.hidingClutter(withPresets, apps: scanned)
                            }
                        }
                    }
                    Button("Restore Suggested") { updateLauncherState { $0.hidden = LauncherHidePresets.restoringAll($0.hidden) } }
                }
                SettingsGrid(LauncherHidePresets.entries, id: \.bundleID) { entry in
                    SettingsCheckboxRow(Text(verbatim: entry.name), isOn: Binding(
                        get: { launcherHiddenIDs.contains(entry.bundleID) },
                        set: { _ in updateLauncherState { $0.hidden = LauncherOrdering.toggleHidden($0.hidden, entry.bundleID) } }
                    ))
                }
            }
        }
    }

    private func presetCard(_ preset: LauncherPresentation, symbol: String, title: Text) -> some View {
        let selected = store.launcherPresentation == preset
        return Button { store.setLauncherPresentation(preset) } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(selected ? .accentColor : .secondary)
                title.font(.system(size: 11, weight: selected ? .semibold : .regular)).lineLimit(1)
            }
            .frame(width: 92, height: 50)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    private func prefsBinding<T>(_ keyPath: WritableKeyPath<LauncherPrefs, T>) -> Binding<T> {
        Binding(
            get: { launcherPrefs[keyPath: keyPath] },
            set: { launcherPrefs[keyPath: keyPath] = $0; launcherPrefs.save() }
        )
    }

    private func toggleBinding(for option: LauncherToggleOption) -> Binding<Bool> {
        switch option {
        case .pinned: return Binding(get: { store.launcherPinnedRow }, set: { store.setLauncherPinnedRow($0) })
        case .recommended: return prefsBinding(\.showRecommended)
        case .categorySidebar: return prefsBinding(\.showCategorySidebar)
        case .runningDots: return prefsBinding(\.showRunningDot)
        case .quickPlaces: return prefsBinding(\.showQuickPlaces)
        case .powerControls: return prefsBinding(\.showPowerControls)
        case .footerTelemetry: return prefsBinding(\.showFooterTelemetry)
        }
    }

    private func scopeBinding(for scope: LauncherScopeOption) -> Binding<Bool> {
        switch scope {
        case .apps: return prefsBinding(\.searchScope.apps)
        case .appGroups: return prefsBinding(\.searchScope.appGroups)
        case .recentFiles: return prefsBinding(\.searchScope.recentFiles)
        case .systemActions: return prefsBinding(\.searchScope.systemActions)
        }
    }

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

    func updateLauncherState(_ edit: (inout LauncherState) -> Void) {
        let launcherStore = LauncherStore(url: LauncherStore.defaultURL)
        var state = launcherStore.load()
        edit(&state)
        try? launcherStore.save(state)
        launcherHiddenCount = state.hidden.count
        launcherHiddenIDs = Set(state.hidden)
    }
}

private enum LauncherToggleOption: CaseIterable {
    case pinned, recommended, categorySidebar, runningDots, quickPlaces, powerControls, footerTelemetry

    var label: Text {
        switch self {
        case .pinned: return Text("Pinned Row")
        case .recommended: return Text("Recommended / Recent")
        case .categorySidebar: return Text("Category Sidebar")
        case .runningDots: return Text("Show Running Apps")
        case .quickPlaces: return Text("Quick Places")
        case .powerControls: return Text("Power Controls")
        case .footerTelemetry: return Text("Footer Telemetry Strip")
        }
    }
}

private enum LauncherScopeOption: CaseIterable {
    case apps, appGroups, recentFiles, systemActions

    var label: Text {
        switch self {
        case .apps: return Text("Apps")
        case .appGroups: return Text("App Groups")
        case .recentFiles: return Text("Recent Files")
        case .systemActions: return Text("System Actions")
        }
    }
}

private struct LauncherDockGroupSyncRow: View {
    @ObservedObject private var groupStore = DockAppGroupStore.shared

    var body: some View {
        SettingsToggleRow(
            Text("Sync Folders with Dock App Groups"),
            isOn: Binding(
                get: { groupStore.syncWithLauncherFolders },
                set: { groupStore.setSyncWithLauncher($0) }
            )
        )
    }
}
