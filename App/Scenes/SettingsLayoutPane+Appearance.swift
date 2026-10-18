import SwiftUI

// The Appearance mode of `SettingsLayoutPane`; state lives in the main file.
extension SettingsLayoutPane {
    @ViewBuilder
    var geometrySections: some View {
        let inputs = store.layoutThumbnailInputs
            // Preview, Layout Mode, Size and Fine-tune are one card (2026-10-15): the page has to fit
            // the window, and each extra card cost its own header, padding and section gap — 78 pt
            // each, 156 of them here. Every control and every divider is unchanged.
            SettingsCard(Text("Layout Mode")) {
                LayoutModeThumbnail(mode: store.barLayoutMode, inputs: inputs, highlighted: true,
                                    minimumIslandHeight: 3, visibleBottomFraction: Self.previewFraction)
                    // Fixed height (≈ the cropped ratio at the pane's 504pt content width): the
                    // window's height probe proposes no height, so `aspectRatio` would collapse.
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                LayoutModePicker(selection: store.barLayoutMode, inputs: inputs) { store.setBarLayoutMode($0) }
                // Fixed two-line box: the window is measured once per tab switch, so the
                // pane height must not change with the selected mode.
                LayoutModeDetail(mode: store.barLayoutMode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
                SettingsDivider()
                SettingsRowPair(
                    left: {
                        SettingsSegmentedRow(Text("Position"), selection: Binding(
                            get: { store.stripPlacementMap.global },
                            set: { store.setStripPlacement($0) }
                        )) {
                            Text("Bottom").tag(StripPlacement.bottom)
                            Text("Left").tag(StripPlacement.left)
                            Text("Right").tag(StripPlacement.right)
                        }
                    },
                    right: {
                        SettingsSegmentedRow(Text("Bar Height"), selection: Binding(
                            get: { DockSizeClass.nearest(to: store.dockPanelHeight.points) },
                            set: { store.setDockPanelHeight(DockPanelHeight(clamping: $0.barHeight)) }
                        )) {
                            Text("Small").tag(DockSizeClass.small)
                            Text("Medium").tag(DockSizeClass.medium)
                            Text("Large").tag(DockSizeClass.large)
                        }
                    }
                )
                SettingsDivider()
                SettingsSegmentedRow(Text("Spacing"), selection: Binding(
                    get: { DockSpacing.matching(gap: store.islandGap, margin: store.islandMargin) },
                    set: { if let spacing = $0 { store.setDockSpacing(spacing) } }
                )) {
                    Text("Compact").tag(DockSpacing?.some(.compact))
                    Text("Comfortable").tag(DockSpacing?.some(.comfortable))
                    Text("Airy").tag(DockSpacing?.some(.airy))
                }
                SettingsDivider()
                DisclosureGroup(isExpanded: $showsFineTune) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Exact values for power users. Bar height is capped at what still fits this screen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        SettingsSliderRow(Text("Bar Height"),
                                  value: store.dockPanelHeight.points,
                                  range: DockPanelHeight.minimum...fittingMaximumBarHeight, step: 1) {
                            store.setDockPanelHeight(DockPanelHeight(clamping: $0))
                        }
                        SettingsSliderRow(Text("Gap Between Islands"), value: store.islandGap, range: 0.5...40, step: 0.5) {
                            store.setIslandGap($0)
                        }
                        SettingsSliderRow(Text("Side Margin"), value: store.islandMargin, range: 0...80, step: 1) {
                            store.setIslandMargin($0)
                        }
                        SettingsSliderRow(Text("Centered Width"), value: store.centeredWidth,
                                  range: AppSettingsStore.minimumCenteredWidth...AppSettingsStore.maximumCenteredWidth, step: 10) {
                            store.setCenteredWidth($0)
                        }
                        .disabled(store.barLayoutMode != .centered)
                        SettingsRow(Text("Bottom Edge")) {
                            Picker("Bottom Edge", selection: Binding(
                                get: { BottomEdgeChoice(gap: store.bottomGap) },
                                set: { choice in
                                    switch choice {
                                    case .floating: store.setBottomGap(PanelLayoutMetrics.floatingBottomGap)
                                    case .hugging: store.setBottomGap(PanelLayoutMetrics.huggingBottomGap)
                                    case .custom:
                                        if BottomEdgeChoice(gap: store.bottomGap) != .custom { store.setBottomGap(5) }
                                    }
                                }
                            )) {
                                Text("Floating").tag(BottomEdgeChoice.floating)
                                Text("Hugging").tag(BottomEdgeChoice.hugging)
                                Text("Custom").tag(BottomEdgeChoice.custom)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .fixedSize()
                        }
                        SettingsSliderRow(Text("Distance From Edge"), value: store.bottomGap,
                                  range: PanelLayoutMetrics.bottomGapRange, step: 1) {
                            store.setBottomGap($0)
                        }
                        Text("Floating keeps the bar 8 pt above the screen edge. Hugging sits it almost on the edge.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if NSScreen.screens.count > 1 {
                            Text("Displays").font(.subheadline.weight(.semibold)).padding(.top, 4)
                            ForEach(NSScreen.screens, id: \.self) { screen in
                                if let uuid = DisplayIdentity.uuidString(for: screen) {
                                    displayPlacementRow(name: screen.localizedName, uuid: uuid)
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Fine-tune").font(.headline)
                }
            }
    }

    @ViewBuilder
    var chipSections: some View {
            SettingsCard(Text("Window Chips")) {
                // The card's four paragraphs are the rows' own explanations now (rule 4): three of
                // them belonged to a switch that could not carry them, and the card rendered three
                // hand-rolled `Toggle`s beside their text instead of rows (rule 3).
                SettingsRow(
                    Text("Multiple Windows"),
                    info: String(localized: "A grouped app shows one chip with a window count; clicking it cycles the app's windows.")
                ) {
                    Picker("Multiple Windows", selection: Binding(
                        get: { store.chipGroupingPlan.defaultPolicy },
                        set: { store.setChipGroupingDefault($0) }
                    )) {
                        Text("One chip per window").tag(WindowChipGroupPolicy.separate)
                        Text("Group by app").tag(WindowChipGroupPolicy.grouped)
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                ForEach(store.chipGroupingPlan.overrides.keys.sorted(), id: \.self) { bundleID in
                    SettingsRow(Text(verbatim: Self.appName(forBundleID: bundleID))) {
                        HStack(spacing: SettingsMetrics.controlSpacing) {
                            Picker("Multiple Windows", selection: Binding(
                                get: { store.chipGroupingPlan.overrides[bundleID] ?? store.chipGroupingPlan.defaultPolicy },
                                set: { store.setChipGrouping($0, forBundleID: bundleID) }
                            )) {
                                Text("One chip per window").tag(WindowChipGroupPolicy.separate)
                                Text("Group by app").tag(WindowChipGroupPolicy.grouped)
                            }
                            .labelsHidden().pickerStyle(.menu).fixedSize()
                            Button("Remove") { store.setChipGrouping(nil, forBundleID: bundleID) }
                        }
                    }
                }
                Menu {
                    ForEach(Self.runningAppChoices(excluding: Set(store.chipGroupingPlan.overrides.keys)), id: \.bundleID) { app in
                        Button(app.name) {
                            let other: WindowChipGroupPolicy = store.chipGroupingPlan.defaultPolicy == .grouped ? .separate : .grouped
                            store.setChipGrouping(other, forBundleID: app.bundleID)
                        }
                    }
                } label: {
                    Text("Add App…")
                }
                .fixedSize()

                SettingsRowPair(
                    left: {
                        SettingsToggleRow(
                            Text("Show All Running Apps"),
                            isOn: Binding(
                                get: { store.showAllRunningApps },
                                set: { store.setShowAllRunningApps($0) }
                            ),
                            note: Text("Gives every running app a chip, even when it has no open window — like the system Dock.")
                        )
                    },
                    right: {
                        SettingsToggleRow(
                            Text("Hover Preview"),
                            isOn: Binding(
                                get: { store.chipPreviewEnabled },
                                set: { store.setChipPreviewEnabled($0) }
                            )
                        )
                    }
                )
                if store.chipPreviewEnabled {
                    SettingsDivider()
                    SettingsRowPair(
                        left: {
                            SettingsSegmentedRow(Text("Preview Delay"), selection: Binding(
                                get: { store.chipPreviewDelayMs },
                                set: { store.setChipPreviewDelayMs($0) }
                            )) {
                                Text("Fast").tag(150)
                                Text("Normal").tag(350)
                                Text("Slow").tag(600)
                            }
                        },
                        right: {
                            SettingsSegmentedRow(Text("Preview Size"), selection: Binding(
                                get: { store.chipPreviewThumbWidth },
                                set: { store.setChipPreviewThumbWidth($0) }
                            )) {
                                Text("Small").tag(140)
                                Text("Medium").tag(180)
                                Text("Large").tag(240)
                            }
                        }
                    )
                    if !CGPreflightScreenCaptureAccess() {
                        SettingsDivider()
                        SettingsButtonRow(
                            Text("Allow Screen Recording"),
                            note: Text("Window previews need Screen Recording permission. Without it, previews show titles only.")
                        ) { _ = CGRequestScreenCaptureAccess() }
                    }
                }
                SettingsDivider()
                SettingsToggleRow(
                    Text("Classic Right-Click Menu"),
                    isOn: Binding(
                        get: { store.chipClassicMenu },
                        set: { store.setChipClassicMenu($0) }
                    ),
                    info: String(localized: "Right-click a window chip for a floating jump list above the dock. Turn this on to use the system menu instead.")
                )
            }
    }

    /// Fine-tune's Bar Height cap on the dock's screen (never below the current value, so the
    /// slider can always show where the bar is).
    var fittingMaximumBarHeight: CGFloat {
        let cap = DockStyleFit.maximumBarHeight(
            mode: store.barLayoutMode, gap: store.islandGap, margin: store.islandMargin, bottomGap: store.bottomGap,
            screenWidth: dockScreenWidth, widgetOrder: store.widgetLayout.visibleOrder,
            range: DockPanelHeight.minimum...DockPanelHeight.maximum)
        return max(cap, store.dockPanelHeight.points, DockPanelHeight.minimum + 1)
    }

    /// One display's placement override; "Same as All Displays" clears it (Phase 18h, decision 5).
    func displayPlacementRow(name: String, uuid: String) -> some View {
        SettingsRow(Text(verbatim: name)) {
            Picker(selection: Binding<StripPlacement?>(
                get: { store.stripPlacementMap.perDisplay[uuid] },
                set: { store.setStripPlacement($0 ?? store.stripPlacementMap.global, forDisplay: uuid) }
            )) {
                Text("Same as All Displays").tag(StripPlacement?.none)
                Text("Bottom").tag(StripPlacement?.some(.bottom))
                Text("Left").tag(StripPlacement?.some(.left))
                Text("Right").tag(StripPlacement?.some(.right))
            } label: { Text(verbatim: name) }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}
