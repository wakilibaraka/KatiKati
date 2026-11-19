import Foundation
import XCTest

final class DesktopGlanceTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testSolarTermsMatchKnownDates() {
        XCTAssertEqual(DesktopGlanceEngine.solarTerm(on: date(2026, 3, 20), calendar: calendar), .springEquinox)
        XCTAssertEqual(DesktopGlanceEngine.solarTerm(on: date(2026, 2, 4), calendar: calendar), .startOfSpring)
        XCTAssertNil(DesktopGlanceEngine.solarTerm(on: date(2026, 3, 21), calendar: calendar))
    }

    func testEveryYearHasTwentyFourTermsOnDistinctDays() {
        let days = DesktopSolarTerm.allCases.map { DesktopGlanceEngine.solarTermDay($0, year: 2026) }
        XCTAssertEqual(days.count, 24)
        for term in DesktopSolarTerm.allCases {
            let day = DesktopGlanceEngine.solarTermDay(term, year: 2026)
            XCTAssertTrue((3...24).contains(day), "\(term) day \(day)")
        }
    }

    func testLunarNewYear2026AndFestivals() {
        let springFestival = date(2026, 2, 17)
        XCTAssertEqual(DesktopGlanceEngine.lunarDate(on: springFestival, timeZone: calendar.timeZone),
                       DesktopLunarDate(month: 1, day: 1, isLeapMonth: false))
        XCTAssertTrue(DesktopGlanceEngine.festivals(on: springFestival, calendar: calendar).contains(.springFestival))
        XCTAssertEqual(DesktopGlanceEngine.festivals(on: date(2026, 12, 25), calendar: calendar), [.christmas])
        XCTAssertTrue(DesktopGlanceEngine.festivals(on: date(2026, 6, 10), calendar: calendar).isEmpty)
    }
}
