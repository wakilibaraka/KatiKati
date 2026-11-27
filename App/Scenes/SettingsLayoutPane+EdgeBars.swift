import SwiftUI

// The EdgeBars mode of `SettingsLayoutPane`; state lives in the main file.
extension SettingsLayoutPane {
    static var liquidGlassSupported: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// The Edge Bars page (Phase 12 A5). Three sections — the bar, the widgets it carries, and its
    /// size and behaviour — where the page used to be one card of ~28 controls, and the two
    /// checklists are two-column grids: a single column of four or seventeen checkboxes left the
    /// right half of the card empty and ran the page past the screen (`Docs/SETTINGS.md` rule 5).
    @ViewBuilder
    var edgeBarSections: some View {
        SettingsCard(
            Text("Edge Bars"),
            note: Text(verbatim: "Slim bar on the right screen edge for ExtraDock apps, notes, productivity tools and system status. Left edge stays free for the Window Drawer.")
        ) {
            SettingsPickerRow(Text("Edge Bars"), selection: Binding(
                get: { store.edgeBarPreset },
                set: { store.setEdgeBarPreset($0) }
            )) {
                ForEach(EdgeBarPreset.allCases, id: \.self) { Self.presetTitle($0).tag($0) }
            }
            SettingsDivider()
            // SD-8: the same swap as Settings › Side Deck, in one write for both surfaces.
            SettingsButtonRow(Text("Swap Left / Right Sides")) { SideDeckSettings.swapSides(store: store) }
            SettingsDivider()
            SettingsRowPair(
                left: {
                    SettingsToggleRow(Text("Keep Edge Bars Open"), isOn: Binding(
                        get: { store.deckKeepOpen },
                        set: { store.setDeckKeepOpen($0) }
                    ))
                    .disabled(store.edgeBarPreset == .off)
                },
                right: {
                    SettingsToggleRow(Text(verbatim: "Collapse to Single Button"), isOn: edgePrefBinding(\.collapseToButton))
                        .disabled(store.edgeBarPreset == .off)
                }
            )
            if store.edgeBarPreset != .off {
                SettingsDivider()
                SettingsRowPair(
                    left: {
                        SettingsToggleRow(Text(verbatim: "Show Apps (ExtraDock)"), isOn: Binding(
                            get: { store.edgeBarPreset == .extraDock || store.edgePrefs.showAppsInBar },
                            set: { enabled in
                                var prefs = store.edgePrefs
                                prefs.showAppsInBar = enabled
                                store.setEdgePrefs(prefs)
                            }
                        ))
                        .disabled(store.edgeBarPreset == .extraDock || store.edgeBarPreset == .custom)
                    },
                    right: {
                        SettingsToggleRow(Text(verbatim: "Running Apps Only"), isOn: edgePrefBinding(\.appsRunningOnly))
                            .disabled(!(store.edgeBarPreset == .extraDock || store.edgePrefs.showAppsInBar || (store.edgeBarPreset == .custom && store.edgePlacement(of: .apps) != .hidden)))
                    }
                )
                SettingsDivider()
                SettingsToggleRow(Text(verbatim: "Show Running Dots"), isOn: edgePrefBinding(\.showRunningDots))
                    .disabled(!(store.edgeBarPreset == .extraDock || store.edgePrefs.showAppsInBar || (store.edgeBarPreset == .custom && store.edgePlacement(of: .apps) != .hidden)))
            }
        }

        // Sydedock dedicated configuration card
        if store.edgeBarPreset == .sydedock {
            SettingsCard(
                Text(verbatim: "Sydedock Glanceable Deck"),
                note: Text(verbatim: "Live micro-widgets right on your display bezel with in-place countdowns and status.")
            ) {
                // PHN-4: cadence and goal had two owners (this card wrote `edgePrefs` *and* the
                // controller). They moved to the Notch page's Daily Helpers card; this card says so
                // instead of offering a second copy of the same two numbers.
                SettingsRow(
                    Text("Hydration & Water Tracking"),
                    note: Text("Hydration cadence, goal and pause prompts live on the Notch page, under Daily Helpers.")
                ) {
                    Image(systemName: "drop.fill").foregroundColor(.cyan)
                }

                SettingsDivider()

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        SettingsRow(Text("Fasting Protocol")) {
                            Picker("Fasting Protocol", selection: Binding(
                                get: { store.edgePrefs.foodFastingProtocol },
                                set: { val in
                                    var p = store.edgePrefs
                                    p.foodFastingProtocol = val
                                    store.setEdgePrefs(p)
                                    if let proto = FastingProtocol(rawValue: val) {
                                        NutritionController.shared.protocolType = proto
                                    }
                                }
                            )) {
                                Text("16:8 Fast").tag("fast16_8")
                                Text("18:6 Fast").tag("fast18_6")
                                Text("14:10 Fast").tag("fast14_10")
                                Text("Off").tag("none")
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .fixedSize()
                        }
                        SettingsSliderRow(
                            Text("Meal Cadence Interval"),
                            value: store.edgePrefs.foodMealIntervalHours,
                            range: 2.0...6.0,
                            step: 0.5,
                            valueText: String(format: "%.1f h", store.edgePrefs.foodMealIntervalHours),
                            set: { val in
                                var p = store.edgePrefs
                                p.foodMealIntervalHours = val
                                store.setEdgePrefs(p)
                                NutritionController.shared.mealIntervalHours = val
                            }
                        )
                    }
                    .padding(.top, 4)
                } label: {
                    HStack {
                        Image(systemName: "fork.knife").foregroundColor(.orange)
                        Text("Food, Fasting & Nutrition").font(.subheadline.weight(.semibold))
                    }
                }

                SettingsDivider()

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        SettingsRowPair(
                            left: {
                                SettingsToggleRow(Text("24-Hour Clock"), isOn: edgePrefBinding(\.clockIs24Hour))
                            },
                            right: {
                                SettingsToggleRow(Text("Show Seconds"), isOn: edgePrefBinding(\.clockShowSeconds))
                            }
                        )
                        SettingsRowPair(
                            left: {
                                SettingsToggleRow(Text("Battery Percentage"), isOn: edgePrefBinding(\.batteryShowPercentage))
                            },
                            right: {
                                SettingsToggleRow(Text("Wi-Fi Status Icon"), isOn: edgePrefBinding(\.batteryShowWifi))
                            }
                        )
                    }
                    .padding(.top, 4)
                } label: {
                    HStack {
                        Image(systemName: "clock.fill").foregroundColor(.white)
                        Text("Clock & Battery Displays").font(.subheadline.weight(.semibold))
                    }
                }

