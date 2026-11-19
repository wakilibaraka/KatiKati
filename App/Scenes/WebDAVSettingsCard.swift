import SwiftUI

/// Phase 67A–C: scheduled WebDAV backup and restore. Credentials are written to the Keychain by
/// `WebDAVBackupService`; the password field never round-trips through `UserDefaults`.
struct WebDAVSettingsCard: View {
    @ObservedObject private var service = WebDAVBackupService.shared
    @State private var password = ""
    @State private var localMessage: String?

    private var settings: WebDAVSyncSettings { service.settings }

    private var scheduleBinding: Binding<String> {
        Binding(
            get: { settings.schedule.rawValue },
            set: { raw in
                guard let schedule = WebDAVSchedule(rawValue: raw) else { return }
                var next = settings
                next.schedule = schedule
                service.settings = next
            }
        )
    }

    private var restoreModeBinding: Binding<String> {
        Binding(
            get: { settings.restoreMode.rawValue },
            set: { raw in
                guard let mode = WebDAVRestoreMode(rawValue: raw) else { return }
                var next = settings
                next.restoreMode = mode
                service.settings = next
            }
        )
    }

    private func domainBinding(_ domain: WebDAVSyncDomain) -> Binding<Bool> {
        Binding(
            get: { settings.enabledDomains.contains(domain) },
            set: { enabled in
                var next = settings
                if enabled { next.enabledDomains.insert(domain) } else { next.enabledDomains.remove(domain) }
                service.settings = next
            }
        )
    }

    private var deviceBinding: Binding<String> {
        Binding(
            get: { settings.deviceName },
            set: { name in
                var next = settings
                next.deviceName = name
                service.settings = next
            }
        )
    }

    private var remoteRootBinding: Binding<String> {
        Binding(
            get: { settings.remoteRoot },
            set: { root in
                var next = settings
                next.remoteRoot = root
                service.settings = next
            }
        )
    }

    var body: some View {
        SettingsCard(Text("WebDAV Sync")) {
            SettingsRow(Text("Server")) {
                TextField("Server", text: $service.serverURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 230)
            }
            SettingsDivider()
            SettingsRow(Text("User Name")) {
                TextField("User Name", text: $service.username)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 230)
            }
            SettingsDivider()
            SettingsRow(
                Text("Password"),
                note: Text("Kept in the macOS Keychain, never in KatiKati's settings.")
            ) {
                HStack(spacing: 8) {
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                    Button(String(localized: "Save")) {
                        do {
                            try service.savePassword(password)
                            password = ""
                            localMessage = String(localized: "Password saved in the Keychain.")
                        } catch {
                            localMessage = error.localizedDescription
                        }
                    }
                    .disabled(password.isEmpty || service.serverURL.isEmpty)
                }
            }
            SettingsDivider()
            SettingsRow(Text("Remote Folder")) {
                TextField("Remote Folder", text: remoteRootBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 230)
            }
            SettingsDivider()
            SettingsRow(Text("This Mac")) {
                TextField("This Mac", text: deviceBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 230)
            }
            SettingsDivider()
            SettingsPickerRow(Text("Schedule"), selection: scheduleBinding) {
                Text("Off").tag(WebDAVSchedule.off.rawValue)
                Text("Daily").tag(WebDAVSchedule.daily.rawValue)
                Text("Weekly").tag(WebDAVSchedule.weekly.rawValue)
            }
            SettingsDivider()
            SettingsPickerRow(
                Text("Restore Mode"),
                selection: restoreModeBinding,
                note: Text("Merge keeps local items the server does not have. Snapshot-Faithful replaces the selected parts with the server's copy.")
            ) {
                Text("Merge").tag(WebDAVRestoreMode.merge.rawValue)
                Text("Snapshot-Faithful").tag(WebDAVRestoreMode.snapshotFaithful.rawValue)
            }
            SettingsDivider()
            ForEach(WebDAVSyncDomain.allCases, id: \.self) { domain in
                SettingsToggleRow(Text(verbatim: domain.displayName), isOn: domainBinding(domain))
                if domain != WebDAVSyncDomain.allCases.last { SettingsDivider() }
            }
            SettingsDivider()
            SettingsButtonRow(
                Text("Test Connection"),
                note: Text("Checks the server address and saved password.")
            ) {
                localMessage = nil
                Task { await service.testConnection() }
            }
            SettingsDivider()
            SettingsButtonRow(Text("Back Up to WebDAV Now")) {
                localMessage = nil
                Task { await service.backupNow() }
            }
            SettingsDivider()
            SettingsButtonRow(
                Text("Restore from WebDAV…"),
                note: Text("Takes a local safety backup first. Restart KatiKati afterwards to apply restored settings.")
            ) {
                localMessage = nil
                Task { await service.restoreNow() }
            }
            if let statusText {
                SettingsDivider()
                SettingsNote(Text(verbatim: statusText))
            }
        }
    }

    private var statusText: String? {
        if let localMessage { return localMessage }
        switch service.status {
        case .idle: return nil
        case .checking: return String(localized: "Checking the connection…")
        case .backingUp: return String(localized: "Backing up to WebDAV…")
        case .restoring: return String(localized: "Restoring from WebDAV…")
        case .success(let message), .failure(let message): return message
        }
    }
}
