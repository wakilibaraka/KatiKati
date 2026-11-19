import CoreGraphics
import Foundation

/// Keys and bounded defaults for the unified desktop search (Phase 66A–B).
enum DesktopSearchConfig {
    static let excludedPathsKey = "com.katikati.desktop.searchExcludedPaths"
    static let resultLimitKey = "com.katikati.desktop.searchResultLimit"
    static let historyKey = "com.katikati.desktop.search.history"
    static let favoritesKey = "com.katikati.desktop.search.favorites"

    static let defaultResultLimit = 40
    static let resultLimitRange = 10...120
    static let historyLimit = 12
    static let favoritesLimit = 24

    static func clampedResultLimit(_ value: Int) -> Int {
        min(max(value, resultLimitRange.lowerBound), resultLimitRange.upperBound)
    }

    static func resultLimit(defaults: UserDefaults = .standard) -> Int {
        let raw = defaults.object(forKey: resultLimitKey) as? Int ?? defaultResultLimit
        return clampedResultLimit(raw)
    }

    /// One path per line; blank lines and `#` comments are ignored.
    static func excludedPaths(defaults: UserDefaults = .standard) -> [String] {
        guard let raw = defaults.string(forKey: excludedPathsKey) else { return [] }
        return raw.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    static func encodedExcludedPaths(_ paths: [String]) -> String {
        paths.joined(separator: "\n")
    }
}

/// Where a unified search row came from.
enum DesktopSearchProvider: String, Codable, CaseIterable, Sendable {
    case app
    case setting
    case note
    case todo
    case file

    /// Ordering weight when scores tie; apps and settings are deliberate targets, files are long-tail.
    var priority: Int {
        switch self {
        case .app: return 5
        case .setting: return 4
        case .todo: return 3
        case .note: return 2
        case .file: return 1
        }
    }
}

/// One row in the unified desktop search.
struct DesktopSearchResult: Identifiable, Equatable, Codable, Sendable {
    let id: String
    var provider: DesktopSearchProvider
    var title: String
    var subtitle: String
    var path: String?
    /// Provider-specific handle: bundle ID, setting raw value, note ID or task UUID.
    var payload: String?
    var symbol: String

    init(
        id: String,
        provider: DesktopSearchProvider,
        title: String,
        subtitle: String,
        path: String? = nil,
        payload: String? = nil,
        symbol: String
    ) {
        self.id = id
        self.provider = provider
        self.title = title
        self.subtitle = subtitle
        self.path = path
        self.payload = payload
        self.symbol = symbol
    }
}

/// Excludes caches, system trees, build products and user-listed paths from Spotlight results.
struct SearchPathFilter: Equatable, Sendable {
    static let builtInExcludedPrefixes: [String] = [
        "/System", "/usr", "/bin", "/sbin", "/dev", "/cores",
        "/private/var", "/private/tmp", "/private/etc",
        "/Library/Caches", "/Library/Logs", "/Library/Developer",
        "~/Library/Caches", "~/Library/Logs", "~/Library/Developer",
        "~/Library/Containers", "~/Library/Group Containers",
        "~/Library/Application Support/CrashReporter",
        "~/Library/Application Support/Code/Cache",
        "~/Library/Application Support/Code/CachedData"
    ]

    static let builtInExcludedComponents: Set<String> = [
        ".git", ".build", ".swiftpm", "node_modules", "DerivedData", ".Trash", ".Spotlight-V100"
    ]

    let excludedPrefixes: [String]
    let excludedComponents: Set<String>

    init(userExcludedPaths: [String] = []) {
        let home = NSHomeDirectory()
        func normalize(_ raw: String) -> String? {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let expanded = (trimmed as NSString).expandingTildeInPath
            let absolute = expanded.hasPrefix("/") ? expanded : "\(home)/\(expanded)"
            var path = (absolute as NSString).standardizingPath
            while path.count > 1, path.hasSuffix("/") { path.removeLast() }
            return path
        }
        var prefixes = Self.builtInExcludedPrefixes.compactMap(normalize)
        prefixes += userExcludedPaths.compactMap(normalize)
        excludedPrefixes = Array(Set(prefixes)).sorted()
        excludedComponents = Self.builtInExcludedComponents
    }

    func allows(_ rawPath: String) -> Bool {
        let path = (rawPath as NSString).standardizingPath
        guard !path.isEmpty else { return false }
        for prefix in excludedPrefixes {
            if path == prefix || path.hasPrefix(prefix + "/") { return false }
        }
        let components = path.split(separator: "/").map(String.init)
        return !components.contains { excludedComponents.contains($0) }
    }

    func filtering(_ entries: [FileEntry]) -> [FileEntry] {
        entries.filter { allows($0.path) }
    }
}

/// Recent queries, newest first, de-duplicated case-insensitively and bounded.
struct DesktopSearchHistory: Codable, Equatable, Sendable {
    var queries: [String] = []

    init(queries: [String] = []) {
        self.queries = Array(queries.prefix(DesktopSearchConfig.historyLimit))
    }

    func recording(_ rawQuery: String) -> DesktopSearchHistory {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return self }
        var next = queries.filter { $0.caseInsensitiveCompare(query) != .orderedSame }
        next.insert(query, at: 0)
        return DesktopSearchHistory(queries: Array(next.prefix(DesktopSearchConfig.historyLimit)))
    }

    static func decode(_ raw: String?) -> DesktopSearchHistory {
        guard let data = raw?.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(DesktopSearchHistory.self, from: data)
        else { return DesktopSearchHistory() }
        return decoded
    }

