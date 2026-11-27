import AppKit
import SwiftUI

/// Phase 12b/35 — the behaviour switches that used to sit on the Appearance tab (they change what
/// the app does, not how it looks). Same keys, same copy; only the home moved to Advanced.
/// Renders through the shared card/row system (`Docs/SETTINGS.md` rule 2).
///
/// `store` is explicit and has no default: the full-screen row reads the app's own setting, and a
/// missing argument must fail the build, not quietly point at another store (`AGENTS.md`).
struct BehaviourSettingsBlock: View {
    @ObservedObject var store: AppSettingsStore
    @AppStorage(BackgroundAppsStore.showSystemHelpersKey) private var showSystemHelpers = false
    @ObservedObject private var backgroundStore = BackgroundAppsStore.shared
    @AppStorage(MemoryOverlayController.enabledKey) private var memoryOverlayEnabled = true

    var body: some View {
        SettingsCard(Text("Behaviour")) {
            // Was a headerless card of its own above this one: one row is not a section, and the
            // page then owed a header nothing could name (`Docs/SETTINGS.md` rule 5).
            SettingsToggleRow(
                Text("Predict full-screen transitions to prevent taskbar flicker"),
                isOn: Binding(
                    get: { store.fullscreenIntentEnabled },
                    set: store.setFullscreenIntentEnabled
                ),
                info: fullscreenIntentNote
            )
            SettingsDivider()
            SettingsToggleRow(
                Text("Hold Control to Show Memory"),
                isOn: $memoryOverlayEnabled,
                note: Text("While the pointer is over the dock, holding Control shows how much memory each app uses.")
            )
            SettingsDivider()
            SettingsToggleRow(
                Text("Show System Helpers"),
                isOn: $showSystemHelpers,
                note: Text("Background Apps lists running apps that have no window. Apple helper processes stay hidden unless this is on.")
            )
            // Rule 7: it was disabled with nothing on the row saying why.
            SettingsButtonRow(
                Text("Reset Ignored Apps"),
                note: backgroundStore.ignored.isEmpty ? Text("No background app is ignored right now.") : nil
            ) { backgroundStore.unignoreAll() }
                .disabled(backgroundStore.ignored.isEmpty)
        }
    }

    private var fullscreenIntentNote: String {
        String(localized: "To keep the taskbar from flashing when you switch into full screen, KatiKati has to hide it before your input reaches the app. It therefore watches global left-clicks, key presses and trackpad gestures, and recognizes only four of them: the window’s green button, Control-Command-F, Control-Left/Right arrow, and a three-finger horizontal swipe. What you type is never recorded, logged, or sent anywhere. Turning this off disables the watching completely.")
    }
}

/// The two hold-to-switch bindings that open the Window Switcher.
struct WindowSwitcherHotkeysBlock: View {
    @AppStorage(WindowSwitcherController.enabledKey) private var switcherEnabled = true
    @AppStorage(CommandTabTakeover.enabledKey) private var commandTabEnabled = false

    var body: some View {
        SettingsCard {
            SettingsToggleRow(
                Text("Option-Tab Window Switcher"),
                isOn: $switcherEnabled,
                note: Text("Hold Option and press Tab to pick a window from a thumbnail grid; release to switch. Shift reverses, Esc cancels.")
            )

            SettingsDivider()
            SettingsToggleRow(
                Text("Use ⌘Tab for the Window Switcher"),
                isOn: $commandTabEnabled,
                note: Text("Replaces the system ⌘Tab with the same window grid; ⌘` shows only the front app's windows. Type to search; ⌘W closes, ⌘M minimizes, ⌘Q quits the selected window's app. Needs Accessibility access; turn off to get the system switcher back.")
            )
        }
    }
}

/// The desktop window box and the window drawer. Both are things that live *on* the desktop rather
/// than over a window, which is why they are not on the switcher's pane.
struct DesktopWindowSettingsBlock: View {
    @AppStorage(WindowStripController.enabledKey) private var boxEnabled = false
    @AppStorage(WindowDrawerController.edgeHoverKey) private var edgeHoverEnabled = false

