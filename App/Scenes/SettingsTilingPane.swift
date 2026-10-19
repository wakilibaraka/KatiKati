import AppKit
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
                    set: { engine.setEnabled($0) }
                ),
                note: Text("Arranges your open windows on this screen without overlap. Turning it off puts every window back where it was.")
            )

            if !axTrusted {
                SettingsDivider()
                SettingsButtonRow(
                    Text("Allow Accessibility"),
                    note: Text("macOS needs this before KatiKati can move other apps' windows."),
                    action: { AccessibilitySettingsLink.url.map { NSWorkspace.shared.open($0) } }
                )
            }

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
                SettingsNote(presetNote)
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

                SettingsDivider()
                SettingsButtonRow(
                    Text("Re-tile Moved Windows"),
                    note: engine.releasedCount == 0
                        ? Text("No windows have been moved by hand.")
                        : Text("Windows you moved by hand stay put until you press this."),
                    action: { engine.retileAll() }
                )
                .disabled(engine.releasedCount == 0)
            }
        }

        SettingsCard(Text("How It Works")) {
            SettingsNote(Text("New windows join the layout by themselves. Drag or resize a window and it is left alone until you press Re-tile. Apps in the floating list are never tiled."))
            SettingsNote(Text("Snap zones (halves, quarters, thirds) move one window to a spot you pick. They work with tiling on or off; a snapped window stays where you put it."))
        }

        SettingsCard(Text("Snap Zones")) {
            if boundSnaps.isEmpty {
                SettingsNote(Text("No snap shortcut is set. Add one under Shortcuts → Snap Hotkeys."))
            } else {
                ForEach(boundSnaps, id: \.0) { action, keys in
                    SettingsRow(Text(verbatim: SettingsLayoutPane.shortcutActionName(action))) {
                        Text(verbatim: keys).font(.system(.body, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var axTrusted: Bool { AXIsProcessTrusted() }

    private var presetNote: Text {
        switch engine.preset {
        case .bsp: return Text("BSP: each new window takes half of the space left, so four windows form a grid.")
        case .mainStack: return Text("Main + Stack: the first window fills the left 55%; the rest stack on the right.")
        case .monocle: return Text("Monocle: every window is full size. Use Focus Next / Previous to flip between them.")
        }
    }

    private var boundSnaps: [(ShortcutAction, String)] {
        SettingsLayoutPane.snapHotkeyGroups.flatMap { $0 }.compactMap { action in
            store.shortcutBindings[action].flatMap(Self.glyphs).map { (action, $0) }
        }
    }

    private static func glyphs(_ trigger: ShortcutTrigger) -> String? {
        switch trigger {
        case .off: return nil
        case .chord(let c): return c.glyphs
        case .doubleTap(let k): return "\(k.glyph)\(k.glyph)"
        case .key(let k): return k.glyphs
        case .hyper(let code): return "✦" + (ShortcutKeyNames.name(for: code) ?? "?")
        }
    }
}
