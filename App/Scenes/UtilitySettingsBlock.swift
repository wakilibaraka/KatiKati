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
    @AppStorage(ClipboardMonitor.keepDaysKey) private var clipboardKeepDays = 0
    @AppStorage(CustomCommand.key) private var customCommands = ""
    @AppStorage(CustomCommand.snippetsKey) private var snippets = ""
    @AppStorage(ClaudeHookInstaller.enabledKey) private var claudeHook = false
    @State private var claudeHookFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            SettingsBentoSplit {
                // One row per line: this card is a half-width column, where a side-by-side pair
                // squeezes the labels into a wrapped sliver.
                SettingsCard(Text("Clipboard")) {
                    SettingsToggleRow(
                        Text("Clean Copied Links"),
                        isOn: Binding(get: { store.linkCleanerEnabled }, set: { store.setLinkCleanerEnabled($0) })
                    )
                    SettingsDivider()
                    SettingsRow(Text("Ignore Patterns")) {
                        TextField("Ignore Patterns", text: $clipboardIgnorePatterns)
                            .textFieldStyle(.roundedBorder).frame(width: 200)
                    }
                    SettingsDivider()
                    SettingsToggleRow(Text("Copy Sounds"), isOn: $clipboardSounds)
                    SettingsDivider()
                    SettingsToggleRow(Text("Copy Notifications"), isOn: $clipboardToast)
                    SettingsDivider()
                    SettingsPickerRow(
                        Text("Keep Clipboard History"),
                        selection: Binding(
                            get: { clipboardKeepDays },
                            set: { days in
                                clipboardKeepDays = days
                                ProductivityServices.shared.clipboard.setRetention(days: days)
                            }
                        )
                    ) {
                        Text("Forever").tag(0)
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                    }
                    SettingsNote(Text("Pinned items never expire. History is kept in memory only."))
                }
            } trailing: {
                SettingsCard(Text("Commands & Snippets")) {
                    SettingsEditorRow(
                        Text("Custom Commands"),
                        text: $customCommands,
                        placeholder: Text("One command per line: ;name = /path/to/script")
                    )
                    SettingsDivider()
                    SettingsEditorRow(
                        Text("Text Snippets"),
                        text: $snippets,
                        placeholder: Text("One per line: ;sig = Best regards, Sam. Type the trigger in ⌘Space and press Return to paste it.")
                    )
                    .onChange(of: snippets) { _, _ in KeyGuardService.shared.refreshSnippetTriggers() }
                    SettingsDivider()
                    SettingsToggleRow(
                        Text("Expand Snippets Anywhere"),
                        isOn: Binding(
                            get: { KeyGuardService.shared.isSnippetExpansionEnabled },
                            set: { on in
                                if on, !KeyGuardService.hasPermission { KeyGuardService.requestPermission() }
                                KeyGuardService.shared.setSnippetExpansion(on)
                            }
                        ),
                        info: String(localized: "Type a snippet's trigger and a space in any app to paste its text. It never runs in password fields, in password managers, or while the input is secure, and it needs the Input Monitoring and Accessibility permissions.")
                    )
                }
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
                    SettingsDivider()
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
                SettingsButtonRow(Text("Clear Unpinned")) { confirmShelfClear() }
                SettingsDivider()
                SettingsRow(Text("System Dock")) {
                    Button("Restore Dock") { AppDelegate.shared?.restoreNativeDock() }
                        .buttonStyle(SettingsGelButtonStyle())
                }
            }
            // 52c: the one place KatiKati writes into the user's Claude Code settings, so the warning
            // and the restart note sit on the switch itself rather than in a help popover.
            SettingsCard(Text("Claude Code Status")) {
                SettingsToggleRow(
                    Text("Track Turns with a Claude Hook"),
                    isOn: Binding(
                        get: { claudeHook },
                        set: { on in
                            do {
                                try ClaudeHookInstaller.setEnabled(on)
                                claudeHook = on
                                claudeHookFailed = false
                            } catch {
                                // An unreadable or invalid settings.json is left alone, so the switch stays put.
                                claudeHookFailed = true
                            }
                        }
                    ),
                    note: Text("Adds two hooks to ~/.claude/settings.json: one when a prompt is submitted, one when Claude stops. They append to a local log, so the notch shows ACTIVE while Claude Code works and IDLE as soon as it stops. Your other settings and hooks are kept, and the original file is backed up once. Restart Claude Code after changing this.")
                )
                if claudeHookFailed {
                    SettingsDivider()
                    SettingsNote(Text("Could not update ~/.claude/settings.json. Nothing was changed."))
                }
            }
        }
    }

    /// 55d: a bulk delete of shelf entries asks first. Single-item remove stays immediate; this one drops
    /// every unpinned entry at once.
    private func confirmShelfClear() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Clear Unpinned Shelf Items?")
        alert.informativeText = String(localized: "Unpinned entries leave the shelf and its own copies are deleted. Pinned items stay.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Clear Unpinned"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { AppDelegate.shared?.shelfStore.clear() }
    }
}

