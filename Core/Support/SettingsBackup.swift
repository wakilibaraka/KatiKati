import Foundation

/// Port plan #2a (2026-10-27): the pure half of Settings backup and restore. A backup is one JSON file
/// (`.katikati`) holding the ticked categories. This file decides which `UserDefaults` keys belong to
/// which category and what a backup file looks like; reading and writing the real defaults and files is
/// the service in slice 2b. No AppKit, no I/O.
///
/// Classification is by key family rather than a hand-kept list of ~260 literals, because KatiKati
/// scatters `com.katikati.*` keys across dozens of files. The safety comes from two things instead:
/// an explicit exclusion list (stamps, caches, anything secret-shaped), and tests that pin the families.

enum BackupCategory: String, CaseIterable, Codable, Sendable {
    /// Every `com.katikati.*` preference that is not bar or launcher layout: appearance, notch, edge decks,
    /// shortcuts, command bar, weather, tools.
    case settingsAndShortcuts
    /// What is on the bar and in the launcher: kept apps and their order, pinned folders, drawer, messaging
    /// apps, layout, widgets arrangement, launcher look and order.
    case barAndLauncher
    /// `tasks.json` in Application Support/KatiKati.
    case tasks
    /// The encrypted notes folder. Only ever exported together with a password (slice 2d); without one the
    /// category is left out.
    case notes

    var includesDefaults: Bool { self == .settingsAndShortcuts || self == .barAndLauncher }
}

enum SettingsBackupKeys {
    static let prefix = "com.katikati."

    /// Unprefixed keys that predate the `com.katikati.` convention. They hold the bar's contents.
    static let legacyBarKeys: Set<String> = [
        "keptAppBundleIDsV3", "stripKeptAppOrderV1", "pinnedFolderPaths", "pinnedFolderSortOrders",
        "drawerBundleIDs", "drawerDisplayOrder", "messagingBundleIDsV2", "messagingOptOutBundleIDsV2",
    ]

    /// `com.katikati.` families that describe the bar and launcher.
    static let barPrefixes: [String] = [
        "com.katikati.layout.", "com.katikati.launcher.", "com.katikati.widgets.", "com.katikati.chips.",
        "com.katikati.strip.", "com.katikati.drawer.", "com.katikati.dock.", "com.katikati.dockPanelHeight",
        "com.katikati.dockSize", "com.katikati.hoverStyle", "com.katikati.taskbarScreen.",
    ]

    /// Never backed up: one-shot stamps and seeds (restoring them would suppress a migration or a first-run
    /// step that the other Mac still needs), the welcome flag, and per-machine state.
    static let excludedPrefixes: [String] = [
        "com.katikati.migration.", "com.katikati.hasSeenWelcome", "com.katikati.startup.",
        "com.katikati.launchAtLogin", "com.katikati.screentime.", "com.katikati.weather.cache",
    ]

    /// A key whose name says it holds a credential is never exported, whatever family it is in.
    static let secretMarkers: [String] = ["token", "password", "secret", "apikey", "credential", "license"]

    /// Suffixes of one-shot flags, wherever they live.
    static let excludedSuffixes: [String] = [".stamp", ".seeded", ".seedPending", ".pending", ".lastRun", ".lastSeen"]

    static func isExcluded(_ key: String) -> Bool {
        let lower = key.lowercased()
        if secretMarkers.contains(where: { lower.contains($0) }) { return true }
        if excludedPrefixes.contains(where: { key.hasPrefix($0) }) { return true }
        if excludedSuffixes.contains(where: { key.hasSuffix($0) }) { return true }
        if key.hasSuffix("Seeded") || key.hasSuffix("SeededV1") { return true }
        return false
    }

    /// The category a defaults key belongs to, or nil when it is not ours or is excluded.
    static func category(of key: String) -> BackupCategory? {
        if isExcluded(key) { return nil }
        if legacyBarKeys.contains(key) { return .barAndLauncher }
        guard key.hasPrefix(prefix) else { return nil }
        if barPrefixes.contains(where: { key.hasPrefix($0) }) { return .barAndLauncher }
        return .settingsAndShortcuts
    }

    /// Keys from `allKeys` that a backup of `categories` includes.
    static func keys(in categories: Set<BackupCategory>, from allKeys: [String]) -> [String] {
        allKeys.filter { key in category(of: key).map(categories.contains) ?? false }.sorted()
    }
}

