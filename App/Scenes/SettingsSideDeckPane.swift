import SwiftUI

/// SD-8: Settings › Side Deck — the shell's own preferences and the edge swap it shares with the Edge
/// Bar. Every control writes `SideDeckConfig`, so this pane, the resting handle and the panel cannot
/// disagree about the keys.
struct SettingsSideDeckPane: View {
    @ObservedObject var store: AppSettingsStore
    /// The deck's stored shell, read once: every control here owns its field and writes it back.
    @State private var config = SideDeckConfig.migrating()

    var body: some View {
        SettingsCard(
            Text("Side Deck"),
            note: Text("Placement, width, and how the deck opens.")
        ) {
            SettingsPickerRow(Text("Edge"), selection: Binding(
                get: { config.side },
                set: { move(to: $0) }
            )) {
                Text("Left").tag(SideDeckConfig.Side.left)
                Text("Right").tag(SideDeckConfig.Side.right)
            }
            SettingsDivider()
            SettingsButtonRow(Text("Swap Left / Right Sides")) { swapSides() }
            SettingsDivider()
            SettingsSliderRow(
                Text("Size"),
                value: config.width,
                range: SideDeckConfig.widthRange,
                step: 10,
                valueText: "\(Int(config.width)) pt",
                set: { value in
                    config.width = value
                    config.write()
                }
            )
            SettingsDivider()
            SettingsRowPair(
                left: {
                    SettingsToggleRow(Text("Edge Activation"), isOn: binding(\.edgeActivation))
                },
                right: {
                    SettingsToggleRow(Text("Identity Strip"), isOn: binding(\.identityStrip))
                }
            )
            SettingsDivider()
            SettingsSliderRow(
                Text("Open Dwell"),
                value: config.dwell,
                range: SideDeckConfig.dwellRange,
                step: 0.02,
                valueText: String(format: "%.2f s", config.dwell),
                set: { value in
                    config.dwell = value
                    config.write()
                }
            )
            .disabled(!config.edgeActivation)
            SettingsDivider()
            SettingsToggleRow(Text("Weather Handle"), isOn: binding(\.mergedWeatherHandle))
        }
    }

    private func binding(_ key: WritableKeyPath<SideDeckConfig, Bool>) -> Binding<Bool> {
        Binding(get: { config[keyPath: key] },
                set: {
                    config[keyPath: key] = $0
                    config.write()
                })
    }

    /// Picking an edge moves the Edge Bar to the other one: each surface owns one edge, never both.
    private func move(to side: SideDeckConfig.Side) {
        config.side = side
        config.write()
        store.setEdgePrimarySide(side == .left ? .right : .left)
    }

    private func swapSides() {
        SideDeckSettings.swapSides(store: store)
        config = SideDeckConfig.stored()
    }
}

enum SideDeckSettings {
    /// The one shared swap: both panes call this, so the two surfaces always exchange edges together.
    @MainActor
    static func swapSides(store: AppSettingsStore) {
        var config = SideDeckConfig.migrating()
        let swapped = SideDeckEdgeSwap.exchange(.init(deck: config.side, edgeBar: store.edgePrimarySide))
        config.side = swapped.deck
        config.write()
        store.setEdgePrimarySide(swapped.edgeBar)
    }
}
