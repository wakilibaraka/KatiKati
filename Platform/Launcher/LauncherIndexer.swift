import AppKit
import Foundation

/// Finds installed apps: an instant directory scan for the first paint, then a live Spotlight query that picks up
/// installs and removals. Lazy: nothing runs until the launcher first asks (`start`), and `stop` tears it down.
@MainActor
final class LauncherIndexer: ObservableObject {
    @Published private(set) var apps: [LauncherApp] = []
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []

    static let roots: [String] = [
        "/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
    ]

    func start() {
        guard query == nil else { return }
        apps = LauncherAppIndex.merged(Self.scanDirectories())
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
        let merged = LauncherAppIndex.merged(found)
        if !merged.isEmpty, merged != apps { apps = merged }
    }

    nonisolated static func scanDirectories() -> [LauncherApp] {
        var out: [LauncherApp] = []
        for root in roots {
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])) ?? []
            for url in urls where url.pathExtension == "app" {
                if let app = app(at: url, added: nil) { out.append(app) }
            }
        }
        return out
    }

    nonisolated static func app(at url: URL, added: Date?) -> LauncherApp? {
        guard url.pathExtension == "app", let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        // Background-only helpers (no Dock presence) are not launchable apps.
        if bundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true
            || bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool == true { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        let date = added ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        return LauncherApp(bundleID: id, name: name, path: url.path, installedAt: date)
    }
}
