import SwiftUI

/// Phase 12b/35 — the five behaviour switches that used to sit on the Appearance tab (they change
/// what the app does, not how it looks). Same keys, same copy; only the home moved to Advanced.
/// Renders through the shared card/row system (`Docs/SETTINGS.md` rule 2).
struct BehaviourSettingsBlock: View {
    @AppStorage(BackgroundAppsStore.showSystemHelpersKey) private var showSystemHelpers = false
    @ObservedObject private var backgroundStore = BackgroundAppsStore.shared
    @AppStorage(MenuBarSystemItem.enabledKey) private var menuBarSystemEnabled = false
    @AppStorage(MemoryOverlayController.enabledKey) private var memoryOverlayEnabled = true

    var body: some View {
        SettingsCard(Text("Behaviour")) {
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
            SettingsButtonRow(Text("Reset Ignored Apps")) { backgroundStore.unignoreAll() }
                .disabled(backgroundStore.ignored.isEmpty)
            SettingsDivider()
            SettingsToggleRow(
                Text("Show CPU and Memory in the Menu Bar"),
                isOn: $menuBarSystemEnabled,
                note: Text("A small CPU and memory readout in the menu bar. Click it to open Activity Monitor.")
            )
        }
    }
}

/// Phase 12 — the two window behaviours (Option-Tab switcher, restore after sleep) for the
/// Window Management page.
struct WindowBehaviourSettingsBlock: View {
    @AppStorage(WindowSwitcherController.enabledKey) private var switcherEnabled = true
    @AppStorage(WindowLayoutRestoreController.enabledKey) private var layoutRestoreEnabled = true

    var body: some View {
        SettingsCard {
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
            SettingsButtonRow(Text("Restore Windows From Last Sleep")) {
                (NSApp.delegate as? AppDelegate)?.layoutRestore.restoreNow()
            }
        }
    }
}
