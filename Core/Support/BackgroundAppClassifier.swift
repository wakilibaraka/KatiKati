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

    static func isBackground(_ p: Process, _ c: Context) -> Bool {
        if p.bundleID.isEmpty || p.bundleID == c.selfBundleID || p.bundleID == finderID { return false }
        if c.keptIDs.contains(p.bundleID) || c.messagingIDs.contains(p.bundleID)
            || c.stashedIDs.contains(p.bundleID) || c.ignoredIDs.contains(p.bundleID) { return false }
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
