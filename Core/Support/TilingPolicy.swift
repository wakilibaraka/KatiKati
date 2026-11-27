import CoreGraphics
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

// MARK: - AT-2: per-display profiles

/// What kind of display a profile defaults to. The role is the final fallback when a display
/// reports a new UUID (the LG has already appeared as two different EDID UUIDs on this machine).
enum DisplayRole: String, Codable, CaseIterable, Sendable {
    case builtin, external

    static func resolve(isBuiltin: Bool) -> DisplayRole { isBuiltin ? .builtin : .external }
}

/// What happens when a Space already holds its maximum number of windows. Float Centered is the
/// default: it is instant, never changes the Space the user is on, and works for every app.
enum DisplayOverflowPolicy: String, Codable, CaseIterable, Sendable {
    /// Leave the window floating at a comfortable centred size on the same display.
    case floatCentered
    /// Move it to the other display, keeping its relative place and size (`WindowThrow`).
    case otherDisplay
    /// Assign it to the next KatiKati workspace on the same display and park it there.
    case nextWorkspace

    /// Localized here rather than at the call site: the picker feeds this into `Text(verbatim:)`, and
    /// the explicit `String(localized:)` is what keeps the key visible to the localization scan.
    var localizedTitleKey: String {
        switch self {
        case .floatCentered: return String(localized: "Float Centered")
        case .otherDisplay: return String(localized: "Other Display")
        case .nextWorkspace: return String(localized: "Next Space")
        }
    }
}

/// One display's auto-tiling settings. Only the knobs that differ per display live here; the layout
/// itself stays in `displayPresets`/`displayLayouts`, and mirrored main windows stay global.
struct DisplayTilingProfile: Codable, Equatable, Sendable {
    var role: DisplayRole
    var gaps: TilingGaps
    /// Share of the work area given to the main window in Main + Stack / Centered Main.
    var mainRatio: CGFloat
    /// Hard cap per Space. `nil` keeps the old size-based overflow rule alone.
    var maxWindowsPerSpace: Int?
    var overflow: DisplayOverflowPolicy
    /// Hide the floating island while a watching app is fullscreen, on a display without a notch.
    var hideIslandForMedia: Bool

    static let maxWindowRange: ClosedRange<Int> = 1...12

    init(
        role: DisplayRole,
        gaps: TilingGaps,
        mainRatio: CGFloat,
        maxWindowsPerSpace: Int?,
        overflow: DisplayOverflowPolicy = .floatCentered,
        hideIslandForMedia: Bool = false
    ) {
        self.role = role
        self.gaps = gaps
        self.mainRatio = mainRatio
        self.maxWindowsPerSpace = maxWindowsPerSpace
        self.overflow = overflow
        self.hideIslandForMedia = hideIslandForMedia
    }

    /// Clamps hand-edited values into the ranges the sliders and steppers offer.
    func clamped() -> DisplayTilingProfile {
        var copy = self
        copy.mainRatio = min(max(mainRatio, TilingLayoutOptions.ratioRange.lowerBound),
                             TilingLayoutOptions.ratioRange.upperBound)
        copy.gaps = TilingGaps(inner: min(max(gaps.inner, 0), 32), outer: min(max(gaps.outer, 0), 32))
        if let cap = copy.maxWindowsPerSpace {
            copy.maxWindowsPerSpace = min(max(cap, Self.maxWindowRange.lowerBound), Self.maxWindowRange.upperBound)
        }
        return copy
    }

    /// The Power-User Dual-Display preset. It composes the existing Main + Stack solver; it is not a
    /// new layout type, so a live A/B can still swap the preset without new localisations.
    static func powerUser(role: DisplayRole) -> DisplayTilingProfile {
        switch role {
        case .external:
            return DisplayTilingProfile(role: role, gaps: TilingGaps(inner: 8, outer: 10),
                                        mainRatio: 0.58, maxWindowsPerSpace: 4,
                                        overflow: .floatCentered, hideIslandForMedia: true)
        case .builtin:
            return DisplayTilingProfile(role: role, gaps: TilingGaps(inner: 6, outer: 8),
                                        mainRatio: 0.55, maxWindowsPerSpace: 2,
                                        overflow: .floatCentered, hideIslandForMedia: false)
        }
    }
}

/// The durable half of AT-2. Kept separate from `TilingEngine` so role resolution, UUID churn and the
/// seeding rules can be tested without a screen or a running app.
enum DisplayProfiles {
    static let enabledKey = "com.katikati.tiling.multiDisplay"
    static let profilesKey = "com.katikati.tiling.displayProfiles"

    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    static func stored(_ defaults: UserDefaults = .standard) -> [String: DisplayTilingProfile] {
        guard let text = defaults.string(forKey: profilesKey),
              let data = text.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: DisplayTilingProfile].self, from: data)
        else { return [:] }
        return decoded.mapValues { $0.clamped() }
    }

    static func save(_ profiles: [String: DisplayTilingProfile], _ defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(profiles),
              let text = String(data: data, encoding: .utf8) else { return }
        defaults.set(text, forKey: profilesKey)
    }

    /// UUID first, then the display's name (an install that predates UUID keys, or a panel that
    /// reports a new EDID UUID on the same port), then the role default.
    static func resolve(
        key: String,
        name: String,
        role: DisplayRole,
        profiles: [String: DisplayTilingProfile]
    ) -> DisplayTilingProfile {
        if let match = profiles[key] { return match.clamped() }
        if let match = profiles[name] { return match.clamped() }
        return .powerUser(role: role)
    }

    /// Seeds a profile for every connected display. A display that already has one keeps it, so
    /// turning the toggle off and on never overwrites a tuned setup.
    static func seeded(
        displays: [(key: String, name: String, role: DisplayRole)],
        profiles: [String: DisplayTilingProfile]
    ) -> [String: DisplayTilingProfile] {
        var next = profiles
        for display in displays where next[display.key] == nil {
            if let byName = next[display.name] { next[display.key] = byName; continue }
            next[display.key] = .powerUser(role: display.role)
        }
        return next
    }
}