    var body: some View {
        SettingsCard(Text("Desktop Window Box")) {
            SettingsToggleRow(
                Text("Keep the window box on the desktop"),
                isOn: $boxEnabled,
                note: Text("A glass card listing your open windows, drawn on the desktop underneath every app so it never covers one. Click a window to bring it forward. Press ⌃⌥W for the full Side Deck.")
            )

            SettingsDivider()
            SettingsToggleRow(
                Text("Open Side Deck at Screen Edge"),
                isOn: $edgeHoverEnabled,
                note: Text("Rest the pointer on the left edge of a display for a moment to open the Side Deck. ⌃⌥W always works.")
            )
        }
    }
}

/// Window frame behaviours: the focus ring and the layout KatiKati puts back after sleep.
struct WindowFrameSettingsBlock: View {
    @AppStorage(WindowBorderController.enabledKey) private var borderEnabled = false
    @AppStorage(WindowLayoutRestoreController.enabledKey) private var layoutRestoreEnabled = true

    var body: some View {
        SettingsCard {
            SettingsToggleRow(
                Text("Border Around Focused Window"),
                isOn: $borderEnabled,
                note: Text("Draws an accent-colored outline around the window you are working in.")
            )

            SettingsDivider()
            SettingsToggleRow(
                Text("Restore Window Layout After Sleep"),
                isOn: $layoutRestoreEnabled,
                note: Text("After the Mac wakes or a display is reconnected, windows that moved are put back where they were. Needs Accessibility access.")
            )

            SettingsDivider()
            SettingsButtonRow(Text("Restore Windows From Last Sleep")) {
                (NSApp.delegate as? AppDelegate)?.layoutRestore.restoreNow()
            }
        }
    }
}

/// Dock window layering and multi-tier reliability controls.
struct DockLayeringSettingsBlock: View {
    @ObservedObject var store: AppSettingsStore
    /// The piggyback mode rewrites the native Dock's settings and restarts it, so picking it asks first
    /// (owner 2026-10-27: keep the mode, behind a confirm-and-restore step). The picker stays on the
    /// current mode until the user confirms.
    @State private var confirmingPiggyback = false

