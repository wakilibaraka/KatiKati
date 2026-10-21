import Foundation

/// 53d: which apps may be quit when their last window closes. Empty by default — quitting can end in the
/// app's own save prompt, so the owner opts in per bundle ID and the service only acts on a window count
/// that went from "some" to "none".
struct QuitOnLastWindowPolicy: Equatable, Sendable {
    /// Never ours, whatever a stored list says: the Finder and KatiKati itself are system surfaces.
    static let alwaysIgnored: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.systemuiserver", "com.katikati.app",
    ]

    var bundleIDs: Set<String> = []

    func applies(to bundleID: String?) -> Bool {
        guard let id = bundleID, !Self.alwaysIgnored.contains(id) else { return false }
        return bundleIDs.contains(id)
    }

    /// Comma/whitespace separated, the same form the key-guard lists use. Empty means off.
    static func parse(_ raw: String) -> QuitOnLastWindowPolicy {
        QuitOnLastWindowPolicy(bundleIDs: Set(raw.split { $0 == "," || $0.isWhitespace }.map(String.init)))
    }

    /// True only for the transition the feature is named after: the app had a window and now has none.
    /// A launch with no window yet, an unknown read, or an app that never had one must never quit.
    static func shouldQuit(hadWindow: Bool, windowCount: Int?) -> Bool {
        guard let windowCount else { return false }
        return hadWindow && windowCount == 0
    }
}
