import AppKit
import Foundation

/// Finds installed apps: an instant directory scan for the first paint, then a live Spotlight query that picks up
/// installs and removals. Lazy: nothing runs until the launcher first asks (`start`), and `stop` tears it down.
@MainActor
final class LauncherIndexer: ObservableObject {
    @Published private(set) var apps: [LauncherApp] = []
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var scanTask: Task<Void, Never>?

    static let roots: [String] = [
        "/Applications", "/System/Applications", "/System/Library/CoreServices/Applications",
        NSHomeDirectory() + "/Applications",
    ]

    func start() {
        guard query == nil else { return }
        scanTask = Task.detached(priority: .utility) { [weak self] in
            let found = Self.scanDirectories()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.query != nil else { return }
                self.merge(found)
            }
        }
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "kMDItemContentType == 'com.apple.application-bundle'")
        q.searchScopes = Self.roots
        let names: [Notification.Name] = [.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: q, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.absorb() }
            }
        }
        query = q
        q.start()
    }

    func stop() {
        scanTask?.cancel()
        scanTask = nil
        query?.stop()
        query = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    private func absorb() {
        guard let q = query else { return }
        q.disableUpdates()
        defer { q.enableUpdates() }
        var found: [LauncherApp] = []
        for case let item as NSMetadataItem in q.results {
            guard let path = item.value(forAttribute: kMDItemPath as String) as? String,
                  let app = Self.app(at: URL(fileURLWithPath: path), added: item.value(forAttribute: "kMDItemDateAdded") as? Date)
            else { continue }
            found.append(app)
        }
        merge(found)
    }

    private func merge(_ found: [LauncherApp]) {
        let existing = apps.filter { FileManager.default.fileExists(atPath: $0.path) }
        let merged = LauncherAppIndex.merged(existing + found)
        if merged != apps { apps = merged }
    }

    nonisolated static func scanDirectories(roots: [String] = roots) -> [LauncherApp] {
        var out: [LauncherApp] = []
        for root in roots {
            guard let urls = FileManager.default.enumerator(
                at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in urls where url.pathExtension.lowercased() == "app" {
                urls.skipDescendants()
                if let app = app(at: url, added: nil) { out.append(app) }
            }
        }
        return out
    }

    nonisolated static func app(at url: URL, added: Date?) -> LauncherApp? {
        guard url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        // Menu-bar apps can be launched even when they do not have a Dock icon.
        if bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool == true { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        let date = added ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        let category = bundle.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String ?? ""
        return LauncherApp(bundleID: id, name: name, path: url.path, installedAt: date, category: category)
    }
}
