import XCTest
@testable import KatiKati

// Boring-look notch skin — pure layout numbers, panel selection and the week strip.

final class NotchLayoutSpecTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func testOpenSizeIsTheReferenceProportion() {
        XCTAssertEqual(NotchLayoutSpec.openSize, CGSize(width: 640, height: 190))
        XCTAssertEqual(NotchGeometry.openSize(for: .boring), CGSize(width: 640, height: 190))
        XCTAssertEqual(NotchGeometry.openSize(for: .classic), CGSize(width: 420, height: 130))
    }

    func testOpenPanelNeverExceedsScreen() {
        XCTAssertEqual(NotchLayoutSpec.openPanelSize(screenWidth: 1710, closedWidth: 185).width, 640)
        XCTAssertEqual(NotchLayoutSpec.openPanelSize(screenWidth: 500, closedWidth: 185).width, 476)
        XCTAssertEqual(NotchLayoutSpec.openPanelSize(screenWidth: 100, closedWidth: 185).width, 185, "never narrower than the notch")
    }

    func testHeaderHeightFollowsNotchButFitsButtons() {
        XCTAssertEqual(NotchLayoutSpec.headerHeight(closedHeight: 32), 32)
        XCTAssertEqual(NotchLayoutSpec.headerHeight(closedHeight: 10), NotchLayoutSpec.headerButtonSize)
    }

    func testMusicOrIdleShowsThePlayerNeverTheClock() {
        XCTAssertEqual(NotchLayoutSpec.panels(activityKind: .music, calendarEnabled: true), .init(left: .music, showsCalendar: true))
        XCTAssertEqual(NotchLayoutSpec.panels(activityKind: .clock, calendarEnabled: true).left, .music)
        for kind in LiveActivityKind.allCases where kind != .music && kind != .clock {
            XCTAssertEqual(NotchLayoutSpec.panels(activityKind: kind, calendarEnabled: false), .init(left: .activity, showsCalendar: false))
        }
    }

    func testWeekStripHasSevenDaysTodayInTheMiddle() {
        let now = Date(timeIntervalSince1970: 1_776_000_000) // mid-April 2026
        let strip = NotchLayoutSpec.weekStrip(now: now, calendar: utc)
        XCTAssertEqual(strip.count, 7)
        XCTAssertEqual(strip.filter(\.isToday).count, 1)
        XCTAssertTrue(strip[3].isToday)
        XCTAssertEqual(strip[3].dayNumber, utc.component(.day, from: now))
        for i in 1..<7 {
            XCTAssertEqual(utc.dateComponents([.day], from: strip[i - 1].date, to: strip[i].date).day, 1)
        }
    }

    func testWeekStripCrossesMonthBoundary() {
        let now = utc.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        let numbers = NotchLayoutSpec.weekStrip(now: now, calendar: utc).map(\.dayNumber)
        XCTAssertEqual(numbers, [29, 30, 31, 1, 2, 3, 4])
    }

    func testClockText() {
        XCTAssertEqual(NotchLayoutSpec.clockText(0), "0:00")
        XCTAssertEqual(NotchLayoutSpec.clockText(65), "1:05")
        XCTAssertEqual(NotchLayoutSpec.clockText(3725), "1:02:05")
        XCTAssertEqual(NotchLayoutSpec.clockText(-4), "0:00")
    }

    // Phase 34 witness: the notch pages must never ship hardcoded demo numbers again.
    func testNotchPagesHaveNoMockLiterals() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for (file, bad) in [("NotchHardwareHudPageView", ["\"14%\"", "\"18.4 GB\"", "38°C"]),
                            ("NotchProductivityPageView", ["No conflicts today"]),
                            ("NotchRetroClockPageView", ["UTC+3"])] {
            let src = try String(contentsOf: root.appendingPathComponent("App/Scenes/Notch/\(file).swift"), encoding: .utf8)
            for literal in bad { XCTAssertFalse(src.contains(literal), "\(file) still has \(literal)") }
        }
    }
}
