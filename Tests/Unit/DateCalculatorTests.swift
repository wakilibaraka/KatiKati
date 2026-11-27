import XCTest
@testable import KatiKati

final class DateCalculatorTests: XCTestCase {
    private let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        utcCalendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testSameDayDifferenceIsZero() {
        let d = date(2026, 6, 15, 10, 30)
        let diff = DateCalculator.difference(from: d, to: d, calendar: utcCalendar)
        XCTAssertEqual(diff.years, 0)
        XCTAssertEqual(diff.months, 0)
        XCTAssertEqual(diff.days, 0)
        XCTAssertEqual(diff.totalDays, 0)
        XCTAssertEqual(diff.businessDays, 0)
        XCTAssertFalse(diff.isPast)
    }

    func testLeapYearAndMultiMonthDifference() {
        let start = date(2024, 2, 28)
        let end = date(2024, 3, 2)
        let diff = DateCalculator.difference(from: start, to: end, calendar: utcCalendar)
        // 2024 is a leap year: Feb 28 -> Feb 29 -> Mar 1 -> Mar 2 = 3 days.
        XCTAssertEqual(diff.totalDays, 3)
        XCTAssertEqual(diff.totalHours, 72)
        XCTAssertEqual(diff.totalMinutes, 72 * 60)
        XCTAssertEqual(diff.totalSeconds, 72 * 3600)
        XCTAssertFalse(diff.isPast)
    }

    func testReverseDirectionSetsIsPastAndCountsAbsoluteMagnitude() {
        let later = date(2026, 11, 10)
        let earlier = date(2026, 11, 3)
        let diff = DateCalculator.difference(from: later, to: earlier, calendar: utcCalendar)
        XCTAssertTrue(diff.isPast)
        XCTAssertEqual(diff.totalDays, 7)
        XCTAssertEqual(diff.businessDays, 5)
    }

    func testBusinessDaysSkipsWeekend() {
        // 2026-11-23 is Monday, 2026-11-30 is Monday (5 weekdays in a Mon->Mon span).
        let mon1 = date(2026, 11, 23)
        let mon2 = date(2026, 11, 30)
        let diff = DateCalculator.difference(from: mon1, to: mon2, calendar: utcCalendar)
        XCTAssertEqual(diff.totalDays, 7)
        XCTAssertEqual(diff.businessDays, 5)
    }

    func testOffsetHandlesAllUnitsSigned() {
        let base = date(2026, 1, 15, 12, 0)
        XCTAssertEqual(DateCalculator.offset(from: base, amount: 5, unit: .days, calendar: utcCalendar), date(2026, 1, 20, 12, 0))
        XCTAssertEqual(DateCalculator.offset(from: base, amount: -2, unit: .weeks, calendar: utcCalendar), date(2026, 1, 1, 12, 0))
        XCTAssertEqual(DateCalculator.offset(from: base, amount: 2, unit: .months, calendar: utcCalendar), date(2026, 3, 15, 12, 0))
        XCTAssertEqual(DateCalculator.offset(from: base, amount: 1, unit: .years, calendar: utcCalendar), date(2027, 1, 15, 12, 0))
        XCTAssertEqual(DateCalculator.offset(from: base, amount: 3, unit: .hours, calendar: utcCalendar), date(2026, 1, 15, 15, 0))
        XCTAssertEqual(DateCalculator.offset(from: base, amount: 30, unit: .minutes, calendar: utcCalendar), date(2026, 1, 15, 12, 30))
    }

    func testCountdownSummaryFormatsForwardAndPast() {
        let now = date(2026, 11, 1, 10, 0)
        let future = date(2026, 11, 3, 14, 15)
        let past = date(2026, 10, 31, 8, 30)
        XCTAssertEqual(DateCalculator.countdownSummary(from: now, to: future, calendar: utcCalendar), "2d 4h 15m")
        XCTAssertEqual(DateCalculator.countdownSummary(from: now, to: past, calendar: utcCalendar), "1d 1h 30m ago")
    }
}
