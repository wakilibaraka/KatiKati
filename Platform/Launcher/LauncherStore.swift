import Foundation

/// Launch counts and pins, `launcher.json` in Application Support/KatiKati. A file that fails to decode is moved
/// aside as `.bak` rather than overwritten.
struct LauncherState: Equatable, Codable {
    var usage: [String: LauncherUsage] = [:]
    var pinned: [String] = []
    /// Apps the user hid from the grid (still found by search).
    var hidden: [String] = []
    /// The user's own All Apps order (see `LauncherOrdering`); empty = alphabetical.
    var order: [String] = []
    /// Phase 13i: user folders in All Apps.
    var folders: [LauncherFolder] = []

    init(usage: [String: LauncherUsage] = [:], pinned: [String] = [], hidden: [String] = [], order: [String] = [],
         folders: [LauncherFolder] = []) {
        self.usage = usage
        self.pinned = pinned
        self.hidden = hidden
        self.order = order
        self.folders = folders
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        usage = try c.decodeIfPresent([String: LauncherUsage].self, forKey: .usage) ?? [:]
        pinned = try c.decodeIfPresent([String].self, forKey: .pinned) ?? []
        hidden = try c.decodeIfPresent([String].self, forKey: .hidden) ?? []
        order = try c.decodeIfPresent([String].self, forKey: .order) ?? []
        folders = try c.decodeIfPresent([LauncherFolder].self, forKey: .folders) ?? []
    }
}

struct LauncherStore {
    let url: URL

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("KatiKati/launcher.json")
    }

    func load() -> LauncherState {
        guard let data = try? Data(contentsOf: url) else { return LauncherState() }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(LauncherState.self, from: data)
        } catch {
            try? FileManager.default.removeItem(at: url.appendingPathExtension("bak"))
            try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("bak"))
            return LauncherState()
        }
    }

    func save(_ state: LauncherState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}
