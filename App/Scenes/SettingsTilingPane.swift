import ApplicationServices
import SwiftUI

/// Settings pane for auto-tiling, layout presets, gaps, floating exclusions, and tiling shortcuts (Phase 26b).
/// Renders through the shared card/row system (`Docs/SETTINGS.md` rule 2) — it used to be the one
/// pane whose headers had no card around them at all.
struct SettingsTilingPane: View {
    @ObservedObject var store: AppSettingsStore
    @ObservedObject private var engine = TilingEngine.shared
    @State private var floatingAppsDraft: String = ""

    var body: some View {
        // One card, not four. Window Management carried **six** sections — Tiling, Layout, Floating
        // Applications, Tiling Shortcuts, Window Chips, Window Behaviour — against rule 5's three,
        // and the extra headers plus their gaps are exactly what ran the page past the window.
        // Tiling shortcut assignments are consolidated under the Shortcuts tab (no duplicate controls).
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
                // The block inside the card keeps its own label, so the grouping survives the
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
            }
        }
    }
}
