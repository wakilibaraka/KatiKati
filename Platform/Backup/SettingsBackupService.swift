import Foundation

/// Port plan #2b (2026-10-27): reads and writes the real `UserDefaults` and Application Support files for
/// Settings backup. What belongs in a backup and what a file may restore is decided by `SettingsBackup.swift`;
/// this type only does the I/O. Notes travel only inside a password-sealed envelope (`NotesBackupEnvelope`).
struct SettingsBackupService {
    struct RestoreSummary: Equatable {
        var defaultsWritten: Int
        var defaultsRemoved: Int
        var filesWritten: Int
        /// The automatic copy taken just before anything was changed.
        var safetyBackup: URL?
        var notesRestored = 0
    }

    /// The notes store, reduced to what backup needs (plaintext in, plaintext out), so the service does not
    /// depend on how notes are keyed or stored.
    struct NotesBridge {
        var exportPlaintext: () -> [Data]
        var importPlaintext: ([Data]) throws -> Int
        var iterations = NotesBackupEnvelope.defaultIterations
    }

    enum NotesError: Error, Equatable {
        /// Notes were asked for without a password.
        case passwordRequired
        case wrongPassword
        /// No notes store is wired (or the file's notes envelope is damaged).
        case unavailable
    }

    let defaults: UserDefaults
    /// The domain `defaults` persists to. Reads go through `persistentDomain(forName:)`, not
    /// `dictionaryRepresentation()`, which also returns every registered default (so a backup would
    /// carry values the person never set).
    let domainName: String
    /// Application Support/KatiKati: where `tasks.json` lives and where `Backups/` is created.
    let supportDirectory: URL
    let appVersion: String
    let notes: NotesBridge?
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, domainName: String? = nil, supportDirectory: URL, appVersion: String,
         notes: NotesBridge? = nil, now: @escaping () -> Date = Date.init) {
        self.notes = notes
        self.defaults = defaults
        self.domainName = domainName ?? Bundle.main.bundleIdentifier ?? ""
        self.supportDirectory = supportDirectory
        self.appVersion = appVersion
        self.now = now
    }

    var backupsDirectory: URL { supportDirectory.appendingPathComponent("Backups", isDirectory: true) }

    // MARK: - Export

    private func storedValues() -> [String: Any] {
        defaults.persistentDomain(forName: domainName) ?? [:]
    }

    func makeBackup(categories wanted: Set<BackupCategory>) -> SettingsBackupFile {
        let categories = BackupCategory.allCases.filter { wanted.contains($0) && $0 != .notes }
        var values: [String: BackupValue] = [:]
        let all = storedValues()
        for key in SettingsBackupKeys.keys(in: Set(categories), from: Array(all.keys)) {
            if let value = all[key].flatMap(BackupValue.init(propertyList:)) { values[key] = value }
        }
        var files: [String: Data] = [:]
        if categories.contains(.tasks), let data = try? Data(contentsOf: supportDirectory.appendingPathComponent("tasks.json")) {
            files["tasks.json"] = data
        }
        return SettingsBackupFile(appVersion: appVersion, created: now(), categories: categories, defaults: values, files: files)
    }

    /// Like `makeBackup(categories:)`, plus the notes sealed under `notesPassword` when `.notes` is ticked.
    /// Notes without a password are refused rather than left out silently.
    func makeBackup(categories wanted: Set<BackupCategory>, notesPassword: String?) throws -> SettingsBackupFile {
        var file = makeBackup(categories: wanted)
        guard wanted.contains(.notes) else { return file }
        guard let notes else { throw NotesError.unavailable }
        guard let notesPassword, !notesPassword.isEmpty else { throw NotesError.passwordRequired }
        let envelope = try NotesBackupEnvelope.seal(notes: notes.exportPlaintext(), password: notesPassword, iterations: notes.iterations)
        file.files[SettingsBackupFile.sealedNotesFileName] = envelope
        file.categories.append(.notes)
        file.notesPasswordProtected = true
        return file
    }

    func export(categories: Set<BackupCategory>, to url: URL, notesPassword: String? = nil) throws {
        try makeBackup(categories: categories, notesPassword: notesPassword).encoded().write(to: url, options: .atomic)
    }

    // MARK: - Restore

    /// Overwrites the ticked categories with the file's contents. A copy of the current state goes to
    /// `Backups/` first, so a restore can always be undone. Keys of a restored category that the file does
    /// not hold are removed, so the result matches the backup rather than a blend of the two.
    @discardableResult
    func restore(_ file: SettingsBackupFile, categories wanted: Set<BackupCategory>,
                 notesPassword: String? = nil) throws -> RestoreSummary {
        let categories = wanted.intersection(file.categories).subtracting([.notes])
        let incoming = file.restorableDefaults(categories: categories)
        // Notes never go to disk as files: they are opened here and re-saved through the notes store.
        let incomingFiles = file.restorableFiles(categories: categories).filter { !$0.key.hasPrefix("Notes/") }

        // Opened first, so a wrong password stops everything before a single setting has changed.
        var noteDocuments: [Data]?
        if wanted.contains(.notes), file.categories.contains(.notes),
           let envelope = file.files[SettingsBackupFile.sealedNotesFileName] {
            guard notes != nil else { throw NotesError.unavailable }
            guard let notesPassword, !notesPassword.isEmpty else { throw NotesError.passwordRequired }
            do {
                noteDocuments = try NotesBackupEnvelope.open(envelope, password: notesPassword)
            } catch NotesBackupEnvelope.EnvelopeError.wrongPassword {
                throw NotesError.wrongPassword
            } catch {
                throw NotesError.unavailable
            }
        }
        var safetyCategories = categories
        if noteDocuments != nil { safetyCategories.insert(.notes) }
        let safety = try writeSafetyBackup(categories: safetyCategories, notesPassword: notesPassword)

        var removed = 0
        let existing = Array(storedValues().keys)
        for key in SettingsBackupKeys.keys(in: categories, from: existing) where incoming[key] == nil {
            defaults.removeObject(forKey: key)
            removed += 1
        }
        for (key, value) in incoming { defaults.set(value.propertyList, forKey: key) }

        for (name, data) in incomingFiles {
            let target = supportDirectory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        }
        var notesRestored = 0
        if let noteDocuments, let notes { notesRestored = try notes.importPlaintext(noteDocuments) }
        return RestoreSummary(defaultsWritten: incoming.count, defaultsRemoved: removed,
                              filesWritten: incomingFiles.count, safetyBackup: safety, notesRestored: notesRestored)
    }

    func restore(from url: URL, categories: Set<BackupCategory>, notesPassword: String? = nil) throws -> RestoreSummary {
        try restore(SettingsBackupFile.decode(Data(contentsOf: url)), categories: categories, notesPassword: notesPassword)
    }

    private func writeSafetyBackup(categories: Set<BackupCategory>, notesPassword: String?) throws -> URL {
        try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        let stamp = Self.stampFormatter.string(from: now())
        let url = backupsDirectory.appendingPathComponent("Before restore \(stamp).katikati")
        try makeBackup(categories: categories, notesPassword: notesPassword).encoded().write(to: url, options: .atomic)
        return url
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f
    }()
}