/// A property-list value in a form JSON can carry without losing its type (JSON alone would turn an
/// integer into a double and a `Data` into nothing).
enum BackupValue: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case bool(Bool)
    case date(Date)
    case data(Data)
    case array([BackupValue])
    case dictionary([String: BackupValue])

    private enum CodingKeys: String, CodingKey { case type, value }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let v): try c.encode("string", forKey: .type); try c.encode(v, forKey: .value)
        case .integer(let v): try c.encode("integer", forKey: .type); try c.encode(v, forKey: .value)
        case .double(let v): try c.encode("double", forKey: .type); try c.encode(v, forKey: .value)
        case .bool(let v): try c.encode("bool", forKey: .type); try c.encode(v, forKey: .value)
        case .date(let v): try c.encode("date", forKey: .type); try c.encode(v.timeIntervalSinceReferenceDate, forKey: .value)
        case .data(let v): try c.encode("data", forKey: .type); try c.encode(v, forKey: .value)
        case .array(let v): try c.encode("array", forKey: .type); try c.encode(v, forKey: .value)
        case .dictionary(let v): try c.encode("dictionary", forKey: .type); try c.encode(v, forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "string": self = .string(try c.decode(String.self, forKey: .value))
        case "integer": self = .integer(try c.decode(Int.self, forKey: .value))
        case "double": self = .double(try c.decode(Double.self, forKey: .value))
        case "bool": self = .bool(try c.decode(Bool.self, forKey: .value))
        case "date": self = .date(Date(timeIntervalSinceReferenceDate: try c.decode(Double.self, forKey: .value)))
        case "data": self = .data(try c.decode(Data.self, forKey: .value))
        case "array": self = .array(try c.decode([BackupValue].self, forKey: .value))
        case "dictionary": self = .dictionary(try c.decode([String: BackupValue].self, forKey: .value))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown value type")
        }
    }

    /// From a `UserDefaults` object; nil for types a property list cannot hold or that we do not back up.
    init?(propertyList value: Any) {
        switch value {
        case let v as Bool where CFGetTypeID(v as CFTypeRef) == CFBooleanGetTypeID(): self = .bool(v)
        case let v as Int: self = .integer(v)
        case let v as Double: self = .double(v)
        case let v as String: self = .string(v)
        case let v as Date: self = .date(v)
        case let v as Data: self = .data(v)
        case let v as [Any]:
            let items = v.compactMap(BackupValue.init(propertyList:))
            guard items.count == v.count else { return nil }
            self = .array(items)
        case let v as [String: Any]:
            var out: [String: BackupValue] = [:]
            for (k, item) in v {
                guard let converted = BackupValue(propertyList: item) else { return nil }
                out[k] = converted
            }
            self = .dictionary(out)
        default: return nil
        }
    }

    /// Back to the object `UserDefaults.set(_:forKey:)` takes.
    var propertyList: Any {
        switch self {
        case .string(let v): return v
        case .integer(let v): return v
        case .double(let v): return v
        case .bool(let v): return v
        case .date(let v): return v
        case .data(let v): return v
        case .array(let v): return v.map(\.propertyList)
        case .dictionary(let v): return v.mapValues(\.propertyList)
        }
    }
}

/// The `.katikati` file.
struct SettingsBackupFile: Codable, Equatable, Sendable {
    static let currentFormat = 1

    var format: Int
    var appVersion: String
    var created: Date
    var categories: [BackupCategory]
    var defaults: [String: BackupValue]
    /// Files by name relative to Application Support/KatiKati (`tasks.json`), bytes inline.
    var files: [String: Data]
    /// Set when the notes category is present: the notes were re-encrypted under the backup password
    /// (slice 2d), so `files` holds ciphertext that only that password opens.
    var notesPasswordProtected: Bool

    init(appVersion: String, created: Date = Date(), categories: [BackupCategory],
         defaults: [String: BackupValue] = [:], files: [String: Data] = [:], notesPasswordProtected: Bool = false) {
        self.format = Self.currentFormat
        self.appVersion = appVersion
        self.created = created
        self.categories = categories
        self.defaults = defaults
        self.files = files
        self.notesPasswordProtected = notesPasswordProtected
    }

    enum DecodeError: Error, Equatable {
        case notABackup
        /// Written by a newer build than this one; restoring could drop settings it does not know.
        case newerFormat(Int)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> SettingsBackupFile {
        struct Probe: Decodable { var format: Int }
        guard let probe = try? JSONDecoder().decode(Probe.self, from: data) else { throw DecodeError.notABackup }
        guard probe.format <= currentFormat else { throw DecodeError.newerFormat(probe.format) }
        guard let file = try? JSONDecoder().decode(SettingsBackupFile.self, from: data) else { throw DecodeError.notABackup }
        return file
    }

    /// What restoring this file would write, limited to the categories the user ticked. Keys that are not
    /// ours or are excluded are dropped even if the file carries them (a hand-edited or hostile file).
    func restorableDefaults(categories wanted: Set<BackupCategory>) -> [String: BackupValue] {
        defaults.filter { key, _ in
            guard let category = SettingsBackupKeys.category(of: key) else { return false }
            return wanted.contains(category) && categories.contains(category)
        }
    }

    /// Files restricted to ticked categories and to plain names inside the app folder: no path separators,
    /// no `..`, so a crafted file cannot write elsewhere.
    func restorableFiles(categories wanted: Set<BackupCategory>) -> [String: Data] {
        files.filter { name, _ in
            guard Self.isSafeFileName(name), let category = Self.category(ofFile: name) else { return false }
            return wanted.contains(category) && categories.contains(category)
        }
    }

    /// The password-sealed notes envelope (`NotesBackupEnvelope`). It is never written to disk as a file:
    /// the service opens it and re-saves each note through the notes store.
    static let sealedNotesFileName = "Notes/notes.sealed"

    /// `note.key` is deliberately not a category: a backup must never be able to replace the key that
    /// protects the notes already on this Mac.
    static func category(ofFile name: String) -> BackupCategory? {
        if name == "tasks.json" { return .tasks }
        if name.hasPrefix("Notes/") { return .notes }
        return nil
    }

    static func isSafeFileName(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\") else { return false }
        return !name.split(separator: "/", omittingEmptySubsequences: false).contains { $0.isEmpty || $0 == ".." || $0 == "." }
    }
}
