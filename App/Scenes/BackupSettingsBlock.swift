import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Port plan #2c (2026-10-27): the Settings card for backup and restore. Everything the file holds and
/// every safety rule lives in `SettingsBackupService`; this view only asks where to save or open, and
/// reports the result. Notes are not offered until slice 2d adds the password step.
struct BackupSettingsBlock: View {
    private struct Report: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let restartOffered: Bool
    }

    @State private var report: Report?

    /// Settings, shortcuts, bar, launcher and tasks: what a person expects "my setup" to mean.
    private static let categories: Set<BackupCategory> = [.settingsAndShortcuts, .barAndLauncher, .tasks]

    private static var fileType: UTType { UTType(filenameExtension: "katikati") ?? .json }

    var body: some View {
        SettingsCard(Text("Backup")) {
            SettingsButtonRow(
                Text("Back Up Settings…"),
                note: Text("Saves your settings, shortcuts, bar layout and tasks to one file. Notes are not included.")
            ) { backUp() }
            SettingsDivider()
            SettingsButtonRow(Text("Restore from Backup…")) { restore() }
        }
        .alert(item: $report) { report in
            if report.restartOffered {
                return Alert(
                    title: Text(report.title),
                    message: Text(report.message),
                    primaryButton: .default(Text("Restart"), action: Self.relaunch),
                    secondaryButton: .cancel(Text("Later"))
                )
            }
            return Alert(title: Text(report.title), message: Text(report.message), dismissButton: .default(Text("OK")))
        }
    }

    private func service() throws -> SettingsBackupService {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let info = Bundle.main.infoDictionary
        return SettingsBackupService(
            supportDirectory: base.appendingPathComponent("KatiKati", isDirectory: true),
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "unknown")
    }

    private func backUp() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.fileType]
        panel.nameFieldStringValue = "KatiKati Backup \(Self.dayStamp()).katikati"
        panel.prompt = String(localized: "Save")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try service().export(categories: Self.categories, to: url)
        } catch {
            report = Report(title: String(localized: "Backup Failed"), message: error.localizedDescription, restartOffered: false)
        }
    }

    private func restore() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.fileType]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose a KatiKati backup to restore")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try service().restore(from: url, categories: Self.categories)
            report = Report(
                title: String(localized: "Settings Restored"),
                message: String(localized: "Your previous settings were saved to the Backups folder first. Restart KatiKati to finish applying the restored ones."),
                restartOffered: true)
        } catch SettingsBackupFile.DecodeError.notABackup {
            report = Report(title: String(localized: "Restore Failed"),
                            message: String(localized: "That file is not a KatiKati backup."), restartOffered: false)
        } catch SettingsBackupFile.DecodeError.newerFormat {
            report = Report(title: String(localized: "Restore Failed"),
                            message: String(localized: "This backup was made by a newer version of KatiKati. Update KatiKati and try again."),
                            restartOffered: false)
        } catch {
            report = Report(title: String(localized: "Restore Failed"), message: error.localizedDescription, restartOffered: false)
        }
    }

    private static func dayStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Same relaunch as the language switch and Reset All Settings: wait for this process to exit, then open the bundle.
    private static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", Bundle.main.bundleURL.path]
        try? process.run()
        NSApp.terminate(nil)
    }
}
