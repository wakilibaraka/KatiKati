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
            SettingsBentoSplit {
                SettingsCard(Text("Clipboard")) {
                    // Cleaning copied links is a clipboard job, so it opens this card rather than
                    // sitting in a headerless card of its own. One line with the field it feeds
                    // (2026-10-18): the label and its 220 pt field are 370 pt, half the card is 414.
                    SettingsRowPair(
                        left: {
                            SettingsToggleRow(
                                Text("Clean Copied Links"),
                                isOn: Binding(get: { store.linkCleanerEnabled }, set: { store.setLinkCleanerEnabled($0) })
                            )
                        },
                        right: {
                            SettingsRow(Text("Ignore Patterns")) {
                                TextField("Ignore Patterns", text: $clipboardIgnorePatterns)
                                    .textFieldStyle(.roundedBorder).frame(width: 220)
                            }
                        }
                    )
                    SettingsDivider()
                    SettingsRowPair(
                        left: { SettingsToggleRow(Text("Copy Sounds"), isOn: $clipboardSounds) },
                        right: { SettingsToggleRow(Text("Copy Notifications"), isOn: $clipboardToast) }
                    )
                }
            } trailing: {
                // The two editors are one section, not two (`Docs/SETTINGS.md` rule 5's three-section
                // budget): they are the same kind of thing, and the page was one card over it.
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
                }
            }
            SettingsCard(Text("Shelf")) {
                    SettingsRowPair(
                        left: {
                            SettingsToggleRow(
                                Text("Shake to Shelf"),
                                isOn: Binding(get: { store.shelfShakeEnabled }, set: { store.setShelfShakeEnabled($0) })
                            )
                        },
                        right: {
                            SettingsToggleRow(
                                Text("Auto-Expire"),
                                isOn: Binding(get: { store.shelfAutoExpire }, set: { store.setShelfAutoExpire($0) })
                            )
                        }
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
                    // The storage picker and the clear button, one line (2026-10-18).
                    SettingsRowPair(
                        left: {
                            SettingsRow(Text("Storage")) {
                                Picker("Storage", selection: Binding(get: { store.shelfStorage }, set: { store.setShelfStorage($0) })) {
                                    Text("References").tag(ShelfStorage.reference)
                                    Text("Copies").tag(ShelfStorage.copy)
                                }
                                .labelsHidden().pickerStyle(.menu).fixedSize()
                            }
                        },
                        right: {
                            SettingsButtonRow(Text("Clear Unpinned")) { AppDelegate.shared?.shelfStore.clear() }
                        }
                    )
                    SettingsDivider()
                    SettingsRow(Text("System Dock")) {
                        Button("Restore Dock") { AppDelegate.shared?.restoreNativeDock() }
                            .buttonStyle(SettingsGelButtonStyle())
                    }
                }
        }
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
    @AppStorage("com.katikati.commandbar.hints") private var commandHints = true
    @AppStorage(FileIndexService.enabledKey) private var fastIndex = true

    var body: some View {
        SettingsCard(Text("Launcher")) {
            // Three switches, two on the first line (`Docs/SETTINGS.md` rule 5).
            SettingsRowPair(
                left: { SettingsToggleRow(Text("Script Commands"), isOn: $launcherScripts) },
                right: { SettingsToggleRow(Text("Show Command Hints"), isOn: $commandHints) }
            )
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

/// Phase 12 — the helpers that surface in the notch (indicators, notices, teleprompter page), split
/// out of `UtilitySettingsBlock` so the Notch page owns them.
struct NotchHelpersSettingsBlock: View {
    @AppStorage(DailyHelpersService.hideFromCaptureKey) private var hideFromCapture = false
    @AppStorage(DailyHelpersService.capsLockKey) private var capsLockHUD = false
    @AppStorage(DailyHelpersService.batteryKey) private var batteryNudge = false
    @AppStorage(DailyHelpersService.ejectKey) private var usbEject = false
    @AppStorage(DailyHelpersService.privacyKey) private var privacyDot = false
    @AppStorage(TeleprompterModel.enabledKey) private var teleprompterPage = false
    @AppStorage(CameraMirrorService.enabledKey) private var cameraMirrorPage = false
    @AppStorage(NotificationMirrorService.enabledKey) private var notificationsPage = false

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
        }
    }
}
