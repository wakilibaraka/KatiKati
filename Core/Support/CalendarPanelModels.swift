import Foundation

// Pure models behind the floating calendar panel (Phase 5e): world clocks, the Pomodoro focus
// timer and alarms. No UI, no EventKit, no notifications — everything here is unit-testable.

// MARK: - World clocks (5e-E)

struct WorldClockReading: Equatable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let city: String
    let time: String
    /// -1 yesterday, 0 same day, +1 tomorrow relative to the local calendar day.
    let dayDelta: Int
    /// Signed hour difference from the local zone at `date`, e.g. "+5h", "-3h30m", "same".
    let offsetLabel: String
    let isNight: Bool
}

enum WorldClockModel {
    static let maxClocks = 4
    static let defaultIdentifiers = ["UTC", "America/New_York", "Europe/London", "Asia/Tokyo"]

    static func city(for identifier: String) -> String {
        if identifier == "UTC" || identifier == "GMT" { return "UTC" }
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }

    /// Appends `identifier` unless it is unknown, a duplicate, or the list is already full.
    static func adding(_ identifier: String, to list: [String]) -> [String] {
        guard TimeZone(identifier: identifier) != nil, !list.contains(identifier), list.count < maxClocks else { return list }
        return list + [identifier]
    }

    static func reading(
        for identifier: String, at date: Date, local: TimeZone = .current, locale: Locale = .current
    ) -> WorldClockReading? {
        guard let zone = TimeZone(identifier: identifier) else { return nil }
        var remote = Calendar(identifier: .gregorian); remote.timeZone = zone
        var home = Calendar(identifier: .gregorian); home.timeZone = local

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        formatter.timeStyle = .short
        formatter.dateStyle = .none

        let remoteDay = remote.dateComponents([.year, .month, .day], from: date)
        let homeDay = home.dateComponents([.year, .month, .day], from: date)
        var rc = Calendar(identifier: .gregorian); rc.timeZone = TimeZone(secondsFromGMT: 0)!
        let delta = rc.dateComponents([.day], from: rc.date(from: homeDay)!, to: rc.date(from: remoteDay)!).day ?? 0

        let hour = remote.component(.hour, from: date)
        return WorldClockReading(
            identifier: identifier,
            city: city(for: identifier),
            time: formatter.string(from: date),
            dayDelta: max(-1, min(1, delta)),
            offsetLabel: offsetLabel(seconds: zone.secondsFromGMT(for: date) - local.secondsFromGMT(for: date)),
            isNight: hour < 6 || hour >= 19
        )
    }

    static func offsetLabel(seconds: Int) -> String {
        guard seconds != 0 else { return "same" }
        let sign = seconds < 0 ? "-" : "+"
        let minutes = abs(seconds) / 60
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(sign)\(h)h" : "\(sign)\(h)h\(m)m"
    }
}

// MARK: - Focus timer (5e-F)

struct FocusTimerModel: Equatable {
    enum Phase: Equatable { case focus, shortBreak, longBreak }

    static let focusSeconds = 25 * 60
    static let shortBreakSeconds = 5 * 60
    static let longBreakSeconds = 15 * 60
    static let cycleLength = 4

    private(set) var phase: Phase = .focus
    private(set) var remaining: Int = FocusTimerModel.focusSeconds
    private(set) var isRunning = false
    /// Focus sessions completed in the current cycle (0…cycleLength-1 shown as lit dots).
    private(set) var completedInCycle = 0

    static func duration(of phase: Phase) -> Int {
        switch phase {
        case .focus: return focusSeconds
        case .shortBreak: return shortBreakSeconds
        case .longBreak: return longBreakSeconds
        }
    }

    var progress: Double {
        1 - Double(remaining) / Double(Self.duration(of: phase))
    }

    mutating func toggle() { isRunning.toggle() }

    mutating func reset() {
        isRunning = false
        remaining = Self.duration(of: phase)
    }

    /// Ends the current phase now and moves to the next one (does not auto-start).
    mutating func skip() {
        isRunning = false
        advance()
    }

    /// One second elapsed. Returns true when a phase just completed (caller plays the chime).
    @discardableResult
    mutating func tick() -> Bool {
        guard isRunning else { return false }
        remaining -= 1
        if remaining <= 0 { advance(); return true }
        return false
    }

    private mutating func advance() {
        switch phase {
        case .focus:
            completedInCycle += 1
            if completedInCycle >= Self.cycleLength {
                phase = .longBreak
                completedInCycle = Self.cycleLength
            } else {
                phase = .shortBreak
            }
        case .shortBreak:
            phase = .focus
        case .longBreak:
            phase = .focus
            completedInCycle = 0
        }
        remaining = Self.duration(of: phase)
    }
}

// MARK: - Alarms (5e-F)

struct AlarmItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var hour: Int
    var minute: Int
    var label: String = ""
    var isEnabled = true
    /// Calendar weekdays (1 = Sunday … 7 = Saturday). Empty = one-shot, next occurrence only.
    var weekdays: Set<Int> = []

    /// Next time this alarm rings strictly after `date`, or nil when disabled.
    func nextFire(after date: Date, calendar: Calendar = .current) -> Date? {
        guard isEnabled else { return nil }
        let components = DateComponents(hour: hour, minute: minute, second: 0)
        var cursor = date
        // Up to 8 matches covers every weekday filter plus a DST-skipped local time.
        for _ in 0..<8 {
            guard let candidate = calendar.nextDate(
                after: cursor, matching: components, matchingPolicy: .nextTime
            ) else { return nil }
            if weekdays.isEmpty || weekdays.contains(calendar.component(.weekday, from: candidate)) {
                return candidate
            }
            cursor = candidate
        }
        return nil
    }
}

enum AlarmList {
    /// Alarms sorted by time of day, then by label, for stable display.
    static func sorted(_ alarms: [AlarmItem]) -> [AlarmItem] {
        alarms.sorted { ($0.hour, $0.minute, $0.label) < ($1.hour, $1.minute, $1.label) }
    }

    /// The earliest upcoming ring among enabled alarms.
    static func next(in alarms: [AlarmItem], after date: Date, calendar: Calendar = .current) -> (AlarmItem, Date)? {
        alarms.compactMap { alarm in alarm.nextFire(after: date, calendar: calendar).map { (alarm, $0) } }
            .min { $0.1 < $1.1 }
    }
}

// MARK: - Agenda fitting (5e-D)

enum AgendaFitting {
    /// How many rows fit in `height` and how many overflow into a "+N more" line.
    static func visibleCount(total: Int, height: CGFloat, rowHeight: CGFloat, reservedForMore: CGFloat) -> (shown: Int, more: Int) {
        guard total > 0, rowHeight > 0 else { return (0, 0) }
        let fitsAll = Int(max(0, height) / rowHeight)
        if fitsAll >= total { return (total, 0) }
        let shown = max(0, Int(max(0, height - reservedForMore) / rowHeight))
        return (shown, total - shown)
    }
}
