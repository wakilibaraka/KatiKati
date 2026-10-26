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

/// Phase 12 — the two window behaviours (Option-Tab switcher, restore after sleep) for the
/// Window Management page.
struct WindowBehaviourSettingsBlock: View {
    @AppStorage(WindowSwitcherController.enabledKey) private var switcherEnabled = true
    @AppStorage(WindowLayoutRestoreController.enabledKey) private var layoutRestoreEnabled = true

    var body: some View {
        SettingsCard {
            // Two switches on one line (`Docs/SETTINGS.md` rule 5) — this card was the longest
            // run of one-row-per-line switches left on the page.
            SettingsToggleRow(
                Text("Option-Tab Window Switcher"),
                isOn: $switcherEnabled,
                note: Text("Hold Option and press Tab to pick a window from a thumbnail grid; release to switch. Shift reverses, Esc cancels.")
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

    var body: some View {
        SettingsCard(Text("Dock Window Layering")) {
            SettingsPickerRow(
                Text("Layering Mode"),
                selection: Binding(
                    get: { store.dockLayeringMode },
                    set: { store.setDockLayeringMode($0) }
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
    }
}
