import Foundation

/// Per-app foreground seconds by local day (Phase 7B-W1). Pure value + arithmetic; no AppKit, no clock, no disk.
/// Only an app's bundle id, its display name and a number of seconds are ever stored — never window titles, URLs,
/// documents or input.
struct ScreenTimeLedger: Equatable, Codable, Sendable {
    /// `yyyy-MM-dd` (local) → bundle id → seconds.
    var days: [String: [String: Double]] = [:]
    var names: [String: String] = [:]

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    mutating func add(bundleID: String, name: String, seconds: Double, day: String) {
        guard seconds > 0, !bundleID.isEmpty else { return }
        days[day, default: [:]][bundleID, default: 0] += seconds
        if !name.isEmpty { names[bundleID] = name }
    }

    func total(day: String) -> Double { (days[day] ?? [:]).values.reduce(0, +) }

    func seconds(bundleID: String, day: String) -> Double { days[day]?[bundleID] ?? 0 }

    /// Most-used apps for a day, biggest first; ties by name so the order is stable.
    func top(day: String, limit: Int) -> [(bundleID: String, name: String, seconds: Double)] {
        (days[day] ?? [:])
            .map { (bundleID: $0.key, name: names[$0.key] ?? $0.key, seconds: $0.value) }
            .sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.name < $1.name }
            .prefix(max(0, limit)).map { $0 }
    }

    /// Totals for the seven days ending at `end` (oldest first).
    func week(endingAt end: Date, calendar: Calendar) -> [(day: String, seconds: Double)] {
        (0..<7).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: end).map { d in
                let k = Self.dayKey(d, calendar: calendar)
                return (k, total(day: k))
            }
        }
    }

    /// Drops days older than `keepDays` and names no remaining day mentions.
    mutating func prune(keepDays: Int, now: Date, calendar: Calendar) {
        guard let cutoff = calendar.date(byAdding: .day, value: -max(1, keepDays), to: now) else { return }
        let cutoffKey = Self.dayKey(cutoff, calendar: calendar)
        days = days.filter { $0.key > cutoffKey }
        let live = Set(days.values.flatMap { $0.keys })
        names = names.filter { live.contains($0.key) }
    }

    static func format(_ seconds: Double) -> String {
        let m = Int((max(0, seconds) / 60).rounded())
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}

/// Accrues foreground time into a ledger. The platform feeds it events (app switched, idle, screen asleep) and ticks;
/// everything about *how time is counted* lives here so it can be tested without a clock.
struct ScreenTimeTracker: Equatable, Sendable {
    /// A gap longer than this between two ticks is not credited (the Mac was asleep or the app was suspended).
    static let maxCreditedGap: TimeInterval = 120
    /// Seconds without input after which the user counts as away.
    static let idleThreshold: TimeInterval = 120

    private(set) var current: (bundleID: String, name: String)?
    private(set) var counting = false
    private var lastTick: Date?

    static func == (a: ScreenTimeTracker, b: ScreenTimeTracker) -> Bool {
        a.current?.bundleID == b.current?.bundleID && a.counting == b.counting && a.lastTick == b.lastTick
    }

    /// Credits the time since the last tick to the current app (split at local midnight) and moves the clock on.
    mutating func advance(to now: Date, ledger: inout ScreenTimeLedger, calendar: Calendar) {
        defer { lastTick = now }
        guard counting, let app = current, let from = lastTick, now > from else { return }
        let end = min(now, from.addingTimeInterval(Self.maxCreditedGap))
        var cursor = from
        while cursor < end {
            let nextMidnight = calendar.nextDate(after: cursor, matching: DateComponents(hour: 0, minute: 0, second: 0),
                                                 matchingPolicy: .nextTime) ?? end
            let sliceEnd = min(end, nextMidnight)
            ledger.add(bundleID: app.bundleID, name: app.name, seconds: sliceEnd.timeIntervalSince(cursor),
                       day: ScreenTimeLedger.dayKey(cursor, calendar: calendar))
            cursor = sliceEnd
        }
    }

    mutating func appActivated(bundleID: String, name: String, at now: Date, ledger: inout ScreenTimeLedger, calendar: Calendar) {
        advance(to: now, ledger: &ledger, calendar: calendar)
        current = bundleID.isEmpty ? nil : (bundleID, name)
    }

    /// `awake` = screen on and recent input. Flipping it first credits the time up to now.
    mutating func setCounting(_ awake: Bool, at now: Date, ledger: inout ScreenTimeLedger, calendar: Calendar) {
        advance(to: now, ledger: &ledger, calendar: calendar)
        counting = awake
    }

    static func isAway(idleSeconds: TimeInterval, screenAsleep: Bool) -> Bool {
        screenAsleep || idleSeconds >= idleThreshold
    }
}

/// Per-app daily limits (Phase 7B-W3), stored as `bundle.id:minutes,other.id:minutes` in
/// `com.katikati.screentime.limits`. Minutes are clamped to 5…720; malformed entries are dropped.
enum ScreenTimeLimits {
    static let range = 5...720
    static let presets = [15, 30, 45, 60, 90, 120, 180, 240]

    static func parse(_ stored: String?) -> [String: Int] {
        var out: [String: Int] = [:]
        for part in (stored ?? "").split(separator: ",") {
            guard let colon = part.lastIndex(of: ":"), let m = Int(part[part.index(after: colon)...]) else { continue }
            let id = String(part[..<colon]).trimmingCharacters(in: .whitespaces)
            if !id.isEmpty { out[id] = min(max(m, range.lowerBound), range.upperBound) }
        }
        return out
    }

    static func serialize(_ limits: [String: Int]) -> String {
        limits.keys.sorted().map { "\($0):\(limits[$0]!)" }.joined(separator: ",")
    }
}

/// What the limit check wants shown right now.
enum ScreenTimeLimitAction: Equatable {
    case warn(minutesLeft: Int)
    case reached
}

/// Remembers what was already said today so each warning fires once and a snooze or dismissal is respected.
struct ScreenTimeLimitState: Equatable {
    /// Bundle id → day key on which the heads-up was shown.
    var warned: [String: String] = [:]
    /// Bundle id → no "reached" prompt before this time.
    var quietUntil: [String: Date] = [:]

    static let warnMinutes = 5
    static let snoozeMinutes = 5

    /// Call for the frontmost app on each tick. Nil = nothing to show.
    mutating func evaluate(bundleID: String, usedSeconds: Double, limitMinutes: Int?, now: Date, day: String) -> ScreenTimeLimitAction? {
        guard let limit = limitMinutes, limit > 0 else { return nil }
        let left = Double(limit) * 60 - usedSeconds
        if left <= 0 {
            if let until = quietUntil[bundleID], now < until { return nil }
            quietUntil[bundleID] = now.addingTimeInterval(Double(Self.snoozeMinutes) * 60) // re-prompt cadence if ignored
            return .reached
        }
        if left <= Double(Self.warnMinutes) * 60, warned[bundleID] != day {
            warned[bundleID] = day
            return .warn(minutesLeft: max(1, Int((left / 60).rounded(.up))))
        }
        return nil
    }

    mutating func snooze(_ bundleID: String, from now: Date) {
        quietUntil[bundleID] = now.addingTimeInterval(Double(Self.snoozeMinutes) * 60)
    }

    /// "Dismiss": stay quiet for this app until the next day starts.
    mutating func dismissForToday(_ bundleID: String, now: Date, calendar: Calendar) {
        quietUntil[bundleID] = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(86_400)
    }
}
