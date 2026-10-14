import Foundation

/// Rules for determining whether a window should float or be managed by the tiling engine (Phase 26b).
struct TilingPolicy: Equatable, Sendable, Codable {
    /// Bundle identifiers that are exempted from automatic tiling.
    var floatingBundleIDs: Set<String>

    /// Default bundle identifiers for utility and transient panels that should float.
    static let defaultFloatingBundleIDs: Set<String> = [
        "com.apple.systempreferences",
        "com.apple.calculator",
        "com.apple.archiveutility",
        "com.apple.QuickTimePlayerX",
        "com.apple.ActivityMonitor",
        "com.apple.DiskUtility"
    ]

    init(floatingBundleIDs: Set<String> = defaultFloatingBundleIDs) {
        self.floatingBundleIDs = floatingBundleIDs
    }

    /// Whether a window with the given bundle identifier should remain floating.
    func shouldFloat(bundleIdentifier: String?) -> Bool {
        guard let id = bundleIdentifier, !id.isEmpty else { return false }
        return floatingBundleIDs.contains(id)
    }

    /// Serializes the floating bundle ID set into a newline-separated string for Settings editing.
    var serializedPatterns: String {
        floatingBundleIDs.sorted().joined(separator: "\n")
    }

    /// Parses a newline-separated list of bundle identifiers.
    static func parse(patterns: String) -> TilingPolicy {
        let lines = patterns.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return TilingPolicy(floatingBundleIDs: Set(lines))
    }
}
