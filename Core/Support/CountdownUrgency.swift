import Foundation

/// D1: Color-coded urgency tiers for upcoming meeting countdowns in `CalendarDockWidget`.
enum CountdownUrgency: Int, Equatable, Comparable, Sendable {
    case neutral = 0
    case accent = 1
    case amber = 2
    case red = 3

    static func < (lhs: CountdownUrgency, rhs: CountdownUrgency) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func tier(secondsUntil: TimeInterval) -> CountdownUrgency {
        if secondsUntil < -300 { return .accent }
        if secondsUntil <= 60 { return .red }
        if secondsUntil <= 300 { return .amber }
        if secondsUntil <= 900 { return .accent }
        return .neutral
    }
}

/// D1: Guarded meeting auto-join policy (opt-in, unlocked screen only, active user, fires once per event).
enum MeetingAutoJoinPolicy {
    static let enabledKey = "com.katikati.calendar.autoJoinMeeting"
    static let maxIdleSeconds: TimeInterval = 300

    static func shouldAutoJoin(
        eventID: String,
        hasMeetingURL: Bool,
        secondsUntil: TimeInterval,
        isScreenLocked: Bool,
        idleSeconds: TimeInterval,
        alreadyFired: Set<String>,
        enabled: Bool
    ) -> Bool {
        guard enabled,
              hasMeetingURL,
              !isScreenLocked,
              idleSeconds < maxIdleSeconds,
              !alreadyFired.contains(eventID),
              (-30...60).contains(secondsUntil) else {
            return false
        }
        return true
    }
}
