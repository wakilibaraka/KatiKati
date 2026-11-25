import Foundation

/// Phase 20a — decides which running apps belong in the Background Apps drawer: running apps with no window to
/// switch to (menu-bar apps, and regular apps that are hidden or have closed their windows). Pure; the app layer
/// feeds it process facts.
enum BackgroundAppClassifier {
    enum Policy: Sendable { case regular, accessory, prohibited }

    struct Process: Equatable, Sendable {
        var bundleID: String
        var policy: Policy
        var hasWindows: Bool
        var isHidden: Bool
        /// Lives inside another app's bundle (…app/Contents/…/X.app) or is named like a helper — a worker, not an app.
        var isHelper: Bool = false
    }

    struct Context: Equatable, Sendable {
        var selfBundleID: String = ""
        var keptIDs: Set<String> = []
        var messagingIDs: Set<String> = []
        var stashedIDs: Set<String> = []
        var ignoredIDs: Set<String> = []
        var showSystemHelpers = false
    }

    static let finderID = "com.apple.finder"

    /// Nested bundle (`Foo.app/Contents/.../Bar.app`) or a name ending in Helper / Updater / Agent / Service.
    static func looksLikeHelper(bundlePath: String?, name: String?) -> Bool {
        if let path = bundlePath, path.components(separatedBy: ".app/").count > 2 { return true }
        let n = (name ?? "").lowercased()
        return ["helper", "updater", "agent", "service", "daemon"].contains { n.hasSuffix($0) }
    }

    static func isBackground(_ p: Process, _ c: Context) -> Bool {
        if p.bundleID.isEmpty || p.bundleID == c.selfBundleID || p.bundleID == finderID { return false }
        if c.keptIDs.contains(p.bundleID) || c.messagingIDs.contains(p.bundleID)
            || c.stashedIDs.contains(p.bundleID) || c.ignoredIDs.contains(p.bundleID) { return false }
        if p.isHelper && !c.showSystemHelpers { return false }
        switch p.policy {
        case .prohibited:
            return false
        case .accessory:
            return c.showSystemHelpers || !p.bundleID.hasPrefix("com.apple.")
        case .regular:
            return !p.hasWindows || p.isHidden
        }
    }

    /// Background bundle ids, stable-sorted (case-insensitive) so the drawer doesn't reshuffle.
    static func background(_ processes: [Process], _ context: Context) -> [String] {
        Array(Set(processes.filter { isBackground($0, context) }.map(\.bundleID)))
            .sorted { $0.lowercased() < $1.lowercased() }
    }
}

// MARK: - Control Centre's Background Apps deck

/// What the deck presents as a person's own background activity. Window state is intentionally not
/// consulted: the deck opens without it, so the readable signal is the kind of process.
/// Prohibited processes and Apple accessory apps are OS machinery — loginwindow, WindowManager,
/// MenuBarAgent, Wallpaper — and are never offered as the user's apps. Third-party menu-bar apps
/// and regular apps are; nested helpers already fail `looksLikeHelper`.
enum BackgroundActivity {
    struct Item: Equatable, Sendable {
        var bundleID: String
        var name: String
        var policy: BackgroundAppClassifier.Policy
        var isHelper: Bool
    }

    static func belongs(_ item: Item) -> Bool {
        // Nested workers can slip past `looksLikeHelper` when the bundle name carries a suffix
        // (`Google Chrome Helper (Aperitif)`), so the deck also treats a helper name as a worker.
        let isWorker = item.isHelper || item.name.lowercased().contains("helper")
        guard !item.bundleID.isEmpty, item.bundleID != BackgroundAppClassifier.finderID,
              !isWorker else { return false }
        switch item.policy {
        case .prohibited: return false
        case .accessory: return !item.bundleID.hasPrefix("com.apple.")
        case .regular: return true
        }
    }

    /// Filtered, stably sorted (name, then id) and capped so the deck stays a glance, not a task list.
    static func visible(_ items: [Item], limit: Int = 10) -> [Item] {
        Array(items.filter(belongs).sorted {
            let a = $0.name.lowercased(), b = $1.name.lowercased()
            return a == b ? $0.bundleID.lowercased() < $1.bundleID.lowercased() : a < b
        }.prefix(limit))
    }

    /// The monogram fallback, in the panel's own type: initials for multi-word names, the first
    /// letter otherwise, and the bundle id's last component only when there is no name at all.
    static func monogram(for name: String, bundleID: String) -> String {
        let words = name.split { $0.isWhitespace || $0 == "-" }.map(String.init)
        let letters: String
        if words.count >= 2 {
            letters = String(words[0].prefix(1)) + String(words[1].prefix(1))
        } else if let word = words.first {
            letters = String(word.prefix(1))
        } else {
            letters = String(bundleID.split(separator: ".").last?.prefix(1) ?? "?")
        }
        return letters.uppercased()
    }
}
