import Foundation

/// Pure date-math calculator for elapsed/remaining breakdowns, business-day counting, and date offsetting.
public enum DateCalculator {
    public struct DateDifference: Equatable, Sendable {
        public let years: Int
        public let months: Int
        public let days: Int
        public let totalDays: Int
        public let totalHours: Int
        public let totalMinutes: Int
        public let totalSeconds: Int
        public let businessDays: Int
        public let isPast: Bool

        public init(
            years: Int,
            months: Int,
            days: Int,
            totalDays: Int,
            totalHours: Int,
            totalMinutes: Int,
            totalSeconds: Int,
            businessDays: Int,
            isPast: Bool
        ) {
            self.years = years
            self.months = months
            self.days = days
            self.totalDays = totalDays
            self.totalHours = totalHours
            self.totalMinutes = totalMinutes
            self.totalSeconds = totalSeconds
            self.businessDays = businessDays
            self.isPast = isPast
        }
    }

    public enum OffsetUnit: String, CaseIterable, Identifiable, Sendable {
        case days
        case weeks
        case months
        case years
        case hours
        case minutes

        public var id: String { rawValue }
    }

    public static func difference(
        from start: Date,
        to end: Date,
        calendar: Calendar = .current
    ) -> DateDifference {
        let isPast = end < start
        let earlier = isPast ? end : start
        let later = isPast ? start : end

        let comps = calendar.dateComponents([.year, .month, .day], from: earlier, to: later)
        let exactDay = calendar.dateComponents([.day], from: earlier, to: later).day ?? 0

        let interval = max(0, later.timeIntervalSince(earlier))
        let totalSeconds = Int(interval.rounded(.down))
        let totalMinutes = totalSeconds / 60
        let totalHours = totalMinutes / 60

        let startDay = calendar.startOfDay(for: earlier)
        let endDay = calendar.startOfDay(for: later)
        let businessDays = countWeekdays(from: startDay, to: endDay, calendar: calendar)

        return DateDifference(
            years: comps.year ?? 0,
            months: comps.month ?? 0,
            days: comps.day ?? 0,
            totalDays: exactDay,
            totalHours: totalHours,
            totalMinutes: totalMinutes,
            totalSeconds: totalSeconds,
            businessDays: businessDays,
            isPast: isPast
        )
    }

    public static func offset(
        from date: Date,
        amount: Int,
        unit: OffsetUnit,
        calendar: Calendar = .current
    ) -> Date {
        let component: Calendar.Component
        let value: Int
        switch unit {
        case .days:
            component = .day
            value = amount
        case .weeks:
            component = .day
            value = amount * 7
        case .months:
            component = .month
            value = amount
        case .years:
            component = .year
            value = amount
        case .hours:
            component = .hour
            value = amount
        case .minutes:
            component = .minute
            value = amount
        }
        return calendar.date(byAdding: component, value: value, to: date) ?? date
    }

    public static func countdownSummary(
        from now: Date,
        to target: Date,
        calendar: Calendar = .current
    ) -> String {
        let isPast = target < now
        let earlier = isPast ? target : now
        let later = isPast ? now : target
        let comps = calendar.dateComponents([.day, .hour, .minute], from: earlier, to: later)
        let d = comps.day ?? 0
        let h = comps.hour ?? 0
        let m = comps.minute ?? 0

        var parts: [String] = []
        if d > 0 { parts.append("\(d)d") }
        if h > 0 || d > 0 { parts.append("\(h)h") }
        parts.append("\(m)m")
        let joined = parts.joined(separator: " ")
        return isPast ? "\(joined) ago" : joined
    }

    private static func countWeekdays(from startDay: Date, to endDay: Date, calendar: Calendar) -> Int {
        guard endDay > startDay else { return 0 }
        var count = 0
        var cursor = startDay
        while cursor < endDay {
            let weekday = calendar.component(.weekday, from: cursor)
            // Sunday == 1, Saturday == 7 in Gregorian/ISO calendars.
            if weekday != 1 && weekday != 7 {
                count += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return count
    }
}
