import ApplicationServices
import SwiftUI

/// Settings pane for auto-tiling, layout presets, gaps, floating exclusions, and tiling shortcuts (Phase 26b).
struct SettingsTilingPane: View {
    @ObservedObject var store: AppSettingsStore
    @ObservedObject private var engine = TilingEngine.shared
    @State private var floatingAppsDraft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            section {
                Text("Tiling")
            } content: {
                Toggle("Enable Auto-Tiling", isOn: Binding(
                    get: { engine.isEnabled },
                    set: { on in
                        if on, !AXIsProcessTrusted() {
                            // Accessibility check
                        }
                        engine.setEnabled(on)
                    }
                )).accessibilityLabel("Enable Auto-Tiling")
                Text("Automatically tile open windows in binary space partitions or presets. Disabling instantly restores pre-tiling window frames.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            if engine.isEnabled {
                section {
                    Text("Layout")
                } content: {
                    Picker("Preset", selection: Binding(
                        get: { engine.preset },
                        set: { engine.setPreset($0) }
                    )) {
                        ForEach(TilingLayoutPreset.allCases, id: \.self) { preset in
                            Text(preset.localizedTitleKey).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Inner Gap")
                        Spacer()
                        Text(verbatim: "\(Int(engine.gaps.inner)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Slider(
                            value: Binding(
                                get: { Double(engine.gaps.inner) },
                                set: { engine.setGaps(TilingGaps(inner: CGFloat($0), outer: engine.gaps.outer)) }
                            ),
                            in: 0...32,
                            step: 1
                        )
                        .frame(width: 140)
                    }

                    HStack {
                        Text("Outer Gap")
                        Spacer()
                        Text(verbatim: "\(Int(engine.gaps.outer)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Slider(
                            value: Binding(
                                get: { Double(engine.gaps.outer) },
                                set: { engine.setGaps(TilingGaps(inner: engine.gaps.inner, outer: CGFloat($0))) }
                            ),
                            in: 0...32,
                            step: 1
                        )
                        .frame(width: 140)
                    }
                }

                section {
                    Text("Floating Applications")
                } content: {
                    Text("Applications listed below will float and never be tiled (one bundle identifier per line):")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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

                section {
                    Text("Tiling Shortcuts")
                } content: {
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
                        HStack {
                            shortcutActionTitle(action)
                            if duplicated.contains(action) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                                    .help(Text("Another action uses the same shortcut"))
                            }
                            Spacer(minLength: 12)
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
        }
        .padding(20)
    }

    private func section<Header: View, Content: View>(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header().font(.headline)
            content()
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