    var body: some View {
        SettingsCard(Text("Dock Window Layering")) {
            SettingsPickerRow(
                Text("Layering Mode"),
                selection: Binding(
                    get: { store.dockLayeringMode },
                    set: { mode in
                        if mode == .nativeDockVisibleFramePiggyback, store.dockLayeringMode != mode {
                            confirmingPiggyback = true
                        } else {
                            store.setDockLayeringMode(mode)
                        }
                    }
                ),
                note: Text(store.dockLayeringMode.subtitle)
            ) {
                ForEach(DockLayeringMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            SettingsDivider()
            SettingsToggleRow(
                Text("SkyLight Compositor Fast Path"),
                isOn: Binding(
                    get: { store.dockSkyLightReinforcement },
                    set: { store.setDockSkyLightReinforcement($0) }
                ),
                note: Text("Instructs WindowServer to commit window level changes in the same screen refresh frame.")
            )

            SettingsDivider()
            SettingsToggleRow(
                Text("AppleScript Window Resize Fallback"),
                isOn: Binding(
                    get: { store.dockAppleScriptFallback },
                    set: { store.setDockAppleScriptFallback($0) }
                ),
                note: Text("Uses System Events automation to resize non-standard or Electron application windows when direct Accessibility fails.")
            )

            SettingsDivider()
            SettingsButtonRow(Text("Install Keep-Alive Watchdog")) {
                try? DockWindowManager.installKeepAliveLaunchAgent(executablePath: Bundle.main.executablePath ?? "")
            }

            SettingsDivider()
            SettingsButtonRow(Text("Suppress Native macOS Dock")) {
                DockWindowManager.suppressNativeMacDock(suppress: true)
            }

            SettingsDivider()
            SettingsButtonRow(Text("Restore Native macOS Dock")) {
                DockWindowManager.suppressNativeMacDock(suppress: false)
            }
        }
        .alert(Text("Change your macOS Dock settings?"), isPresented: $confirmingPiggyback) {
            Button("Change Dock Settings") { store.setDockLayeringMode(.nativeDockVisibleFramePiggyback) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This mode keeps Apple's Dock visible at the bottom, under KatiKati: it turns off Dock auto-hide and magnification, sets the Dock's icon size, and restarts the Dock. KatiKati puts your Dock settings back when you choose another mode.")
        }
    }
}

// MARK: - Window Management revamp (WM-5)

/// Window Management is two surfaces, not five sub-tabs of one list: the **Window Switcher** the
/// hotkeys open, and the **Dock & Desktop** surfaces drawn around windows.
enum WindowManagementPane: String, CaseIterable, Identifiable {
    case switcher, dock

    var id: String { rawValue }

    var title: Text {
        switch self {
        case .switcher: return Text("Window Switcher")
        case .dock: return Text("Dock & Desktop")
        }
    }

    var sections: [WindowManagementSection] {
        WindowManagementSection.allCases.filter { $0.pane == self }
    }
}

enum WindowManagementSection: String, CaseIterable, Identifiable {
    // Window Switcher — everything the Option-Tab / ⌘Tab surface answers to.
    case style, hotkeys, filtering, ordering
    // Dock & Desktop — the surfaces drawn around windows, plus snapping.
    case hover, desktop, windows, snapping

    var id: String { rawValue }

    var pane: WindowManagementPane {
        switch self {
        case .style, .hotkeys, .filtering, .ordering: return .switcher
        case .hover, .desktop, .windows, .snapping: return .dock
        }
    }

    var title: Text {
        switch self {
        case .style: return Text("Style")
        case .hotkeys: return Text("Hotkeys")
        case .filtering: return Text("Filtering")
        case .ordering: return Text("Ordering")
        case .hover: return Text("Hover Preview")
        case .desktop: return Text("Desktop")
        case .windows: return Text("Windows")
        case .snapping: return Text("Snap Preview")
        }
    }
}

/// The Window Management page: one pane picker, one section picker for that pane, cards below.
struct WindowManagementSettingsPane: View {
    @ObservedObject var store: AppSettingsStore
    @AppStorage("com.katikati.windowManagement.pane") private var paneRaw = WindowManagementPane.switcher.rawValue
    @AppStorage("com.katikati.windowManagement.section") private var sectionRaw = WindowManagementSection.style.rawValue
    @AppStorage(SnapGaps.outerKey) private var snapOuterGap = 0.0
    @AppStorage(SnapGaps.innerKey) private var snapInnerGap = 0.0
    @State private var showsStyleSettings = false
    @State private var showsDockLayering = false

    private var pane: WindowManagementPane {
        WindowManagementPane(rawValue: paneRaw) ?? .switcher
    }

    /// A section left over from the other pane is never shown: the picker always agrees with the
    /// content below it.
    private var section: WindowManagementSection {
        let stored = WindowManagementSection(rawValue: sectionRaw) ?? .style
        return stored.pane == pane ? stored : (pane.sections.first ?? .style)
    }

    private var paneBinding: Binding<WindowManagementPane> {
        Binding(get: { pane }, set: { next in
            paneRaw = next.rawValue
            if section.pane != next {
                sectionRaw = (next.sections.first ?? .style).rawValue
            }
        })
    }

    private var sectionBinding: Binding<WindowManagementSection> {
        Binding(get: { section }, set: { next in
            sectionRaw = next.rawValue
            paneRaw = next.pane.rawValue
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            Picker(selection: paneBinding) {
                ForEach(WindowManagementPane.allCases) { pane in
                    pane.title.tag(pane)
                }
            } label: {
                Text("Window Management")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Picker(selection: sectionBinding) {
                ForEach(pane.sections) { section in
                    section.title.tag(section)
                }
            } label: {
                Text("Window Management")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch section {
            case .style: styleSection
            case .hotkeys: hotkeysSection
            case .filtering: filteringSection
            case .ordering: orderingSection
            case .hover: hoverSection
            case .desktop: desktopSection
            case .windows: windowsSection
            case .snapping: snappingSection
            }
        }
    }

    private var styleSection: some View {
        SettingsCard(Text("Switcher Style")) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(WindowSwitcherStyle.allCases) { style in
                    styleCard(style)
                }
            }
            .padding(.vertical, 8)
            SettingsDivider()
            SettingsToggleRow(
                Text("Keep switcher open when hotkeys are released"),
                isOn: Binding(
                    get: { store.switcherStyleConfig.keepOpenOnRelease },
                    set: { value in updateConfig { $0.keepOpenOnRelease = value } }
                ),
                note: Text("Return, a click or Esc still closes it.")
            )
        }
    }

    private func styleCard(_ style: WindowSwitcherStyle) -> some View {
        let selected = store.switcherStyle == style
        return Button { store.setSwitcherStyle(style) } label: {
            VStack(spacing: 7) {
                Image(systemName: style.symbol).font(.system(size: 22, weight: .medium))
                style.title.font(.system(size: 12, weight: selected ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if selected, style != .disabled {
                Button { showsStyleSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .help(Text("Style settings"))
                .popover(isPresented: $showsStyleSettings, arrowEdge: .trailing) {
                    WindowSwitcherStyleEditor(store: store)
                }
            }
        }
    }

    private var hotkeysSection: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            WindowSwitcherHotkeysBlock()
            SettingsCard(Text("Switcher Hotkeys")) {
                SettingsRow(Text("Secondary Switcher Chord"),
                            note: Text("A second hold-to-switch combination beside the main Option-Tab binding.")) {
                    HStack(spacing: 8) {
                        Text(verbatim: store.secondarySwitcherKey?.glyphs ?? String(localized: "Off"))
                            .foregroundStyle(.secondary)
                        ShortcutRecorderButton { store.setSecondarySwitcherKey($0) }
                        Button("Clear") { store.setSecondarySwitcherKey(nil) }
                            .disabled(store.secondarySwitcherKey == nil)
                    }
                }
            }
            PinnedAppHotkeySettings(store: store)
        }
    }

    private var orderingSection: some View {
        SettingsCard(Text("Predictive Ordering")) {
            SettingsToggleRow(
                Text("Put likely windows first"),
                isOn: Binding(get: { store.predictiveRankingEnabled },
                              set: store.setPredictiveRankingEnabled),
                note: Text("Combines recency with how often you choose a window. Frequency data stays on this Mac.")
            )
            SettingsDivider()
            SettingsButtonRow(Text("Clear Learned Ordering"),
                              note: store.predictiveRankingEnabled ? nil : Text("Turn predictive ordering on to use it.")) {
                store.clearWindowSwitcherLearning()
            }
            .disabled(!store.predictiveRankingEnabled)
        }
    }

    private var filteringSection: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            SettingsLayoutPane(store: store, mode: .chips)
            SettingsCard(Text("Window Filtering")) {
                SettingsToggleRow(
                    Text("Current display only"),
                    isOn: filterBinding(\.currentDisplayOnly),
                    note: Text("Windows whose display is unknown are kept rather than hidden.")
                )
                SettingsDivider()
                SettingsToggleRow(
                    Text("Current Space only"),
                    isOn: filterBinding(\.currentSpaceOnly),
                    note: Text("Reads Space membership only when the switcher opens.")
                )
                SettingsDivider()
                SettingsToggleRow(Text("Show minimized windows"), isOn: filterBinding(\.showMinimized))
                SettingsDivider()
                SettingsToggleRow(Text("Show hidden windows"), isOn: filterBinding(\.showHidden))
            }
            IgnoredWindowAppsSettings(store: store)
        }
    }

    private var hoverSection: some View {
        SettingsCard(Text("Hover Preview")) {
            SettingsToggleRow(
                Text("Show window previews on hover"),
                isOn: Binding(get: { store.chipPreviewEnabled }, set: store.setChipPreviewEnabled)
            )
            SettingsDivider()
            SettingsPickerRow(Text("Open Delay"),
                              selection: Binding(get: { store.chipPreviewDelayMs },
                                                 set: store.setChipPreviewDelayMs)) {
                Text("150 ms").tag(150)
                Text("350 ms").tag(350)
                Text("600 ms").tag(600)
            }
            SettingsDivider()
            SettingsPickerRow(Text("Size"),
                              selection: Binding(get: { store.chipPreviewPreset.size },
                                                 set: { value in updatePreset { $0.size = value } })) {
                ForEach(DockHoverPreviewPreset.Size.allCases) { $0.title.tag($0) }
            }
            SettingsDivider()
            SettingsPickerRow(Text("Shape"),
                              selection: Binding(get: { store.chipPreviewPreset.shape },
                                                 set: { value in updatePreset { $0.shape = value } })) {
                ForEach(DockHoverPreviewPreset.Shape.allCases) { $0.title.tag($0) }
            }
            SettingsDivider()
            SettingsPickerRow(Text("Tint"),
                              selection: Binding(get: { store.chipPreviewPreset.tint },
                                                 set: { value in updatePreset { $0.tint = value } })) {
                ForEach(DockHoverPreviewPreset.Tint.allCases) { $0.title.tag($0) }
            }
            SettingsDivider()
            SettingsToggleRow(Text("Show quick actions"),
                              isOn: Binding(get: { store.chipPreviewPreset.showsQuickActions },
                                            set: { value in updatePreset { $0.showsQuickActions = value } }))
            SettingsDivider()
            SettingsToggleRow(Text("Minimize quick action"),
                              isOn: Binding(get: { store.chipPreviewPreset.showsMinimizeQuickAction },
                                            set: { value in updatePreset { $0.showsMinimizeQuickAction = value } }))
                .disabled(!store.chipPreviewPreset.showsQuickActions)
            SettingsDivider()
            SettingsToggleRow(Text("Maximize quick action"),
                              isOn: Binding(get: { store.chipPreviewPreset.showsMaximizeQuickAction },
                                            set: { value in updatePreset { $0.showsMaximizeQuickAction = value } }))
                .disabled(!store.chipPreviewPreset.showsQuickActions)
        }
    }

    private var desktopSection: some View {
        DesktopWindowSettingsBlock()
    }

    private var windowsSection: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            WindowFrameSettingsBlock()
            SettingsCard(Text("Green Button")) {
                SettingsPickerRow(
                    Text("Clicking the green button"),
                    selection: Binding(get: { store.greenButtonBehavior },
                                       set: store.setGreenButtonBehavior),
                    note: Text("Option-click uses the native macOS Zoom behaviour.")
                ) {
                    Text("Native Full Screen").tag(GreenButtonBehavior.nativeFullscreen)
                    Text("Maximize in Current Space").tag(GreenButtonBehavior.maximizeInCurrentSpace)
                }
                // SN-5: maximize-in-place is the one setting that arms a global click tap, so the
                // caveat sits where the choice is made instead of in a release note.
                if store.greenButtonBehavior == .maximizeInCurrentSpace {
                    Text("This mode watches the green button through a global click observer. If a click ever feels delayed, switch back to Native Full Screen.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            SettingsCard {
                DisclosureGroup(isExpanded: $showsDockLayering) {
                    DockLayeringSettingsBlock(store: store)
                } label: {
                    Text("Dock Window Layering").font(.system(size: 13, weight: .semibold))
                }
            }
        }
    }

    private var snappingSection: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            SettingsCard(Text("Snap Preview")) {
                SettingsToggleRow(Text("Snap windows by dragging to an edge"),
                                  isOn: Binding(get: { store.snapDragEnabled }, set: store.setSnapDragEnabled))
                SettingsDivider()
                SettingsPickerRow(Text("Preview"),
                                  selection: Binding(get: { store.snapPreviewStyle },
                                                     set: store.setSnapPreviewStyle)) {
                    Text("Outline").tag(SnapPreviewStyle.outline)
                    Text("Filled").tag(SnapPreviewStyle.filled)
                    Text("Off").tag(SnapPreviewStyle.off)
                }
                SettingsDivider()
                SettingsSliderRow(Text("Edge Margin"), value: store.snapEdgeMargin,
                                  range: 4...40, step: 1,
                                  valueText: "\(Int(store.snapEdgeMargin)) pt") { value in
                    store.setSnapEdgeMargin(value)
                }
                SettingsDivider()
                SettingsSliderRow(Text("Outer Gap"), value: snapOuterGap,
                                  range: 0...32, step: 1,
                                  valueText: "\(Int(snapOuterGap)) pt") { snapOuterGap = $0 }
                SettingsDivider()
                SettingsSliderRow(Text("Inner Gap"), value: snapInnerGap,
                                  range: 0...32, step: 1,
                                  valueText: "\(Int(snapInnerGap)) pt") { snapInnerGap = $0 }
            }
            SettingsNote(Text("Keeps snapped windows clear of screen edges, the Dock, and each other."))
            SettingsCard(Text("Snap Shortcuts")) {
                SettingsButtonRow(Text("Edit Snap Shortcuts"),
                                  note: Text("Every snap zone is a normal shortcut action; this page never duplicates that editor.")) {
                    (NSApp.delegate as? AppDelegate)?.openSettings(selecting: .shortcuts)
                }
            }
        }
    }

    private func filterBinding(_ keyPath: WritableKeyPath<WindowFilterPolicy, Bool>) -> Binding<Bool> {
        Binding(get: { store.switcherFilterPolicy[keyPath: keyPath] }, set: { value in
            var policy = store.switcherFilterPolicy
            policy[keyPath: keyPath] = value
            store.setSwitcherFilterPolicy(policy)
        })
    }

    private func updateConfig(_ body: (inout WindowSwitcherStyleConfig) -> Void) {
        var config = store.switcherStyleConfig
        body(&config)
        store.setSwitcherStyleConfig(config)
    }

    private func updatePreset(_ body: (inout DockHoverPreviewPreset) -> Void) {
        var preset = store.chipPreviewPreset
        body(&preset)
        store.setChipPreviewPreset(preset)
    }
}

private struct WindowSwitcherStyleEditor: View {
    @ObservedObject var store: AppSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Style Settings").font(.system(size: 13, weight: .semibold))
            SettingsSliderRow(Text("Icon Size"), value: store.switcherStyleConfig.iconSize,
                              range: 16...128, step: 1,
                              valueText: "\(Int(store.switcherStyleConfig.iconSize)) pt") { value in
                update { $0.iconSize = value }
            }
            SettingsSliderRow(Text("Spacing"), value: store.switcherStyleConfig.spacing,
                              range: 0...48, step: 1,
                              valueText: "\(Int(store.switcherStyleConfig.spacing)) pt") { value in
                update { $0.spacing = value }
            }
            SettingsSliderRow(Text("Opacity"), value: store.switcherStyleConfig.opacity,
                              range: 0.2...1, step: 0.05,
                              valueText: "\(Int(store.switcherStyleConfig.opacity * 100))%") { value in
                update { $0.opacity = value }
            }
            SettingsSliderRow(Text("Animation Speed"), value: store.switcherStyleConfig.animationSpeed,
                              range: 0.1...3, step: 0.1,
                              valueText: String(format: "%.1f×", store.switcherStyleConfig.animationSpeed)) { value in
                update { $0.animationSpeed = value }
            }
            SettingsRow(Text("Rows")) {
                Stepper(value: Binding(get: { store.switcherStyleConfig.rows },
                                       set: { value in update { $0.rows = value } }), in: 0...8) {
                    Text(verbatim: "\(store.switcherStyleConfig.rows)")
                }
            }
            SettingsRow(Text("Columns")) {
                Stepper(value: Binding(get: { store.switcherStyleConfig.columns },
                                       set: { value in update { $0.columns = value } }), in: 0...8) {
                    Text(verbatim: "\(store.switcherStyleConfig.columns)")
                }
            }
            SettingsRow(Text("Accent")) {
                HStack(spacing: 8) {
                    ColorPicker("", selection: accentBinding).labelsHidden()
                    Button("Use System Accent") { update { $0.accentColor = nil } }
                        .disabled(store.switcherStyleConfig.accentColor == nil)
                }
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private var accentBinding: Binding<Color> {
        Binding(get: {
            guard let c = store.switcherStyleConfig.accentColor else { return .accentColor }
            return Color(red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
        }, set: { color in
            let converted = NSColor(color).usingColorSpace(.sRGB) ?? .controlAccentColor
            update {
                $0.accentColor = WindowSwitcherAccentColor(red: Double(converted.redComponent),
                                                           green: Double(converted.greenComponent),
                                                           blue: Double(converted.blueComponent),
                                                           alpha: Double(converted.alphaComponent))
            }
        })
    }

    private func update(_ body: (inout WindowSwitcherStyleConfig) -> Void) {
        var config = store.switcherStyleConfig
        body(&config)
        store.setSwitcherStyleConfig(config)
    }
}

private struct PinnedAppHotkeySettings: View {
    @ObservedObject var store: AppSettingsStore
    @State private var app = ""
    @State private var key: ShortcutKey?
    @State private var notice: String?

    private var runningApps: [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier else { return nil }
                return (bundleID, app.localizedName ?? bundleID)
            }
            .filter { app in !store.pinnedAppHotkeys.contains { $0.bundleID == app.bundleID } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        SettingsCard(Text("Pinned App Hotkeys")) {
            if store.pinnedAppHotkeys.isEmpty {
                Text("No pinned apps yet.").foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            ForEach(store.pinnedAppHotkeys) { hotkey in
                SettingsRow(Text(verbatim: AppDisplayNameResolver.displayName(for: hotkey.bundleID))) {
                    HStack(spacing: 8) {
                        Text(verbatim: hotkey.key.glyphs).foregroundStyle(.secondary)
                        Button { store.setPinnedAppHotkeys(store.pinnedAppHotkeys.filter { $0 != hotkey }) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .help(Text("Remove"))
                    }
                }
            }
            SettingsDivider()
            SettingsRow(Text("Pin an App"), note: notice.map { Text(verbatim: $0) }) {
                HStack(spacing: 8) {
                    Picker(selection: $app) {
                        Text("Choose App").tag("")
                        ForEach(runningApps, id: \.bundleID) { app in
                            Text(verbatim: app.name).tag(app.bundleID)
                        }
                    } label: { Text("App") }
                    .labelsHidden().frame(maxWidth: 150)
                    ShortcutRecorderButton { key = $0 }
                    Button("Add") { add() }
                        .disabled(app.isEmpty || key == nil)
                }
            }
        }
    }

    private func add() {
        guard !app.isEmpty, let key else { return }
        var next = store.pinnedAppHotkeys
        next.append(PinnedAppHotkey(bundleID: app, key: key))
        let validated = PinnedAppHotkeyValidation.validated(next)
        guard validated.count == next.count else {
            notice = String(localized: "That key is already used by another pinned app.")
            return
        }
        store.setPinnedAppHotkeys(next)
        self.app = ""; self.key = nil; notice = nil
    }
}

private struct IgnoredWindowAppsSettings: View {
    @ObservedObject var store: AppSettingsStore
    @State private var app = ""

    private var runningApps: [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier,
                      !store.switcherFilterPolicy.ignoredBundleIDs.contains(bundleID) else { return nil }
                return (bundleID, app.localizedName ?? bundleID)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        SettingsCard(Text("Ignored Apps")) {
            if store.switcherFilterPolicy.ignoredBundleIDs.isEmpty {
                Text("No ignored apps.").foregroundStyle(.secondary).padding(.vertical, 8)
            }
            ForEach(store.switcherFilterPolicy.ignoredBundleIDs, id: \.self) { bundleID in
                SettingsRow(Text(verbatim: AppDisplayNameResolver.displayName(for: bundleID))) {
                    Button { remove(bundleID) } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).help(Text("Remove"))
                }
            }
            SettingsDivider()
            SettingsRow(Text("Ignore an App")) {
                HStack(spacing: 8) {
                    Picker(selection: $app) {
                        Text("Choose App").tag("")
                        ForEach(runningApps, id: \.bundleID) { app in
                            Text(verbatim: app.name).tag(app.bundleID)
                        }
                    } label: { Text("App") }
                    .labelsHidden().frame(maxWidth: 170)
                    Button("Add") { add() }.disabled(app.isEmpty)
                }
            }
        }
    }

    private func add() {
        guard !app.isEmpty else { return }
        var policy = store.switcherFilterPolicy
        policy.ignoredBundleIDs.append(app)
        store.setSwitcherFilterPolicy(policy)
        app = ""
    }

    private func remove(_ bundleID: String) {
        var policy = store.switcherFilterPolicy
        policy.ignoredBundleIDs.removeAll { $0 == bundleID }
        store.setSwitcherFilterPolicy(policy)
    }
}

private extension WindowSwitcherStyle {
    var title: Text {
        switch self {
        case .thumbnail: return Text("Thumbnail")
        case .list: return Text("List")
        case .icons: return Text("Icons")
        case .classicIcons: return Text("Classic")
        case .carousel: return Text("Carousel")
        case .disabled: return Text("Disable")
        }
    }

    var symbol: String {
        switch self {
        case .thumbnail: return "rectangle.on.rectangle"
        case .list: return "list.bullet.rectangle"
        case .icons: return "square.grid.2x2"
        case .classicIcons: return "list.bullet"
        case .carousel: return "rectangle.on.rectangle.angled"
        case .disabled: return "nosign"
        }
    }
}

private extension DockHoverPreviewPreset.Size {
    var title: Text {
        switch self {
        case .compact: return Text("Compact")
        case .standard: return Text("Standard")
        case .large: return Text("Large")
        }
    }
}

private extension DockHoverPreviewPreset.Shape {
    var title: Text {
        switch self {
        case .roundedCard: return Text("Rounded Card")
        case .squircle: return Text("Squircle")
        case .borderlessGlass: return Text("Borderless Glass")
        }
    }
}

private extension DockHoverPreviewPreset.Tint {
    var title: Text {
        switch self {
        case .liquidGlass: return Text("Liquid Glass")
        case .darkObsidian: return Text("Dark Obsidian")
        case .appAccent: return Text("App Accent")
        }
    }
}
