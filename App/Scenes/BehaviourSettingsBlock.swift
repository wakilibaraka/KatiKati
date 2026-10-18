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
    @AppStorage(MenuBarSystemItem.enabledKey) private var menuBarSystemEnabled = false
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
            SettingsDivider()
            SettingsToggleRow(
                Text("Show CPU and Memory in the Menu Bar"),
                isOn: $menuBarSystemEnabled,
                note: Text("A small CPU and memory readout in the menu bar. Click it to open Activity Monitor.")
            )
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
