import Foundation

/// Phase 56a: how far through the calendar year a date is, counted in whole days.
struct YearProgress: Equatable {
    let dayOfYear: Int
    let daysInYear: Int

    init(date: Date, calendar: Calendar = .current) {
        dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        daysInYear = calendar.range(of: .day, in: .year, for: date)?.count ?? 365
    }

    var fraction: Double { Double(dayOfYear) / Double(daysInYear) }
    var percent: Int { Int((fraction * 100).rounded(.down)) }
    var daysLeft: Int { daysInYear - dayOfYear }
}
