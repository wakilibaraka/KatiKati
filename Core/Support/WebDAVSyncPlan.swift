import Foundation

/// Which slice of local state a scheduled WebDAV sync carries.
enum WebDAVSyncDomain: String, CaseIterable, Codable, Hashable, Sendable {
    case desktopBoxesAndStyles
    case todos
    case quickCaptureAndNotes
    case settingsAndShortcuts

    var remoteFileName: String {
        switch self {
        case .desktopBoxesAndStyles: return "desktop.json"
        case .todos: return "todos.json"
        case .quickCaptureAndNotes: return "capture.json"
        case .settingsAndShortcuts: return "settings.json"
        }
    }

    /// The defaults families this domain owns locally (settings uses the backup classifier instead).
    var defaultsPrefixes: [String] {
        switch self {
        case .desktopBoxesAndStyles: return ["com.katikati.desktop."]
        case .todos, .quickCaptureAndNotes: return []
        case .settingsAndShortcuts: return ["com.katikati."]
        }
    }
}

enum WebDAVRestoreMode: String, CaseIterable, Codable, Sendable {
    /// Incoming rows win on conflicts; local-only rows and keys are kept.
    case merge
    /// Local domain data is replaced by the remote snapshot (after a safety backup).
    case snapshotFaithful
}

enum WebDAVSchedule: String, CaseIterable, Codable, Sendable {
    case off
    case daily
    case weekly

    var interval: TimeInterval? {
        switch self {
        case .off: return nil
        case .daily: return 24 * 60 * 60
        case .weekly: return 7 * 24 * 60 * 60
        }
    }
}

enum WebDAVSyncKeys {
    static let prefix = "com.katikati.backup.webdav."
    static let serverURL = prefix + "serverURL"
    static let remoteRoot = prefix + "remoteRoot"
    static let username = prefix + "username"
    static let deviceName = prefix + "deviceName"
    static let enabledDomains = prefix + "enabledDomains"
    static let restoreMode = prefix + "restoreMode"
    static let schedule = prefix + "schedule"
    static let lastRun = prefix + "lastRun"
    static let defaultRemoteRoot = "/KatiKatiSync"
}

struct WebDAVSyncSettings: Codable, Equatable, Sendable {
    var enabledDomains: Set<WebDAVSyncDomain>
    var restoreMode: WebDAVRestoreMode
    var deviceName: String
    var remoteRoot: String
    var schedule: WebDAVSchedule

    static func defaults(
        deviceName: String = ProcessInfo.processInfo.hostName,
        remoteRoot: String = WebDAVSyncKeys.defaultRemoteRoot
    ) -> WebDAVSyncSettings {
        WebDAVSyncSettings(
            enabledDomains: Set(WebDAVSyncDomain.allCases),
            restoreMode: .merge,
            deviceName: deviceName,
            remoteRoot: remoteRoot,
            schedule: .off
        )
    }

    static func load(defaults: UserDefaults = .standard) -> WebDAVSyncSettings {
        var settings = WebDAVSyncSettings.defaults(
            deviceName: defaults.string(forKey: WebDAVSyncKeys.deviceName) ?? ProcessInfo.processInfo.hostName,
            remoteRoot: defaults.string(forKey: WebDAVSyncKeys.remoteRoot) ?? WebDAVSyncKeys.defaultRemoteRoot
        )
        if let raw = defaults.string(forKey: WebDAVSyncKeys.enabledDomains) {
            let domains = raw.split(separator: ",").compactMap {
                WebDAVSyncDomain(rawValue: String($0).trimmingCharacters(in: .whitespaces))
            }
            settings.enabledDomains = Set(domains)
        }
        if let raw = defaults.string(forKey: WebDAVSyncKeys.restoreMode),
           let mode = WebDAVRestoreMode(rawValue: raw) {
            settings.restoreMode = mode
        }
        if let raw = defaults.string(forKey: WebDAVSyncKeys.schedule),
           let schedule = WebDAVSchedule(rawValue: raw) {
            settings.schedule = schedule
        }
        return settings
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(remoteRoot, forKey: WebDAVSyncKeys.remoteRoot)
        defaults.set(deviceName, forKey: WebDAVSyncKeys.deviceName)
        defaults.set(enabledDomains.map(\.rawValue).sorted().joined(separator: ","), forKey: WebDAVSyncKeys.enabledDomains)
        defaults.set(restoreMode.rawValue, forKey: WebDAVSyncKeys.restoreMode)
        defaults.set(schedule.rawValue, forKey: WebDAVSyncKeys.schedule)
    }
}

