import Foundation

/// Phase 10a-7 — context presets: switch the widget preset by time of day / weekday. Pure rule evaluation;
/// the app layer owns the (opt-in) minute tick and the apply.
struct ContextPresetRule: Codable, Equatable, Sendable {
    var presetID: String
    /// Minutes after local midnight, `start` inclusive, `end` exclusive; `start > end` wraps past midnight.
    var startMinute: Int
    var endMinute: Int
    /// `Calendar` weekday numbers (1 = Sunday … 7 = Saturday).
    var weekdays: Set<Int>
}

enum ContextPresetRules {
    static let defaultsKey = "com.katikati.widgets.contextRules.v1"
    static let enabledKey = "com.katikati.widgets.contextPresets.enabled"

    static let weekdaysMonToFri: Set<Int> = [2, 3, 4, 5, 6]
    static let allWeekdays: Set<Int> = Set(1...7)

    /// The two slots the Settings UI exposes (times fixed, preset chosen by the user).
    static func workRule(presetID: String) -> ContextPresetRule {
        ContextPresetRule(presetID: presetID, startMinute: 9 * 60, endMinute: 17 * 60, weekdays: weekdaysMonToFri)
    }
    static func eveningRule(presetID: String) -> ContextPresetRule {
        ContextPresetRule(presetID: presetID, startMinute: 18 * 60, endMinute: 23 * 60, weekdays: allWeekdays)
    }

    /// First matching rule's preset id, or nil.
    static func matchingPresetID(rules: [ContextPresetRule], at date: Date, calendar: Calendar = .current) -> String? {
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, let hour = parts.hour, let minute = parts.minute else { return nil }
        let now = hour * 60 + minute
        return rules.first { rule in
            guard rule.weekdays.contains(weekday) else { return false }
            if rule.startMinute <= rule.endMinute { return now >= rule.startMinute && now < rule.endMinute }
            return now >= rule.startMinute || now < rule.endMinute
        }?.presetID
    }

    /// Seconds until the next whole minute — the controller's one-shot timer target (minute-aligned, no drift).
    static func secondsToNextMinute(from date: Date, calendar: Calendar = .current) -> TimeInterval {
        guard let next = calendar.dateInterval(of: .minute, for: date)?.end else { return 60 }
        return max(1, next.timeIntervalSince(date))
    }

    /// Apply only when the matched preset *changes* (so a manual tweak inside a window isn't undone every minute).
    static func presetToApply(matched: String?, lastApplied: String?) -> String? {
        guard let matched, matched != lastApplied else { return nil }
        return matched
    }
}