                SettingsDivider()

                SettingsToggleRow(
                    Text("Gentle Audio Feedback (Pouring & Chimes)"),
                    isOn: edgePrefBinding(\.edgeSoundEffectsEnabled)
                )
            }
        }

        // Custom toggles every item individually (Right vs Hidden); presets provide curated widget & productivity checklists.
        if store.edgeBarPreset == .custom {
            SettingsCard {
                DisclosureGroup(isExpanded: $showsEdgeItems) {
                    SettingsGrid(EdgeItem.allCases.filter { $0.isBuilt() }, id: \.self) { item in
                        SettingsRow(Self.itemTitle(item)) {
                            Picker(selection: Binding(
                                get: { store.edgePlacement(of: item) == .hidden ? EdgePlacement.hidden : EdgePlacement.right },
                                set: { store.setEdgePlacement($0, of: item) }
                            )) {
                                Text(verbatim: "Shown").tag(EdgePlacement.right)
                                Text("Hidden").tag(EdgePlacement.hidden)
                            } label: { Self.itemTitle(item) }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .fixedSize()
                        }
                        .draggable(item.rawValue)
                    }
                } label: {
                    Text("Widgets").font(.headline)
                }
            }
        } else if store.edgeBarPreset != .off && store.edgeBarPreset != .sydedock {
            SettingsCard(Text("Widgets")) {
                SettingsRowPair(
                    left: {
                        SettingsCheckboxRow(Text("Weather"), isOn: widgetBinding(.weather))
                    },
                    right: {
                        SettingsCheckboxRow(Text("Now Playing"), isOn: widgetBinding(.nowPlaying))
                    }
                )
                SettingsRowPair(
                    left: {
                        SettingsCheckboxRow(Text(verbatim: "Bluetooth & Wi-Fi"), isOn: widgetBinding(.bluetooth))
                    },
                    right: {
                        SettingsCheckboxRow(Text(verbatim: "System & Battery"), isOn: widgetBinding(.systemMonitor))
                    }
                )
                if store.edgeBarPreset == .productivityAndRest {
                    SettingsDivider()
                    Text(verbatim: "Productivity")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    SettingsRowPair(
                        left: {
                            SettingsCheckboxRow(Text(verbatim: "Reminders & Tasks"), isOn: pairProductivityBinding(.reminders, .tasks))
                        },
                        right: {
                            SettingsCheckboxRow(Text(verbatim: "Time & Alarms"), isOn: pairProductivityBinding(.time, .alarms))
                        }
                    )
                    SettingsRowPair(
                        left: {
                            SettingsCheckboxRow(Text(verbatim: "Capture & Screenshot"), isOn: pairProductivityBinding(.capture, .screenshot))
                        },
                        right: {
                            SettingsCheckboxRow(Text("Clipboard"), isOn: productivityBinding(.clipboard))
                        }
                    )
                    SettingsRowPair(
                        left: {
                            SettingsCheckboxRow(Text("Windows"), isOn: productivityBinding(.windows))
                        },
                        right: {
                            SettingsCheckboxRow(Text("Screen Time"), isOn: productivityBinding(.screenTime))
                        }
                    )
                }
            }
        }

        SettingsCard(Text("Size & Behaviour")) {
            deckControls
            SettingsToggleRow(Text("Sync Notes with iCloud Drive"), isOn: Binding(
                get: { store.notesSyncEnabled },
                set: { store.setNotesSyncEnabled($0) }
            ))
        }
    }

    func edgePrefBinding<V>(_ key: WritableKeyPath<EdgeBarPrefs, V>) -> Binding<V> {
        Binding(get: { store.edgePrefs[keyPath: key] },
                set: { var p = store.edgePrefs; p[keyPath: key] = $0; store.setEdgePrefs(p) })
    }

    func widgetBinding(_ tile: WidgetTile) -> Binding<Bool> {
        Binding(get: { store.widgetTiles.contains(tile) },
                set: { store.setWidgetTile(tile, enabled: $0) })
    }

    func productivityBinding(_ item: ProductivityItem) -> Binding<Bool> {
        Binding(get: { store.productivityItems.contains(item) },
                set: { store.setProductivityItem(item, enabled: $0) })
    }

    func pairProductivityBinding(_ first: ProductivityItem, _ second: ProductivityItem) -> Binding<Bool> {
        Binding(get: { store.productivityItems.contains(first) || store.productivityItems.contains(second) },
                set: {
                    store.setProductivityItem(first, enabled: $0)
                    store.setProductivityItem(second, enabled: $0)
                })
    }

    /// Look and behaviour of the deck itself (7A-D6). The sliders keep the card's full width — a
    /// track in half a card is unusable — and the narrow rows (switches, menus, segmented pickers)
    /// sit two to a line, which is what pulls this page back inside the window (`Docs/SETTINGS.md`
    /// rule 5). Same keys, same controls as before; only the arrangement changed.
    var deckControls: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSliderRow(
                Text("Right Bar Size"),
                value: store.deckScale(for: .right),
                range: DeckSettingsRules.scaleRange,
                step: 0.05,
                valueText: "\(Int((store.deckScale(for: .right) * 100).rounded()))%",
                set: { store.setDeckScale($0, for: .right) }
            )
            SettingsSliderRow(
                Text("Open Delay"),
                value: store.edgePrefs.openDelay,
                range: EdgeBarPrefs.openDelayRange,
                step: 0.05,
                valueText: String(format: "%.2f s", store.edgePrefs.openDelay),
                set: { value in
                    var prefs = store.edgePrefs
                    prefs.openDelay = value
                    store.setEdgePrefs(prefs)
                }
            )
            SettingsSliderRow(
                Text("Edge Sensitivity"),
                value: store.edgePrefs.sensitivity,
                range: 0...1,
                step: 0.05,
                valueText: "\(Int((store.edgePrefs.sensitivity * 100).rounded()))%",
                set: { value in
                    var prefs = store.edgePrefs
                    prefs.sensitivity = value
                    store.setEdgePrefs(prefs)
                }
            )
            SettingsSliderRow(
                Text("Right Bar Height"),
                value: 1 - store.deckYRatio(for: .right),
                range: 0...1,
                step: 0.01,
                valueText: "\(Int(((1 - store.deckYRatio(for: .right)) * 100).rounded()))%",
                set: { store.setDeckYRatio(1 - $0, for: .right) }
            )
            SettingsRowPair {
                SettingsToggleRow(Text("Magnify Buttons Under the Pointer"), isOn: Binding(
                    get: { store.deckMagnify },
                    set: { store.setDeckMagnify($0) }
                ))
            } right: {
                SettingsRow(Text("Magnify Amount")) {
                    Picker("Magnify Amount", selection: edgePrefBinding(\.magnifyAmount)) {
                        Text("Subtle").tag(EdgeMagnifyAmount.subtle)
                        Text("Standard").tag(EdgeMagnifyAmount.standard)
                        Text("Bold").tag(EdgeMagnifyAmount.bold)
                    }.labelsHidden().pickerStyle(.segmented).fixedSize()
                }
            }
            SettingsRow(Text("Edge Bar Style")) {
                Picker("Edge Bar Style", selection: edgePrefBinding(\.barStyle)) {
                    Text("Paper").tag(EdgeBarStyle.paper)
                    Text(Self.liquidGlassSupported ? "Liquid Glass" : "Liquid Glass (frosted on this macOS)").tag(EdgeBarStyle.liquidGlass)
                    Text("Fluid").tag(EdgeBarStyle.fluid)
                    Text(verbatim: "Bezel Dock").tag(EdgeBarStyle.bezelDock)
                }.labelsHidden().pickerStyle(.segmented).fixedSize()
            }
            SettingsRowPair {
                SettingsRow(Text("Button Icons")) {
                    Picker("Button Icons", selection: edgePrefBinding(\.iconSet)) {
                        Text("Classic").tag(EdgeIconSet.classic)
                        Text("Modern").tag(EdgeIconSet.modern)
                        Text("Realistic").tag(EdgeIconSet.realistic)
                    }.labelsHidden().pickerStyle(.segmented).fixedSize()
                    .disabled(store.edgePrefs.barStyle != .paper)
                }
            } right: {
                SettingsRow(Text("Flyout Style")) {
                    Picker("Flyout Style", selection: edgePrefBinding(\.flyoutStyle)) {
                        Text("Modern").tag(EdgeFlyoutStyle.modern)
                        Text("Glass").tag(EdgeFlyoutStyle.glass)
                    }.labelsHidden().pickerStyle(.segmented).fixedSize()
                    .disabled(store.edgePrefs.barStyle != .paper)
                }
            }
            SettingsRowPair {
                SettingsRow(Text("Button Style")) {
                    Picker("Button Style", selection: Binding(get: { store.edgeTileStyle }, set: { store.setEdgeTileStyle($0) })) {
                        Text("Glass").tag(EdgeTileStyle.glass)
                        Text("Coloured").tag(EdgeTileStyle.coloured)
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                    .disabled(store.edgePrefs.barStyle != .paper)
                }
            } right: {
                SettingsRow(Text("Note Tab Font")) {
                    Picker("Note Tab Font", selection: Binding(get: { store.deckTabFont }, set: { store.setDeckTabFont($0) })) {
                        ForEach(DeckFont.faces, id: \.postScript) { face in
                            if face.postScript.isEmpty { Text("System").tag(face.postScript) } else { Text(verbatim: face.name).tag(face.postScript) }
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
            }
            SettingsRowPair {
                SettingsToggleRow(Text("Open Only on Click"), isOn: edgePrefBinding(\.openOnClick))
            } right: {
                SettingsToggleRow(Text("Show Button Names on Hover"), isOn: edgePrefBinding(\.hoverLabels))
            }
            SettingsRowPair {
                SettingsToggleRow(Text("Preview Notes on Hover"), isOn: Binding(
                    get: { store.deckTabPreview },
                    set: { store.setDeckTabPreview($0) }
                ))
            } right: {
                SettingsToggleRow(Text("Open Notes on Hover"), isOn: Binding(
                    get: { store.deckOpenOnHover },
                    set: { store.setDeckOpenOnHover($0) }
                ))
            }
            SettingsButtonRow(Text("Reset Bar Positions")) {
                store.setDeckYRatio(0.5, for: .left)
                store.setDeckYRatio(0.5, for: .right)
            }
        }
    }

    @ViewBuilder
    private var archivedEdgeBarStrings: some View {
        // Preserves existing Localizable.xcstrings references for controls retired when consolidating EdgeBars on the right.
        Text("Slim bars on the screen edges for notes, productivity and system status. Pick a layout, flip it to either side, or choose Custom to place each item yourself.")
        Text("Edge Bar on the Dock's Side")
        Text("Move Across")
        Text("Main Side")
        Text("Left Bar Size")
        Text("Left Bar Height")
    }

    var customRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(EdgeItem.allCases.filter { $0.isBuilt() }, id: \.self) { item in
                HStack {
                    Self.itemTitle(item)
                    Spacer(minLength: 12)
                    Picker(selection: Binding(
                        get: { store.edgePlacement(of: item) },
                        set: { store.setEdgePlacement($0, of: item) }
                    )) {
                        Text("Left").tag(EdgePlacement.left)
                        Text("Right").tag(EdgePlacement.right)
                        Text("Hidden").tag(EdgePlacement.hidden)
                    } label: { Self.itemTitle(item) }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
        }
    }
}