/// The upload/restore file map for one device. Pure so remote paths and domain selection are testable.
struct WebDAVSyncPlan: Equatable, Sendable {
    struct Item: Equatable, Sendable {
        let domain: WebDAVSyncDomain
        let remotePath: String
    }

    let deviceSlug: String
    let remoteRoot: String
    let items: [Item]

    var manifestPath: String { WebDAVSyncPlanner.join(remoteRoot, deviceSlug, "manifest.json") }

    static func upload(_ settings: WebDAVSyncSettings) -> WebDAVSyncPlan {
        let slug = WebDAVSyncPlanner.deviceSlug(settings.deviceName)
        let root = WebDAVSyncPlanner.normalizedRoot(settings.remoteRoot)
        let items = WebDAVSyncDomain.allCases
            .filter { settings.enabledDomains.contains($0) }
            .map { domain in
                Item(
                    domain: domain,
                    remotePath: WebDAVSyncPlanner.join(root, slug, domain.remoteFileName)
                )
            }
        return WebDAVSyncPlan(deviceSlug: slug, remoteRoot: root, items: items)
    }

    /// Same domain map; the service skips items the server does not offer.
    static func restore(_ settings: WebDAVSyncSettings) -> WebDAVSyncPlan {
        upload(settings)
    }
}

/// One domain's uploaded payload: file bytes plus the defaults that belong to it.
struct WebDAVSyncEnvelope: Codable, Equatable, Sendable {
    static let currentSchema = 1

    var schema: Int
    var domain: WebDAVSyncDomain
    var deviceName: String
    var homeDirectory: String
    var savedAt: Date
    /// File name relative to Application Support/KatiKati (e.g. `desktop-boxes.json`, `Notes/<id>.note`).
    var files: [String: Data]
    /// Defaults values for this domain, already filtered to `WebDAVSyncDomain.defaultsPrefixes`.
    var defaults: [String: BackupValue]

    init(
        domain: WebDAVSyncDomain,
        deviceName: String,
        homeDirectory: String = NSHomeDirectory(),
        savedAt: Date = Date(),
        files: [String: Data] = [:],
        defaults: [String: BackupValue] = [:]
    ) {
        self.schema = Self.currentSchema
        self.domain = domain
        self.deviceName = deviceName
        self.homeDirectory = homeDirectory
        self.savedAt = savedAt
        self.files = files
        self.defaults = defaults
    }
}

struct WebDAVSyncManifest: Codable, Equatable, Sendable {
    var schema: Int
    var deviceName: String
    var homeDirectory: String
    var savedAt: Date
    var domains: [WebDAVSyncDomain]
}

