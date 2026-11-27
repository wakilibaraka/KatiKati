import XCTest
@testable import KatiKati

final class LockScreenSurfacePolicyTests: XCTestCase {
    private func makeEvent(id: String, title: String, offsetMinutes: TimeInterval, durationMinutes: TimeInterval = 30, now: Date) -> DockEvent {
        let start = now.addingTimeInterval(offsetMinutes * 60)
        return DockEvent(
            id: id,
            title: title,
            start: start,
            end: start.addingTimeInterval(durationMinutes * 60),
            isAllDay: false,
            link: nil,
            location: "Room 42",
            colorRGB: [0.2, 0.6, 0.9]
        )
    }

    func testBusyOnlyRedactsTitlesWhilePreservingTimesAndLimit() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let events = [
            makeEvent(id: "1", title: "1:1 Confidential", offsetMinutes: 10, now: now),
            makeEvent(id: "2", title: "Design Sync", offsetMinutes: 45, now: now),
            makeEvent(id: "3", title: "Team Standup", offsetMinutes: 90, now: now),
            makeEvent(id: "4", title: "Late Review", offsetMinutes: 150, now: now)
        ]

        let busyRows = LockScreenSurfacePolicy.eventRows(
            from: events,
            now: now,
            detailMode: .busyOnly,
            limit: 3,
            busyPlaceholder: "Busy"
        )
        XCTAssertEqual(busyRows.count, 3)
        XCTAssertTrue(busyRows.allSatisfy { $0.displayTitle == "Busy" })
        XCTAssertFalse(busyRows[0].timeLabel.isEmpty)

        let titledRows = LockScreenSurfacePolicy.eventRows(
            from: events,
            now: now,
            detailMode: .titles,
            limit: 2
        )
        XCTAssertEqual(titledRows.map(\.displayTitle), ["1:1 Confidential", "Design Sync"])
    }

    func testGlanceItemsIncludeActiveSourcesInPriorityOrder() {
        let items = LockScreenSurfacePolicy.glanceItems(
            focusRemaining: "18:40",
            temperatureCelsius: 21.6,
            weatherSymbol: "sun.max.fill",
            nextEventCountdown: "in 12m"
        )
        XCTAssertEqual(items.map(\.id), ["focus", "weather", "nextEvent"])
        XCTAssertEqual(items[1].text, "22°")

        let partial = LockScreenSurfacePolicy.glanceItems(
            focusRemaining: nil,
            temperatureCelsius: nil,
            weatherSymbol: nil,
            nextEventCountdown: "Now"
        )
        XCTAssertEqual(partial.map(\.id), ["nextEvent"])
    }

    func testStackHeightScalesForCalendarAndGlance() {
        let base = LockScreenSurfacePolicy.stackHeight(musicHeight: 200, showsCalendar: false, calendarRowCount: 0, showsGlance: false)
        XCTAssertEqual(base, 200)

        let withBoth = LockScreenSurfacePolicy.stackHeight(musicHeight: 200, showsCalendar: true, calendarRowCount: 3, showsGlance: true)
        XCTAssertEqual(withBoth, 200 + 36 + 54 + 78)
    }
}
