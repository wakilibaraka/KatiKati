import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Port plan #2c (2026-10-27): the Settings card for backup and restore. Everything the file holds and
/// every safety rule lives in `SettingsBackupService`; this view only asks where to save or open, and
/// reports the result. Notes are included only when asked for, and then only under a password the person
/// chooses (`NotesBackupEnvelope`).
struct BackupSettingsBlock: View {
    private struct Report: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let restartOffered: Bool
    }

    @State private var report: Report?
    @State private var includeNotes = false

    /// Settings, shortcuts, bar, launcher and tasks: what a person expects "my setup" to mean.
    private static let categories: Set<BackupCategory> = [.settingsAndShortcuts, .barAndLauncher, .tasks]

    private static var fileType: UTType { UTType(filenameExtension: "katikati") ?? .json }

    var body: some View {
        SettingsCard(Text("Backup")) {
            SettingsButtonRow(
                Text("Back Up Settings…"),
                note: Text("Saves your settings, shortcuts, bar layout and tasks to one file.")
            ) { backUp() }
            SettingsDivider()
            SettingsToggleRow(
                Text("Include Notes"),
                isOn: $includeNotes,
                note: Text("Protected by a password you choose. You need it to restore the notes.")
            )
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

    private func service(withNotes: Bool = false) throws -> SettingsBackupService {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let info = Bundle.main.infoDictionary
        return SettingsBackupService(
            supportDirectory: base.appendingPathComponent("KatiKati", isDirectory: true),
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "unknown",
            notes: withNotes ? notesBridge() : nil)
    }

    /// A second handle on the same notes files, with the same key file the Notes tile uses. The Notes tile
    /// keeps its notes in memory, so restored notes show up after the restart that is offered afterwards.
    private func notesBridge() -> SettingsBackupService.NotesBridge? {
        let directory = NotesStore.defaultDirectory()
        let keys = FileNoteKeyProvider(
            keyFile: FileNoteKeyProvider.defaultKeyFile(),
            legacy: KeychainNoteKeyProvider(),
            hasExistingNotes: { FileNoteKeyProvider.directoryHasNotes(directory) })
        guard let store = try? NotesStore(directory: directory, keyProvider: keys) else { return nil }
        return SettingsBackupService.NotesBridge(
            exportPlaintext: { store.exportPlaintext() },
            importPlaintext: { try store.importPlaintext($0) })
    }

    /// A password sheet. With `confirm`, asks twice and reports a mismatch itself; nil means cancelled or rejected.
    private func askPassword(message: String, confirm: Bool) -> String? {
        let alert = NSAlert()
        alert.messageText = String(localized: "Password for Notes")
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let first = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        first.placeholderString = String(localized: "Password")
        var fields = [first]
        if confirm {
            let second = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
            second.placeholderString = String(localized: "Repeat Password")
            fields.append(second)
        }
        let stack = NSStackView(views: fields)
        stack.orientation = .vertical
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 240, height: CGFloat(fields.count) * 24 + CGFloat(fields.count - 1) * 8)
        alert.accessoryView = stack
        alert.window.initialFirstResponder = first
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let password = first.stringValue
        if confirm {
            guard !password.isEmpty else {
                report = Report(title: String(localized: "Password for Notes"), message: String(localized: "Enter a password."), restartOffered: false)
                return nil
            }
            guard fields[1].stringValue == password else {
                report = Report(title: String(localized: "Password for Notes"), message: String(localized: "The passwords do not match."), restartOffered: false)
                return nil
            }
        }
        return password
    }

    private func backUp() {
        NSApp.activate(ignoringOtherApps: true)
        var notesPassword: String?
        if includeNotes {
            guard let password = askPassword(message: String(localized: "Choose a password to protect your notes in this backup."), confirm: true) else { return }
            notesPassword = password
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.fileType]
        panel.nameFieldStringValue = "KatiKati Backup \(Self.dayStamp()).katikati"
        panel.prompt = String(localized: "Save")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let categories = includeNotes ? Self.categories.union([.notes]) : Self.categories
            try service(withNotes: includeNotes).export(categories: categories, to: url, notesPassword: notesPassword)
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
            let file = try SettingsBackupFile.decode(Data(contentsOf: url))
            var notesPassword: String?
            var categories = Self.categories
            if file.categories.contains(.notes) {
                guard let password = askPassword(message: String(localized: "Enter the password you chose when you backed up your notes."), confirm: false) else { return }
                notesPassword = password
                categories.insert(.notes)
            }
            try service(withNotes: categories.contains(.notes)).restore(file, categories: categories, notesPassword: notesPassword)
            report = Report(
                title: String(localized: "Settings Restored"),
                message: String(localized: "Your previous settings were saved to the Backups folder first. Restart KatiKati to finish applying the restored ones."),
                restartOffered: true)
        } catch SettingsBackupService.NotesError.wrongPassword {
            report = Report(title: String(localized: "Restore Failed"),
                            message: String(localized: "The password is wrong, so nothing was restored."), restartOffered: false)
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
