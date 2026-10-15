import AppKit
import SwiftUI

/// Phase 12 (2026-10-15) — the Tools page's rows: the clipboard, the command and snippet editors,
/// and the shelf. It used to also carry the launcher's own rows and to share its page with the
/// launcher; the tools are their own tab now (`SettingsTab.tools`), and the launcher's rows are in
/// `LauncherSettingsBlock`. All rows go through the shared system (`Docs/SETTINGS.md` rule 2).
struct UtilitySettingsBlock: View {
    @ObservedObject var store: AppSettingsStore
    @AppStorage(ClipboardMonitor.soundsKey) private var clipboardSounds = false
    @AppStorage(ClipboardMonitor.notchToastKey) private var clipboardToast = false
    @AppStorage(ClipboardMonitor.ignorePatternsKey) private var clipboardIgnorePatterns = ""
    @AppStorage(CustomCommand.key) private var customCommands = ""
    @AppStorage(CustomCommand.snippetsKey) private var snippets = ""

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            SettingsCard(Text("Clipboard")) {
                // Cleaning copied links is a clipboard job, so it opens this card rather than
                // sitting in a headerless card of its own (`Docs/SETTINGS.md` rule 5).
                SettingsToggleRow(
                    Text("Clean Copied Links"),
                    isOn: Binding(get: { store.linkCleanerEnabled }, set: { store.setLinkCleanerEnabled($0) })
                )
                SettingsDivider()
                SettingsToggleRow(Text("Copy Sounds"), isOn: $clipboardSounds)
                SettingsDivider()
                SettingsToggleRow(Text("Copy Notifications"), isOn: $clipboardToast)
                SettingsDivider()
                SettingsRow(Text("Ignore Patterns")) {
                    TextField("Ignore Patterns", text: $clipboardIgnorePatterns)
                        .textFieldStyle(.roundedBorder).frame(width: 220)
                }
            }
            SettingsCard(Text("Custom Commands")) {
                TextEditor(text: $customCommands)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 60)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15)))
            }
            SettingsCard(Text("Text Snippets")) {
                TextEditor(text: $snippets)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 60)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15)))
                SettingsNote(Text("One per line: ;sig = Best regards, Sam. Type the trigger in ⌘Space and press Return to paste it."))
            }
            SettingsCard(Text("Shelf")) {
                SettingsToggleRow(
                    Text("Shake to Shelf"),
                    isOn: Binding(get: { store.shelfShakeEnabled }, set: { store.setShelfShakeEnabled($0) })
                )
                SettingsDivider()
                SettingsToggleRow(
                    Text("Auto-Expire"),
                    isOn: Binding(get: { store.shelfAutoExpire }, set: { store.setShelfAutoExpire($0) })
                )
                if store.shelfAutoExpire {
                    SettingsRow(Text("Expire After")) {
                        Picker("Expire After", selection: Binding(get: { store.shelfExpiryDays }, set: { store.setShelfExpiryDays($0) })) {
                            Text("1 day").tag(1)
                            Text("3 days").tag(3)
                            Text("7 days").tag(7)
                        }
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                    }
                }
                SettingsDivider()
                SettingsRow(Text("Storage")) {
                    Picker("Storage", selection: Binding(get: { store.shelfStorage }, set: { store.setShelfStorage($0) })) {
                        Text("References").tag(ShelfStorage.reference)
                        Text("Copies").tag(ShelfStorage.copy)
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                SettingsDivider()
                SettingsButtonRow(Text("Clear Unpinned")) { AppDelegate.shared?.shelfStore.clear() }
                SettingsDivider()
                SettingsRow(Text("System Dock")) {
                    Button("Restore Dock") { AppDelegate.shared?.restoreNativeDock() }
                }
            }
        }
    }

}

/// Phase 12 (2026-10-15) — the launcher's own rows (script commands, command hints, the file
/// index, the Spotlight hand-off), split out of `UtilitySettingsBlock` when the tools got their own
/// tab. The launcher and the Control Center share the Launcher page; these rows belong to neither
/// the clipboard nor the shelf.
struct LauncherSettingsBlock: View {
    @AppStorage(LauncherRunner.enabledKey) private var launcherScripts = false
    @AppStorage("com.katikati.commandbar.hints") private var commandHints = true
    @AppStorage(FileIndexService.enabledKey) private var fastIndex = true

    var body: some View {
        SettingsCard(Text("Launcher")) {
            SettingsToggleRow(Text("Script Commands"), isOn: $launcherScripts)
            SettingsDivider()
            SettingsToggleRow(Text("Show Command Hints"), isOn: $commandHints)
            SettingsDivider()
            SettingsToggleRow(Text("Fast File Index"), isOn: $fastIndex)
            SettingsDivider()
            SettingsButtonRow(Text("Replace Spotlight")) {
                if let url = URL(string: SpotlightHandoff.settingsURL) { NSWorkspace.shared.open(url) }
            }
            ForEach(SpotlightHandoff.steps(), id: \.self) { step in
                SettingsNote(spotlightStepText(step))
            }
        }
    }

    private func spotlightStepText(_ step: SpotlightHandoff.Step) -> Text {
        switch step {
        case .openKeyboard: return Text("Open System Settings › Keyboard.")
        case .openShortcuts: return Text("Click Keyboard Shortcuts….")
        case .selectSpotlight: return Text("Select Spotlight in the list.")
        case .uncheckShowSearch: return Text("Turn off Show Spotlight search.")
        case .testHere: return Text("Come back and press ⌘Space to test.")
        }
    }
}

/// Phase 12 — the helpers that surface in the notch (indicators, notices, teleprompter page), split
/// out of `UtilitySettingsBlock` so the Notch page owns them.
struct NotchHelpersSettingsBlock: View {
    @AppStorage(DailyHelpersService.hideFromCaptureKey) private var hideFromCapture = false
    @AppStorage(DailyHelpersService.capsLockKey) private var capsLockHUD = false
    @AppStorage(DailyHelpersService.batteryKey) private var batteryNudge = false
    @AppStorage(DailyHelpersService.ejectKey) private var usbEject = false
    @AppStorage(DailyHelpersService.privacyKey) private var privacyDot = false
    @AppStorage(TeleprompterModel.enabledKey) private var teleprompterPage = false

    var body: some View {
        SettingsCard(Text("Daily Helpers")) {
            SettingsToggleRow(Text("Hide from Screen Capture"), isOn: $hideFromCapture)
            SettingsDivider()
            SettingsToggleRow(Text("Caps Lock Indicator"), isOn: $capsLockHUD)
            SettingsDivider()
            SettingsToggleRow(Text("Charge Notices"), isOn: $batteryNudge)
            SettingsDivider()
            SettingsRow(Text("Clean Keyboard"), note: Text("Keys are off for 60 seconds. Press ⌃⌥⌘P to unlock sooner.")) {
                Button("Lock for 60 Seconds") { KeyGuardService.shared.startCleaningLock() }
            }
            SettingsDivider()
            SettingsToggleRow(Text("Offer to Eject Drives"), isOn: $usbEject)
            SettingsDivider()
            SettingsToggleRow(Text("Camera and Mic Indicator"), isOn: $privacyDot)
            SettingsDivider()
            SettingsRow(Text("Teleprompter"), note: Text("Opens from ⌘Space (prompter). The window is hidden from screen recordings and shares.")) {
                Button("Open Teleprompter Window") { TeleprompterWindowController.shared.show() }
            }
            SettingsDivider()
            SettingsToggleRow(Text("Teleprompter Notch Page"), isOn: $teleprompterPage)
        }
    }
}