enum WebDAVSyncPlanner {
    /// Safe remote directory name for this Mac.
    static func deviceSlug(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = name.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }
        let slug = cleaned.joined()
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
            .lowercased()
        return slug.isEmpty ? "mac" : String(slug.prefix(64))
    }

    static func normalizedRoot(_ raw: String) -> String {
        var root = raw.trimmingCharacters(in: .whitespaces)
        if !root.hasPrefix("/") { root = "/" + root }
        while root.count > 1, root.hasSuffix("/") { root.removeLast() }
        return root
    }

    static func join(_ components: String...) -> String {
        var path = ""
        for component in components {
            let trimmed = component.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !trimmed.isEmpty else { continue }
            path += "/" + trimmed
        }
        return path.isEmpty ? "/" : path
    }

    /// Merge an array of identified objects (`id` key): local rows win, remote-only rows are appended.
    static func mergeIdentifiedJSON(local: Data?, remote: Data) -> Data? {
        guard let local,
              let localArray = try? JSONSerialization.jsonObject(with: local) as? [Any],
              let remoteArray = try? JSONSerialization.jsonObject(with: remote) as? [Any]
        else { return remote }
        var seen = Set<String>()
        var merged: [Any] = []
        for row in localArray {
            if let id = identifier(row) { seen.insert(id) }
            merged.append(row)
        }
        for row in remoteArray {
            if let id = identifier(row) {
                if seen.contains(id) { continue }
                seen.insert(id)
            }
            merged.append(row)
        }
        return try? JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    static func identifier(_ row: Any) -> String? {
        guard let dict = row as? [String: Any] else { return nil }
        if let id = dict["id"] as? String { return id }
        if let id = dict["id"] as? UUID { return id.uuidString }
        return nil
    }

    /// Merge defaults maps with incoming values winning; local-only keys survive.
    static func mergeDefaults(
        local: [String: BackupValue],
        remote: [String: BackupValue]
    ) -> [String: BackupValue] {
        var merged = local
        for (key, value) in remote { merged[key] = value }
        return merged
    }

    /// Rewrites every JSON string that sits under the sending Mac's home directory to this Mac's home.
    /// Used for Desktop Box `backingPath` values and pinned folder paths.
    static func remapHomePaths(in data: Data, from oldHome: String, to newHome: String) -> Data? {
        let old = oldHome.hasSuffix("/") ? String(oldHome.dropLast()) : oldHome
        let new = newHome.hasSuffix("/") ? String(newHome.dropLast()) : newHome
        guard !old.isEmpty, old != new else { return data }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return data }
        let remapped = remap(object, oldHome: old, newHome: new)
        return try? JSONSerialization.data(withJSONObject: remapped, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private static func remap(_ object: Any, oldHome: String, newHome: String) -> Any {
        switch object {
        case let string as String:
            if string == oldHome { return newHome }
            if string.hasPrefix(oldHome + "/") { return newHome + string.dropFirst(oldHome.count) }
            return string
        case let array as [Any]:
            return array.map { remap($0, oldHome: oldHome, newHome: newHome) }
        case let dict as [String: Any]:
            return dict.mapValues { remap($0, oldHome: oldHome, newHome: newHome) }
        default:
            return object
        }
    }

    /// Snapshot-faithful restore replaces the file; merge combines identified `items`/`entries` arrays
    /// inside the app's object-shaped task and capture files as well as legacy top-level arrays.
    static func mergedFileData(
        local: Data?,
        remote: Data,
        mode: WebDAVRestoreMode
    ) -> Data? {
        switch mode {
        case .snapshotFaithful:
            return remote
        case .merge:
            if let local,
               let localObject = try? JSONSerialization.jsonObject(with: local),
               let remoteObject = try? JSONSerialization.jsonObject(with: remote) {
                if localObject is [Any] {
                return mergeIdentifiedJSON(local: local, remote: remote)
                }
                if let localDictionary = localObject as? [String: Any],
                   let remoteDictionary = remoteObject as? [String: Any] {
                    return try? JSONSerialization.data(withJSONObject: mergeObjects(localDictionary, remoteDictionary), options: [.sortedKeys, .withoutEscapingSlashes])
                }
            }
            return remote
        }
    }

    private static func mergeObjects(_ local: [String: Any], _ remote: [String: Any]) -> [String: Any] {
        var merged = local
        for (key, incoming) in remote {
            guard let existing = merged[key] else { merged[key] = incoming; continue }
            if ["items", "entries"].contains(key), existing is [Any], incoming is [Any],
               let localData = try? JSONSerialization.data(withJSONObject: existing),
               let remoteData = try? JSONSerialization.data(withJSONObject: incoming),
               let rows = mergeIdentifiedJSON(local: localData, remote: remoteData),
               let decoded = try? JSONSerialization.jsonObject(with: rows) {
                merged[key] = decoded
            } else if let localChild = existing as? [String: Any], let remoteChild = incoming as? [String: Any] {
                merged[key] = mergeObjects(localChild, remoteChild)
            } else {
                merged[key] = incoming
            }
        }
        return merged
    }
}