/// Phase 44b — the BitTorrent hub's policy: custom engine path, seeding limits and a throttled
/// upload window. Reads the same `com.katikati.torrent.*` keys the engine does, so a change lands
/// without relaunch; policy pushes live via `applyPolicy()`, a path change applies on next start.
struct TorrentSettingsBlock: View {
    @AppStorage(TorrentSettings.enginePathKey) private var enginePath = ""
    @AppStorage(TorrentSettings.seedRatioKey) private var seedRatio = 0.0
    @AppStorage(TorrentSettings.seedTimeMinutesKey) private var seedMinutes = 0
    @AppStorage(TorrentSettings.maxUploadKBpsKey) private var maxUploadKBps = 0
    @AppStorage(TorrentSettings.quietStartHourKey) private var quietStart = 0
    @AppStorage(TorrentSettings.quietEndHourKey) private var quietEnd = 0
    @AppStorage(TorrentSettings.quietUploadKBpsKey) private var quietUploadKBps = 0
    @State private var detectedPath: String? = nil

    var body: some View {
        SettingsCard(Text("BitTorrent")) {
            SettingsRow(Text("Engine Path"), note: Text(statusLine)) {
                HStack(spacing: 8) {
                    TextField("/opt/homebrew/bin/aria2c", text: $enginePath)
                        .textFieldStyle(.roundedBorder).frame(width: 220)
                    if !enginePath.isEmpty {
                        Button("Auto") { enginePath = "" }
                            .buttonStyle(SettingsGelButtonStyle())
                    }
                }
            }
            SettingsDivider()
                                SettingsStepperRow(
                        Text("Seed Ratio"),
                        value: $seedRatio,
                        in: 0...50,
                        step: 0.5,
                        readout: seedRatio == 0 ? "0 (stop)" : String(format: "%.1f", seedRatio)
                    )
            SettingsDivider()
                    SettingsStepperRow(
                        Text("Seed Minutes"),
                        value: Binding(get: { Double(seedMinutes) }, set: { seedMinutes = Int($0) }),
                        in: 0...1440,
                        step: 10,
                        readout: seedMinutes == 0 ? "0 (stop)" : "\(seedMinutes)m"
                    )
            SettingsDivider()
                                SettingsStepperRow(
                        Text("Max Upload"),
                        value: Binding(get: { Double(maxUploadKBps) }, set: { maxUploadKBps = Int($0) }),
                        in: 0...100_000,
                        step: 50,
                        readout: maxUploadKBps == 0 ? "Unlimited" : "\(maxUploadKBps) KB/s"
                    )
            SettingsDivider()
                    SettingsStepperRow(
                        Text("Quiet Upload"),
                        value: Binding(get: { Double(quietUploadKBps) }, set: { quietUploadKBps = Int($0) }),
                        in: 0...100_000,
                        step: 10,
                        readout: quietUploadKBps == 0 ? "Off" : "\(quietUploadKBps) KB/s",
                        note: Text("Equal hours disables the window. 0 stops sharing at completion.")
                    )
            SettingsDivider()
                                SettingsStepperRow(
                        Text("Quiet From"),
                        value: Binding(get: { Double(quietStart) }, set: { quietStart = Int($0) }),
                        in: 0...23,
                        step: 1,
                        readout: "\(quietStart):00"
                    )
            SettingsDivider()
                    SettingsStepperRow(
                        Text("Quiet Until"),
                        value: Binding(get: { Double(quietEnd) }, set: { quietEnd = Int($0) }),
                        in: 0...23,
                        step: 1,
                        readout: "\(quietEnd):00"
                    )
        }
        .onAppear { detectedPath = TorrentEngine.shared.resolvedBinaryPath }
        .onChange(of: seedRatio) { _ in pushPolicy() }
        .onChange(of: seedMinutes) { _ in pushPolicy() }
        .onChange(of: maxUploadKBps) { _ in pushPolicy() }
        .onChange(of: quietStart) { _ in pushPolicy() }
        .onChange(of: quietEnd) { _ in pushPolicy() }
        .onChange(of: quietUploadKBps) { _ in pushPolicy() }
    }

    private var statusLine: String {
        if !enginePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Custom path — applies on next start." }
        return detectedPath ?? "aria2c not found — install aria2 for magnet links."
    }

    private func pushPolicy() { Task { await TorrentEngine.shared.applyPolicy() } }
}

