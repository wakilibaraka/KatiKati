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

    /// Apps tiled even after the user moves them by hand (they snap back into the layout).
    var alwaysTileBundleIDs: Set<String> = []
    /// Bundle identifier → display name the app's windows are tiled on.
    var pinnedDisplays: [String: String] = [:]

    init(
        floatingBundleIDs: Set<String> = defaultFloatingBundleIDs,
        alwaysTileBundleIDs: Set<String> = [],
        pinnedDisplays: [String: String] = [:]
    ) {
        self.floatingBundleIDs = floatingBundleIDs
        self.alwaysTileBundleIDs = alwaysTileBundleIDs
        self.pinnedDisplays = pinnedDisplays
    }

    func alwaysTiles(bundleIdentifier: String?) -> Bool {
        bundleIdentifier.map(alwaysTileBundleIDs.contains) ?? false
    }

    func pinnedDisplay(bundleIdentifier: String?) -> String? {
        bundleIdentifier.flatMap { pinnedDisplays[$0] }
    }

    /// Whether a window with the given bundle identifier should remain floating.
    func shouldFloat(bundleIdentifier: String?) -> Bool {
        guard let id = bundleIdentifier, !id.isEmpty else { return false }
        return floatingBundleIDs.contains(id)
    }

    /// Serializes the floating bundle ID set into a newline-separated string for Settings editing.
    var serializedPatterns: String {
        (floatingBundleIDs.sorted()
            + alwaysTileBundleIDs.sorted().map { "\($0)=tile" }
            + pinnedDisplays.sorted { $0.key < $1.key }.map { "\($0.key)=display:\($0.value)" }
        ).joined(separator: "\n")
    }

    /// Parses one rule per line: `bundle.id` or `bundle.id=float` floats, `=tile` always tiles, `=display:Name` pins to a display.
    static func parse(patterns: String) -> TilingPolicy {
        let lines = patterns.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var policy = TilingPolicy(floatingBundleIDs: [])
        for line in lines {
            guard let eq = line.firstIndex(of: "=") else { policy.floatingBundleIDs.insert(line); continue }
            let id = line[..<eq].trimmingCharacters(in: .whitespaces)
            let rule = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if id.isEmpty { continue }
            if rule == "tile" { policy.alwaysTileBundleIDs.insert(id) }
            else if rule.hasPrefix("display:") { policy.pinnedDisplays[id] = String(rule.dropFirst(8)) }
            else if rule == "float" { policy.floatingBundleIDs.insert(id) }
        }
        return policy
    }
}
