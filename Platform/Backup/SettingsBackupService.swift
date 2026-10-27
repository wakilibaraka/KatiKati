import Foundation

/// Port plan #2b (2026-10-27): reads and writes the real `UserDefaults` and Application Support files for
/// Settings backup. What belongs in a backup and what a file may restore is decided by `SettingsBackup.swift`;
/// this type only does the I/O. Notes are not handled here (slice 2d adds them with a password).
struct SettingsBackupService {
    struct RestoreSummary: Equatable {
        var defaultsWritten: Int
        var defaultsRemoved: Int
        var filesWritten: Int
        /// The automatic copy taken just before anything was changed.
        var safetyBackup: URL?
    }

    let defaults: UserDefaults
    /// The domain `defaults` persists to. Reads go through `persistentDomain(forName:)`, not
    /// `dictionaryRepresentation()`, which also returns every registered default (so a backup would
    /// carry values the person never set).
    let domainName: String
    /// Application Support/KatiKati: where `tasks.json` lives and where `Backups/` is created.
    let supportDirectory: URL
    let appVersion: String
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, domainName: String? = nil, supportDirectory: URL, appVersion: String,
         now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.domainName = domainName ?? Bundle.main.bundleIdentifier ?? ""
        self.supportDirectory = supportDirectory
        self.appVersion = appVersion
        self.now = now
    }

    var backupsDirectory: URL { supportDirectory.appendingPathComponent("Backups", isDirectory: true) }

    // MARK: - Export

    /// A backup of the ticked categories as they are now. `.notes` is ignored until slice 2d.
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

    func export(categories: Set<BackupCategory>, to url: URL) throws {
        try makeBackup(categories: categories).encoded().write(to: url, options: .atomic)
    }

    // MARK: - Restore

    /// Overwrites the ticked categories with the file's contents. A copy of the current state goes to
    /// `Backups/` first, so a restore can always be undone. Keys of a restored category that the file does
    /// not hold are removed, so the result matches the backup rather than a blend of the two.
    @discardableResult
    func restore(_ file: SettingsBackupFile, categories wanted: Set<BackupCategory>) throws -> RestoreSummary {
        let categories = wanted.intersection(file.categories).subtracting([.notes])
        let incoming = file.restorableDefaults(categories: categories)
        let incomingFiles = file.restorableFiles(categories: categories)
        let safety = try writeSafetyBackup(categories: categories)

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
        return RestoreSummary(defaultsWritten: incoming.count, defaultsRemoved: removed,
                              filesWritten: incomingFiles.count, safetyBackup: safety)
    }

    func restore(from url: URL, categories: Set<BackupCategory>) throws -> RestoreSummary {
        try restore(SettingsBackupFile.decode(Data(contentsOf: url)), categories: categories)
    }

    private func writeSafetyBackup(categories: Set<BackupCategory>) throws -> URL {
        try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        let stamp = Self.stampFormatter.string(from: now())
        let url = backupsDirectory.appendingPathComponent("Before restore \(stamp).katikati")
        try makeBackup(categories: categories).encoded().write(to: url, options: .atomic)
        return url
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f
    }()
}
