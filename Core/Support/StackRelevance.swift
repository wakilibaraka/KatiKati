import Foundation

/// Phase 10a-6 — Smart Stack: one widget slot that holds several widgets and shows the most relevant one.
/// Pure scoring (no clock reads beyond the `now` passed in, no AppKit), so every rule is unit-tested.
struct StackSignals: Equatable, Sendable {
    /// The winning live activity; `.clock` means nothing is live.
    var liveKind: LiveActivityKind
    var weatherCondition: WeatherCondition?
}

/// A manual pick that wins over relevance until `until`.
struct StackOverride: Equatable, Sendable {
    var member: BarSection
    var until: Date
}

enum StackRelevance {
    /// What a stack holds when switched on: the three widgets that have something to say.
    static let defaultMembers: [BarSection] = [.weather, .media, .clock]
    /// A challenger must beat the current member by more than this to take over (no flapping).
    static let switchMargin = 15
    static let overrideDuration: TimeInterval = 10 * 60

    static func score(_ member: BarSection, _ signals: StackSignals) -> Int {
        switch member {
        case .media: return signals.liveKind == .clock ? 0 : 100
        case .weather: return isWet(signals.weatherCondition) ? 80 : 10
        case .clock: return 20
        case .launcher, .apps, .widgets: return 0
        }
    }

    private static func isWet(_ condition: WeatherCondition?) -> Bool {
        switch condition {
        case .drizzle?, .rain?, .showers?, .thunderstorm?, .snow?: return true
        default: return false
        }
    }

    /// The member to show: an unexpired override, else the best score — keeping `current` unless beaten by
    /// more than `switchMargin`. Ties go to the earlier member. Empty `members` → `.clock`.
    static func resolve(members: [BarSection], signals: StackSignals, current: BarSection?,
                        override: StackOverride?, now: Date) -> BarSection {
        guard !members.isEmpty else { return .clock }
        if let override, override.until > now, members.contains(override.member) { return override.member }
        var best = members[0]
        for member in members.dropFirst() where score(member, signals) > score(best, signals) { best = member }
        if let current, members.contains(current), current != best,
           score(best, signals) <= score(current, signals) + switchMargin {
            return current
        }
        return best
    }

    /// The member after `shown`, wrapping — for the manual "Show Next in Stack".
    static func next(after shown: BarSection, in members: [BarSection]) -> BarSection {
        guard let index = members.firstIndex(of: shown), !members.isEmpty else { return members.first ?? .clock }
        return members[(index + 1) % members.count]
    }
}
