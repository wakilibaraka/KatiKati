import XCTest
@testable import KatiKati

final class ClockChipContentTests: XCTestCase {
    
    func testStandardClockProvider() {
        let provider = StandardClockProvider()
        
        let testDate = Date(timeIntervalSince1970: 1687000000) // roughly June 2023
        
        let content = provider.currentContent(for: testDate)
        
        XCTAssertFalse(content.primaryText.isEmpty, "Time string should not be empty")
        XCTAssertNotNil(content.secondaryText)
        XCTAssertFalse(content.secondaryText!.isEmpty, "Date string should not be empty")
    }

    // MARK: - 4e: minute-aligned ticking

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func utcDate(_ hour: Int, _ minute: Int, _ second: Int, day: Int = 9) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 10, day: day,
                                     hour: hour, minute: minute, second: second))!
    }

    /// The ticker must land exactly on the next whole minute — late ticks would show a stale
    /// time, early ticks would show the previous minute.
    func testNextMinuteIsTheNextWholeBoundary() {
        XCTAssertEqual(ClockTick.nextMinute(after: utcDate(12, 30, 29), calendar: utc),
                       utcDate(12, 31, 0))
        XCTAssertEqual(ClockTick.nextMinute(after: utcDate(12, 30, 0), calendar: utc),
                       utcDate(12, 31, 0), "exactly on a boundary → the *next* one")
        XCTAssertEqual(ClockTick.nextMinute(after: utcDate(12, 30, 59), calendar: utc),
                       utcDate(12, 31, 0))
        // Hour and day roll over without drift.
        XCTAssertEqual(ClockTick.nextMinute(after: utcDate(23, 59, 59), calendar: utc),
                       utcDate(0, 0, 0, day: 10))
        // Repeated ticks stay on whole minutes.
        let tick = ClockTick.nextMinute(after: utcDate(9, 7, 33), calendar: utc)
        XCTAssertEqual(utc.component(.second, from: tick), 0)
        XCTAssertEqual(utc.component(.second, from: ClockTick.nextMinute(after: tick, calendar: utc)), 0)
    }

    /// A minute-aligned ticker is only correct if the provider is minute-resolution: two dates
    /// inside the same minute must produce identical content (nothing to go stale), and the
    /// next minute must differ.
    func testStandardClockProviderIsMinuteResolution() {
        let provider = StandardClockProvider()
        let base = Date(timeIntervalSince1970: 1_687_000_000)   // :40 past the minute

        XCTAssertEqual(provider.currentContent(for: base),
                       provider.currentContent(for: base.addingTimeInterval(10)),
                       "same minute → identical content")
        XCTAssertNotEqual(provider.currentContent(for: base).primaryText,
                          provider.currentContent(for: base.addingTimeInterval(60)).primaryText,
                          "the next minute must visibly tick over")
    }

    // MARK: - 8d: warm-by-day / indigo-at-night hue split

    /// The hue split must flip exactly at the locked build-time boundaries: warm 07:00–18:59,
    /// indigo 19:00–06:59 — a one-hour drift here would repaint the chip at the wrong time
    /// without any other symptom.
    func testDaylightBoundaryFlipsTheChipHue() {
        XCTAssertTrue(ClockChipDaylight.isNight(utcDate(6, 59, 0), calendar: utc), "06:59 still indigo")
        XCTAssertFalse(ClockChipDaylight.isNight(utcDate(7, 0, 0), calendar: utc), "07:00 flips warm")
        XCTAssertFalse(ClockChipDaylight.isNight(utcDate(12, 0, 0), calendar: utc))
        XCTAssertFalse(ClockChipDaylight.isNight(utcDate(18, 59, 59), calendar: utc), "18:59 still warm")
        XCTAssertTrue(ClockChipDaylight.isNight(utcDate(19, 0, 0), calendar: utc), "19:00 flips indigo")
        XCTAssertTrue(ClockChipDaylight.isNight(utcDate(23, 30, 0), calendar: utc))
        XCTAssertTrue(ClockChipDaylight.isNight(utcDate(0, 30, 0), calendar: utc))
    }
}
