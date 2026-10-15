import AppKit
import SwiftUI

/// Phase 8e — Settings row for the menu utilities that need a switch (the link cleaner; the colour picker
/// is a menu action and needs none). Same plain-row shape as `LiveIslandSettingsBlock`.
struct UtilitySettingsBlock: View {
    @ObservedObject var store: AppSettingsStore
    @AppStorage(ClipboardMonitor.soundsKey) private var clipboardSounds = false
    @AppStorage(ClipboardMonitor.notchToastKey) private var clipboardToast = false
    @AppStorage(ClipboardMonitor.ignorePatternsKey) private var clipboardIgnorePatterns = ""
    @AppStorage(LauncherRunner.enabledKey) private var launcherScripts = false
    @AppStorage(CustomCommand.key) private var customCommands = ""
    @AppStorage(CustomCommand.snippetsKey) private var snippets = ""
    @AppStorage("com.katikati.commandbar.hints") private var commandHints = true
    @AppStorage(FileIndexService.enabledKey) private var fastIndex = true
    @AppStorage(DailyHelpersService.hideFromCaptureKey) private var hideFromCapture = false
    @AppStorage(DailyHelpersService.capsLockKey) private var capsLockHUD = false
    @AppStorage(DailyHelpersService.batteryKey) private var batteryNudge = false
    @AppStorage(DailyHelpersService.ejectKey) private var usbEject = false
    @AppStorage(DailyHelpersService.privacyKey) private var privacyDot = false
    @AppStorage(TeleprompterModel.enabledKey) private var teleprompterPage = false

    var body: some View {
        HStack {
            Text("Clean Copied Links")
            Spacer(minLength: 12)
            Toggle("Clean Copied Links", isOn: Binding(get: { store.linkCleanerEnabled }, set: { store.setLinkCleanerEnabled($0) }))
                .toggleStyle(.switch).labelsHidden().accessibilityLabel("Clean Copied Links")
        }
        Text("Clipboard").font(.headline)
        row("Copy Sounds") {
            Toggle("Copy Sounds", isOn: $clipboardSounds).toggleStyle(.switch).labelsHidden().accessibilityLabel("Copy Sounds")
        }
        row("Copy Notifications") {
            Toggle("Copy Notifications", isOn: $clipboardToast).toggleStyle(.switch).labelsHidden().accessibilityLabel("Copy Notifications")
        }
        row("Ignore Patterns") {
            TextField("Ignore Patterns", text: $clipboardIgnorePatterns)
                .textFieldStyle(.roundedBorder).frame(width: 220)
        }
        Text("Daily Helpers").font(.headline)
        row("Hide from Screen Capture") {
            Toggle("Hide from Screen Capture", isOn: $hideFromCapture).toggleStyle(.switch).labelsHidden().accessibilityLabel("Hide from Screen Capture")
        }
        row("Caps Lock Indicator") {
            Toggle("Caps Lock Indicator", isOn: $capsLockHUD).toggleStyle(.switch).labelsHidden().accessibilityLabel("Caps Lock Indicator")
        }
        row("Charge Notices") {
            Toggle("Charge Notices", isOn: $batteryNudge).toggleStyle(.switch).labelsHidden().accessibilityLabel("Charge Notices")
        }
        HStack {
            Text("Clean Keyboard")
            Spacer(minLength: 12)
            Button("Lock for 60 Seconds") { KeyGuardService.shared.startCleaningLock() }
        }
        Text("Keys are off for 60 seconds. Press ⌃⌥⌘P to unlock sooner.").font(.caption).foregroundColor(.secondary)
        row("Offer to Eject Drives") {
            Toggle("Offer to Eject Drives", isOn: $usbEject).toggleStyle(.switch).labelsHidden().accessibilityLabel("Offer to Eject Drives")
        }
        row("Camera and Mic Indicator") {
            Toggle("Camera and Mic Indicator", isOn: $privacyDot).toggleStyle(.switch).labelsHidden().accessibilityLabel("Camera and Mic Indicator")
        }
        HStack {
            Text("Teleprompter")
            Spacer(minLength: 12)
            Button("Open Teleprompter Window") { TeleprompterWindowController.shared.show() }
        }
        row("Teleprompter Notch Page") {
            Toggle("Teleprompter Notch Page", isOn: $teleprompterPage).toggleStyle(.switch).labelsHidden().accessibilityLabel("Teleprompter Notch Page")
        }
        Text("Opens from ⌘Space (prompter). The window is hidden from screen recordings and shares.").font(.caption).foregroundColor(.secondary)
        Text("Launcher").font(.headline)
        row("Script Commands") {
            Toggle("Script Commands", isOn: $launcherScripts).toggleStyle(.switch).labelsHidden().accessibilityLabel("Script Commands")
        }
        row("Show Command Hints") {
            Toggle("Show Command Hints", isOn: $commandHints).toggleStyle(.switch).labelsHidden().accessibilityLabel("Show Command Hints")
        }
        row("Fast File Index") {
            Toggle("Fast File Index", isOn: $fastIndex).toggleStyle(.switch).labelsHidden().accessibilityLabel("Fast File Index")
        }
        VStack(alignment: .leading, spacing: 4) {
            Button("Replace Spotlight") {
                if let url = URL(string: SpotlightHandoff.settingsURL) { NSWorkspace.shared.open(url) }
            }
            ForEach(SpotlightHandoff.steps(), id: \.self) { step in
                spotlightStepText(step).font(.caption).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Text("Custom Commands").font(.headline)
        TextEditor(text: $customCommands)
            .font(.system(size: 11, design: .monospaced))
            .frame(height: 60)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15)))
        Text("Text Snippets").font(.headline)
        TextEditor(text: $snippets)
            .font(.system(size: 11, design: .monospaced))
            .frame(height: 60)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15)))
        Text("One per line: ;sig = Best regards, Sam. Type the trigger in ⌘Space and press Return to paste it.").font(.caption).foregroundColor(.secondary)
        Text("Shelf").font(.headline)
        row("Shake to Shelf") {
            Toggle("Shake to Shelf", isOn: Binding(get: { store.shelfShakeEnabled }, set: { store.setShelfShakeEnabled($0) }))
                .toggleStyle(.switch).labelsHidden().accessibilityLabel("Shake to Shelf")
        }
        row("Auto-Expire") {
            Toggle("Auto-Expire", isOn: Binding(get: { store.shelfAutoExpire }, set: { store.setShelfAutoExpire($0) }))
                .toggleStyle(.switch).labelsHidden().accessibilityLabel("Auto-Expire")
        }
        if store.shelfAutoExpire {
            row("Expire After") {
                Picker("Expire After", selection: Binding(get: { store.shelfExpiryDays }, set: { store.setShelfExpiryDays($0) })) {
                    Text("1 day").tag(1)
                    Text("3 days").tag(3)
                    Text("7 days").tag(7)
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
        }
        row("Storage") {
            Picker("Storage", selection: Binding(get: { store.shelfStorage }, set: { store.setShelfStorage($0) })) {
                Text("References").tag(ShelfStorage.reference)
                Text("Copies").tag(ShelfStorage.copy)
            }
            .labelsHidden().pickerStyle(.menu).fixedSize()
        }
        row("Clear Unpinned") {
            Button("Clear Unpinned") { AppDelegate.shared?.shelfStore.clear() }
        }
        HStack {
            Text("System Dock")
            Spacer(minLength: 12)
            Button("Restore Dock") { AppDelegate.shared?.restoreNativeDock() }
        }
    }

    private func row<C: View>(_ title: LocalizedStringKey, @ViewBuilder control: () -> C) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            control()
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