/// Phase 12 (2026-10-15) — the launcher's own rows (script commands, command hints, the file
/// index, the Spotlight hand-off), split out of `UtilitySettingsBlock` when the tools got their own
/// tab. The launcher and the Control Center share the Launcher page; these rows belong to neither
/// the clipboard nor the shelf.
struct LauncherSettingsBlock: View {
    @AppStorage(LauncherRunner.enabledKey) private var launcherScripts = false
    @AppStorage(FileIndexService.enabledKey) private var fastIndex = true

    var body: some View {
        SettingsCard(Text("Launcher")) {
            // Two switches (the command bar's hint switch moved to its own page, 2026-10-20).
            SettingsToggleRow(Text("Script Commands"), isOn: $launcherScripts)
            SettingsDivider()
            SettingsToggleRow(Text("Fast File Index"), isOn: $fastIndex)
            SettingsDivider()
            // Rule 4: the five steps used to be five notes under this button. They are the row's
            // ⓘ now. Each step stays a whole literal (rule 9) — they are joined, never assembled.
            SettingsButtonRow(
                Text("Replace Spotlight"),
                info: SpotlightHandoff.steps().map(spotlightStepText).joined(separator: "\n")
            ) {
                if let url = URL(string: SpotlightHandoff.settingsURL) { NSWorkspace.shared.open(url) }
            }
        }
    }

    private func spotlightStepText(_ step: SpotlightHandoff.Step) -> String {
        switch step {
        case .openKeyboard: return String(localized: "Open System Settings › Keyboard.")
        case .openShortcuts: return String(localized: "Click Keyboard Shortcuts….")
        case .selectSpotlight: return String(localized: "Select Spotlight in the list.")
        case .uncheckShowSearch: return String(localized: "Turn off Show Spotlight search.")
        case .testHere: return String(localized: "Come back and press ⌘Space to test.")
        }
    }
}

/// The command bar's own rows (2026-10-20): split out of `LauncherSettingsBlock` so the command
/// bar has a page of its own instead of riding on the launcher's.
struct CommandBarSettingsBlock: View {
    @AppStorage("com.katikati.commandbar.hints") private var commandHints = true

    var body: some View {
        SettingsCard(Text("Command Bar")) {
            SettingsToggleRow(Text("Show Command Hints"), isOn: $commandHints)
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
    @AppStorage(DailyHelpersService.hydrateKey) private var hydrate = false
    @AppStorage(DailyHelpersService.pauseKey) private var pauseReminder = false
    @AppStorage(TeleprompterModel.enabledKey) private var teleprompterPage = false
    @AppStorage(CameraMirrorService.enabledKey) private var cameraMirrorPage = false
    @AppStorage(NotificationMirrorService.enabledKey) private var notificationsPage = false
    @AppStorage(NotchEdgeStyle.sharpKey) private var sharpEdges = false

    var body: some View {
        SettingsCard(Text("Daily Helpers")) {
            SettingsRowPair(
                left: { SettingsToggleRow(Text("Hide from Screen Capture"), isOn: $hideFromCapture) },
                right: { SettingsToggleRow(Text("Caps Lock Indicator"), isOn: $capsLockHUD) }
            )
            SettingsDivider()
            SettingsRowPair(
                left: { SettingsToggleRow(Text("Charge Notices"), isOn: $batteryNudge) },
                right: { SettingsToggleRow(Text("Offer to Eject Drives"), isOn: $usbEject) }
            )
            SettingsDivider()
            SettingsToggleRow(Text("Camera and Mic Indicator"), isOn: $privacyDot)
            SettingsDivider()
            SettingsRowPair(
                left: { SettingsToggleRow(Text("Water Reminder"), isOn: $hydrate) },
                right: { SettingsToggleRow(Text("Break Reminder"), isOn: $pauseReminder) }
            )
            SettingsDivider()
            SettingsRow(Text("Teleprompter"), note: Text("Opens from ⌘Space (prompter). The window is hidden from screen recordings and shares.")) {
                Button("Open Teleprompter Window") { TeleprompterWindowController.shared.show() }
                    .buttonStyle(SettingsGelButtonStyle())
            }
            SettingsDivider()
            SettingsRowPair(
                left: { SettingsToggleRow(Text("Teleprompter Notch Page"), isOn: $teleprompterPage) },
                right: { SettingsToggleRow(Text("Camera Mirror Notch Page"), isOn: $cameraMirrorPage) }
            )
            SettingsDivider()
            SettingsToggleRow(Text("Notifications Notch Page"), isOn: $notificationsPage)
            SettingsDivider()
            SettingsToggleRow(Text("Sharp Notch Edges"), isOn: $sharpEdges)
        }
    }
}
