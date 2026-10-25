import Foundation

/// How far an event is from now, as a value the UI turns into "in 3m" / "Now". Pure so the rounding is tested.
enum EventTimeUntil: Equatable, Sendable {
    case days(Int)
    case hours(Int, minutes: Int)
    case minutes(Int)
    case now
    case ended

    /// Minutes round **up** so "in 1m" holds until the start, never "in 0m".
    static func resolve(start: Date, end: Date? = nil, now: Date) -> EventTimeUntil {
        let seconds = start.timeIntervalSince(now)
        if seconds <= 0 {
            if let end, end <= now { return .ended }
            return .now
        }
        let total = Int((seconds / 60).rounded(.up))
        if total >= 24 * 60 { return .days(total / (24 * 60)) }
        if total >= 60 { return .hours(total / 60, minutes: total % 60) }
        return .minutes(total)
    }

    /// The Join button turns prominent this close to the start (and stays so while the event runs).
    static let joinLeadTime: TimeInterval = 10 * 60

    static func isJoinable(start: Date, end: Date, now: Date) -> Bool {
        now >= start.addingTimeInterval(-joinLeadTime) && now < end
    }
}

/// One calendar event as the dock widgets see it — no EventKit types, so selection logic is testable.
struct DockEvent: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let link: MeetingLink?
    let location: String?
    /// Calendar colour as sRGB components.
    let colorRGB: [Double]
}

enum UpcomingEvents {
    /// Timed events that haven't ended, soonest first. A running event stays in the list so Join remains reachable.
    static func select(_ events: [DockEvent], now: Date, limit: Int) -> [DockEvent] {
        Array(events
            .filter { !$0.isAllDay && $0.end > now }
            .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
            .prefix(limit))
    }
}
