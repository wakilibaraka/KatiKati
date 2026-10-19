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
            note: Text("Slim bars on the screen edges for notes, productivity and system status. Pick a layout, flip it to either side, or choose Custom to place each item yourself.")
        ) {
            SettingsPickerRow(Text("Edge Bars"), selection: Binding(
                get: { store.edgeBarPreset },
                set: { store.setEdgeBarPreset($0) }
            )) {
                ForEach(EdgeBarPreset.allCases, id: \.self) { Self.presetTitle($0).tag($0) }
            }
            SettingsDivider()
            SettingsRowPair(
                left: {
                    // Phase 18g/18h: what an edge bar does when the dock rail takes its side.
                    SettingsSegmentedRow(Text("Edge Bar on the Dock's Side"), selection: Binding(
                        get: { store.edgeConflictPolicy },
                        set: { store.setEdgeConflictPolicy($0) }
                    )) {
                        Text("Move Across").tag(EdgeConflictPolicy.moveAcross)
                        Text("Hide").tag(EdgeConflictPolicy.hide)
                    }
                    .disabled(store.stripPlacementMap.global == .bottom)
                },
                right: {
                    SettingsSegmentedRow(Text("Main Side"), selection: Binding(
                        get: { store.edgePrimarySide },
                        set: { store.setEdgePrimarySide($0) }
                    )) {
                        Text("Left").tag(EdgeSide.left)
                        Text("Right").tag(EdgeSide.right)
                    }
                    .disabled(store.edgeBarPreset == .off || store.edgeBarPreset == .custom)
                }
            )
            SettingsDivider()
            SettingsToggleRow(Text("Keep Edge Bars Open"), isOn: Binding(
                get: { store.deckKeepOpen },
                set: { store.setDeckKeepOpen($0) }
            ))
            .disabled(store.edgeBarPreset == .off)
        }

        // Custom places every item itself; a preset carries a fixed set of tiles. Either way the
        // list is a grid, and the card is absent while the bars are off.
        if store.edgeBarPreset == .custom {
            // Collapsed by default (2026-10-18): this list is one row per item and ran the page 275 pt
            // past the window with Custom chosen (measured live), which is rule 5's "longer than the
            // page can show" case — the disclosure is the page's affordance, the way the Shortcuts
            // assignments use one. Every item and its three-way picker stays.
            SettingsCard {
                DisclosureGroup(isExpanded: $showsEdgeItems) {
                    SettingsGrid(EdgeItem.allCases.filter { $0.isBuilt() }, id: \.self) { item in
                        SettingsRow(Self.itemTitle(item)) {
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
                } label: {
                    Text("Widgets").font(.headline)
                }
            }
        } else if store.edgeBarPreset != .off {
            SettingsCard(Text("Widgets")) {
                SettingsGrid(WidgetTile.allCases, id: \.self) { tile in
                    SettingsCheckboxRow(
                        Self.itemTitle(EdgeItem.allCases.first { $0.widget == tile } ?? .weather),
                        isOn: Binding(
                            get: { store.widgetTiles.contains(tile) },
                            set: { store.setWidgetTile(tile, enabled: $0) }
                        )
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

    /// Look and behaviour of the deck itself (7A-D6). The sliders keep the card's full width — a
    /// track in half a card is unusable — and the narrow rows (switches, menus, segmented pickers)
    /// sit two to a line, which is what pulls this page back inside the window (`Docs/SETTINGS.md`
    /// rule 5). Same keys, same controls as before; only the arrangement changed.
    var deckControls: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach([EdgeSide.left, EdgeSide.right], id: \.self) { side in
                SettingsSliderRow(
                    side == .left ? Text("Left Bar Size") : Text("Right Bar Size"),
                    value: store.deckScale(for: side),
                    range: DeckSettingsRules.scaleRange,
                    step: 0.05,
                    valueText: "\(Int((store.deckScale(for: side) * 100).rounded()))%",
                    set: { store.setDeckScale($0, for: side) }
                )
            }
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
            ForEach([EdgeSide.left, EdgeSide.right], id: \.self) { side in
                SettingsSliderRow(
                    side == .left ? Text("Left Bar Height") : Text("Right Bar Height"),
                    value: 1 - store.deckYRatio(for: side),
                    range: 0...1,
                    step: 0.01,
                    valueText: "\(Int(((1 - store.deckYRatio(for: side)) * 100).rounded()))%",
                    set: { store.setDeckYRatio(1 - $0, for: side) }
                )
            }
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
                }.labelsHidden().pickerStyle(.segmented).fixedSize()
            }
            SettingsRowPair {
                SettingsRow(Text("Button Icons")) {
                    Picker("Button Icons", selection: edgePrefBinding(\.iconSet)) {
                        Text("Classic").tag(EdgeIconSet.classic)
                        Text("Modern").tag(EdgeIconSet.modern)
                        Text("Realistic").tag(EdgeIconSet.realistic)
                    }.labelsHidden().pickerStyle(.segmented).fixedSize()
                    .disabled(store.edgePrefs.barStyle == .liquidGlass)
                }
            } right: {
                SettingsRow(Text("Flyout Style")) {
                    Picker("Flyout Style", selection: edgePrefBinding(\.flyoutStyle)) {
                        Text("Modern").tag(EdgeFlyoutStyle.modern)
                        Text("Glass").tag(EdgeFlyoutStyle.glass)
                    }.labelsHidden().pickerStyle(.segmented).fixedSize()
                    .disabled(store.edgePrefs.barStyle == .liquidGlass)
                }
            }
            SettingsRowPair {
                SettingsRow(Text("Button Style")) {
                    Picker("Button Style", selection: Binding(get: { store.edgeTileStyle }, set: { store.setEdgeTileStyle($0) })) {
                        Text("Glass").tag(EdgeTileStyle.glass)
                        Text("Coloured").tag(EdgeTileStyle.coloured)
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                    .disabled(store.edgePrefs.barStyle == .liquidGlass)
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
