import SwiftUI

/// Phase 12b/35 — the five behaviour switches that used to sit on the Appearance tab (they change
/// what the app does, not how it looks). Same keys, same copy; only the home moved to Advanced.
struct BehaviourSettingsBlock: View {
    @AppStorage(BackgroundAppsStore.showSystemHelpersKey) private var showSystemHelpers = false
    @ObservedObject private var backgroundStore = BackgroundAppsStore.shared
    @AppStorage(MenuBarSystemItem.enabledKey) private var menuBarSystemEnabled = false
    @AppStorage(MemoryOverlayController.enabledKey) private var memoryOverlayEnabled = true

    var body: some View {
        Text("Behaviour").font(.headline)
        Toggle(isOn: $memoryOverlayEnabled) { Text("Hold Control to Show Memory") }
        Text("While the pointer is over the dock, holding Control shows how much memory each app uses.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Toggle(isOn: $showSystemHelpers) { Text("Show System Helpers") }
        Button("Reset Ignored Apps") { backgroundStore.unignoreAll() }
            .disabled(backgroundStore.ignored.isEmpty)
        Text("Background Apps lists running apps that have no window. Apple helper processes stay hidden unless this is on.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Toggle(isOn: $menuBarSystemEnabled) { Text("Show CPU and Memory in the Menu Bar") }
        Text("A small CPU and memory readout in the menu bar. Click it to open Activity Monitor.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// Phase 12 — the two window behaviours (Option-Tab switcher, restore after sleep) for the
/// Window Management page.
struct WindowBehaviourSettingsBlock: View {
    @AppStorage(WindowSwitcherController.enabledKey) private var switcherEnabled = true
    @AppStorage(WindowLayoutRestoreController.enabledKey) private var layoutRestoreEnabled = true

    var body: some View {
        Toggle(isOn: $switcherEnabled) { Text("Option-Tab Window Switcher") }
        Text("Hold Option and press Tab to pick a window from a thumbnail grid; release to switch. Shift reverses, Esc cancels.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Toggle(isOn: $layoutRestoreEnabled) { Text("Restore Window Layout After Sleep") }
        Button("Restore Windows From Last Sleep") {
            (NSApp.delegate as? AppDelegate)?.layoutRestore.restoreNow()
        }
        Text("After the Mac wakes or a display is reconnected, windows that moved are put back where they were. Needs Accessibility access.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
