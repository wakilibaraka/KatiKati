import Foundation

/// Phase 30k: owns the in-memory filename index. Built in the background on first use and refreshed
/// lazily while enabled; nothing runs at idle.
@MainActor
final class FileIndexService {
    static let shared = FileIndexService()
    static let enabledKey = "com.katikati.index.enabled"

    private var index = FileIndex()
    private var isBuilding = false
    private var lastBuild: Date?
    private(set) var isReady = false

    private init() {}

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) == nil || UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// Ask for a build if none exists or it is stale. Cheap to call on each summon.
    func prepare() {
        guard Self.isEnabled, !isBuilding else { return }
        if isReady, let last = lastBuild, Date().timeIntervalSince(last) < 120 { return }
        isBuilding = true
        Task.detached(priority: .utility) {
            let entries = DirectoryScanner.scan()
            await MainActor.run {
                self.index.rebuild(entries)
                self.isReady = true
                self.lastBuild = Date()
                self.isBuilding = false
            }
        }
    }

    /// Indexed matches, or nil when the index is not ready (the caller then uses Spotlight).
    func search(terms: [String], extensions: [String], imageOnly: Bool, limit: Int = 40) -> [FileEntry]? {
        guard isReady else { return nil }
        var results = index.search(terms, limit: limit * 4)
        if imageOnly {
            results = results.filter { FileIndex.imageExtensions.contains(($0.path as NSString).pathExtension.lowercased()) }
        }
        if !extensions.isEmpty {
            let set = Set(extensions.map { $0.lowercased() })
            results = results.filter { set.contains(($0.path as NSString).pathExtension.lowercased()) }
        }
        return results.prefix(limit).map { FileEntry(path: $0.path, name: $0.name) }
    }
}