    func encoded() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// A pinned search row. The whole result is stored so a favorite still works after reindexing.
struct DesktopSearchFavorite: Codable, Equatable, Identifiable, Sendable {
    var result: DesktopSearchResult
    var id: String { result.id }
}

struct DesktopSearchFavorites: Codable, Equatable, Sendable {
    var items: [DesktopSearchFavorite] = []

    init(items: [DesktopSearchFavorite] = []) {
        self.items = Array(items.prefix(DesktopSearchConfig.favoritesLimit))
    }

    func contains(_ id: String) -> Bool {
        items.contains { $0.result.id == id }
    }

    func toggling(_ result: DesktopSearchResult) -> DesktopSearchFavorites {
        var next = items
        if let index = next.firstIndex(where: { $0.result.id == result.id }) {
            next.remove(at: index)
        } else {
            next.insert(DesktopSearchFavorite(result: result), at: 0)
        }
        return DesktopSearchFavorites(items: Array(next.prefix(DesktopSearchConfig.favoritesLimit)))
    }

    static func decode(_ raw: String?) -> DesktopSearchFavorites {
        guard let data = raw?.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(DesktopSearchFavorites.self, from: data)
        else { return DesktopSearchFavorites() }
        return decoded
    }

    func encoded() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Ranking for the merged provider rows: fuzzy title match, provider priority and path/body fallback.
enum DesktopSearchRanker {
    static func rank(
        _ results: [DesktopSearchResult],
        query: String,
        limit: Int = DesktopSearchConfig.defaultResultLimit
    ) -> [DesktopSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        let unique = results.filter { seen.insert($0.id).inserted }
        guard !trimmed.isEmpty else { return Array(unique.prefix(max(0, limit))) }

        let scored: [(DesktopSearchResult, Int)] = unique.compactMap { result in
            let title = LauncherMatch.score(query: trimmed, name: result.title)
                ?? LauncherMatch.score(query: trimmed, name: result.subtitle)
            let path = result.path.flatMap { LauncherMatch.score(query: trimmed, name: $0) }.map { $0 - 200 }
            guard let base = [title, path].compactMap({ $0 }).max() else { return nil }
            return (result, base + result.provider.priority * 10)
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                if lhs.0.provider != rhs.0.provider { return lhs.0.provider.priority > rhs.0.provider.priority }
                return lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
            }
            .prefix(max(0, limit))
            .map(\.0)
    }
}

/// ⌘-toggle and ⇧-range selection shared by the results list and the batch action bar.
struct DesktopSearchSelectionModel: Equatable, Sendable {
    private(set) var selectedIDs: Set<String> = []
    private(set) var anchorID: String?

    init(selectedIDs: Set<String> = [], anchorID: String? = nil) {
        self.selectedIDs = selectedIDs
        self.anchorID = anchorID
    }

    func isSelected(_ id: String) -> Bool { selectedIDs.contains(id) }

    mutating func replace(_ ids: Set<String>) {
        selectedIDs = ids
        anchorID = ids.count == 1 ? ids.first : nil
    }

    mutating func clear() {
        selectedIDs = []
        anchorID = nil
    }

    mutating func toggle(_ id: String, in orderedIDs: [String]) {
        guard orderedIDs.contains(id) else { return }
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        anchorID = id
    }

    mutating func selectRange(to id: String, in orderedIDs: [String]) {
        guard let end = orderedIDs.firstIndex(of: id) else { return }
        let start = anchorID.flatMap { orderedIDs.firstIndex(of: $0) } ?? end
        let bounds = min(start, end)...max(start, end)
        selectedIDs.formUnion(orderedIDs[bounds])
        anchorID = orderedIDs[start]
    }

    /// Rubber-band: every row whose frame intersects the selection rectangle.
    mutating func rubberBand(_ rect: CGRect, rowFrames: [String: CGRect], additive: Bool) {
        let hits = Set(rowFrames.filter { $0.value.intersects(rect) }.map(\.key))
        selectedIDs = additive ? selectedIDs.union(hits) : hits
        anchorID = hits.count == 1 ? hits.first : nil
    }
}

/// Batch operations over a selection of search rows.
enum DesktopSearchBatchAction: String, CaseIterable, Sendable {
    case open
    case reveal
    case copy
    case moveToBox
    case trash

    var requiresConfirmation: Bool { self == .trash }

    /// Whole localized labels live in the view; the planner only decides availability.
    static func available(for results: [DesktopSearchResult]) -> [DesktopSearchBatchAction] {
        guard !results.isEmpty else { return [] }
        let hasPath = results.contains { $0.path != nil }
        let hasOpenable = results.contains { result in
            switch result.provider {
            case .app, .setting, .file: return result.path != nil || result.payload != nil
            case .note, .todo: return false
            }
        }
        var actions: [DesktopSearchBatchAction] = []
        if hasOpenable { actions.append(.open) }
        if hasPath { actions.append(.reveal) }
        actions.append(.copy)
        if hasPath { actions.append(.moveToBox) }
        if hasPath { actions.append(.trash) }
        return actions
    }

    static func filePaths(in results: [DesktopSearchResult]) -> [String] {
        results.filter { $0.provider == .file }.compactMap(\.path)
    }

    /// Copy puts one item verbatim on the clipboard, a list as newline-separated paths.
    static func clipboardText(for results: [DesktopSearchResult]) -> String? {
        let values = results.compactMap { $0.path ?? $0.title }
        guard !values.isEmpty else { return nil }
        return values.joined(separator: "\n")
    }
}
