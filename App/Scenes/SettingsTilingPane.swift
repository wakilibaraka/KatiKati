import ApplicationServices
import SwiftUI

/// Settings pane for auto-tiling, layout presets, gaps, floating exclusions, and tiling shortcuts (Phase 26b).
/// Renders through the shared card/row system (`Docs/SETTINGS.md` rule 2) — it used to be the one
/// pane whose headers had no card around them at all.
struct SettingsTilingPane: View {
    @ObservedObject var store: AppSettingsStore
    @ObservedObject private var engine = TilingEngine.shared
    @State private var floatingAppsDraft: String = ""
    /// The six tiling assignments start collapsed: they are 246 pt of a page that has to fit the
    /// window, and the same run is collapsed on the Shortcuts page (measured live 2026-10-15).
    @State private var showsTilingShortcuts = false

    var body: some View {
        // One card, not four. Window Management carried **six** sections — Tiling, Layout, Floating
        // Applications, Tiling Shortcuts, Window Chips, Window Behaviour — against rule 5's three,
        // and the extra headers plus their gaps are exactly what ran the page past the window. Every
        // row below is unchanged; the ones that only apply while tiling is on keep that guard, and
        // the shortcut block keeps its own label so the grouping is still visible inside the card.
        SettingsCard(Text("Tiling")) {
            SettingsToggleRow(
                Text("Enable Auto-Tiling"),
                isOn: Binding(
                    get: { engine.isEnabled },
                    set: { on in
                        if on, !AXIsProcessTrusted() {
                            // Accessibility check
                        }
                        engine.setEnabled(on)
                    }
                ),
                note: Text("Automatically tile open windows in binary space partitions or presets. Disabling instantly restores pre-tiling window frames.")
            )

            if engine.isEnabled {
                SettingsDivider()
                SettingsSegmentedRow(
                    Text("Preset"),
                    selection: Binding(get: { engine.preset }, set: { engine.setPreset($0) })
                ) {
                    ForEach(TilingLayoutPreset.allCases, id: \.self) { preset in
                        Text(preset.localizedTitleKey).tag(preset)
                    }
                }
                SettingsDivider()
                SettingsSliderRow(
                    Text("Inner Gap"),
                    value: engine.gaps.inner,
                    range: 0...32,
                    step: 1,
                    valueText: "\(Int(engine.gaps.inner)) pt",
                    set: { engine.setGaps(TilingGaps(inner: CGFloat($0), outer: engine.gaps.outer)) }
                )
                SettingsDivider()
                SettingsSliderRow(
                    Text("Outer Gap"),
                    value: engine.gaps.outer,
                    range: 0...32,
                    step: 1,
                    valueText: "\(Int(engine.gaps.outer)) pt",
                    set: { engine.setGaps(TilingGaps(inner: engine.gaps.inner, outer: CGFloat($0))) }
                )

                SettingsDivider()
                // The two blocks inside the card keep their own label, so the grouping survives the
                // merge without a second card (rule 5's three-section budget).
                Text("Floating Applications")
                    .font(.subheadline)
                SettingsNote(Text("Applications listed below will float and never be tiled (one bundle identifier per line):"))
                TextEditor(text: Binding(
                    get: { floatingAppsDraft.isEmpty ? engine.policy.serializedPatterns : floatingAppsDraft },
                    set: {
                        floatingAppsDraft = $0
                        engine.setPolicy(TilingPolicy.parse(patterns: $0))
                    }
                ))
                .font(.system(.body, design: .monospaced))
                .frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                SettingsDivider()
                DisclosureGroup(isExpanded: $showsTilingShortcuts) {
                    tilingShortcutRows
                } label: {
                    Text("Tiling Shortcuts").font(.subheadline)
                }
            }
        }
    }

    /// The six tiling assignments, one per line, like the Shortcuts page: an assignment is a name, a
    /// menu and a Record button, and three controls do not fit half a card (rule 5's exception;
    /// measured live 2026-10-15). The run is collapsed by default so the page fits the window.
    @ViewBuilder
    private var tilingShortcutRows: some View {
        let duplicated = ShortcutConflicts.duplicated(store.shortcutBindings)
        let tilingActions: [ShortcutAction] = [
            .toggleTiling,
            .cycleTilingLayout,
            .tilingFocusNext,
            .tilingFocusPrevious,
            .tilingSwapNext,
            .tilingSwapPrevious
        ]
        ForEach(tilingActions, id: \.self) { action in
            SettingsRow(shortcutActionTitle(action)) {
                HStack(spacing: SettingsMetrics.controlSpacing) {
                    if duplicated.contains(action) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                            .help(Text("Another action uses the same shortcut"))
                    }
                    Picker(selection: Binding(
                        get: { store.shortcutBindings[action] ?? .off },
                        set: { store.setShortcut(action, $0) }
                    )) {
                        Text("Off").tag(ShortcutTrigger.off)
                        Divider()
                        ForEach(ShortcutChord.allCases, id: \.self) { Text(verbatim: $0.glyphs).tag(ShortcutTrigger.chord($0)) }
                        Divider()
                        if case let .key(custom) = store.shortcutBindings[action] ?? .off {
                            Text(verbatim: custom.glyphs).tag(ShortcutTrigger.key(custom))
                            Divider()
                        }
                    } label: { EmptyView() }
                    .pickerStyle(.menu).fixedSize()
                    ShortcutRecorderButton { store.setShortcut(action, .key($0)) }
                }
            }
        }
    }

    private func shortcutActionTitle(_ action: ShortcutAction) -> Text {
        switch action {
        case .toggleTiling: return Text("Toggle Tiling")
        case .cycleTilingLayout: return Text("Cycle Tiling Layout")
        case .tilingFocusNext: return Text("Focus Next Tile")
        case .tilingFocusPrevious: return Text("Focus Previous Tile")
        case .tilingSwapNext: return Text("Swap with Next Tile")
        case .tilingSwapPrevious: return Text("Swap with Previous Tile")
        default: return Text(verbatim: "\(action)")
        }
    }
}
