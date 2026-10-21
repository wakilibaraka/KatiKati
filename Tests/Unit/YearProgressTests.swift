import XCTest
@testable import KatiKati

final class YearProgressTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }

    func testFirstAndLastDay() {
        let first = YearProgress(date: date(2026, 1, 1), calendar: cal)
        XCTAssertEqual([first.dayOfYear, first.daysInYear, first.daysLeft], [1, 365, 364])
        let last = YearProgress(date: date(2026, 12, 31), calendar: cal)
        XCTAssertEqual([last.percent, last.daysLeft], [100, 0])
    }

    func testLeapYearAndMidYear() {
        let leap = YearProgress(date: date(2028, 3, 1), calendar: cal)
        XCTAssertEqual([leap.dayOfYear, leap.daysInYear], [61, 366])
        XCTAssertEqual(YearProgress(date: date(2026, 7, 2), calendar: cal).percent, 50)
    }
}
