import XCTest
@testable import KatiKati

final class CalendarPanelModelsTests: XCTestCase {
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, in zone: TimeZone) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = zone
        return c.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    // MARK: World clocks
    func testCityNamesAndList() {
        XCTAssertEqual(WorldClockModel.city(for: "America/New_York"), "New York")
        XCTAssertEqual(WorldClockModel.city(for: "UTC"), "UTC")
        var list: [String] = []
        for id in ["UTC", "UTC", "Nope/Zone", "Asia/Tokyo", "Europe/London", "America/Chicago", "Asia/Dubai"] {
            list = WorldClockModel.adding(id, to: list)
        }
        XCTAssertEqual(list, ["UTC", "Asia/Tokyo", "Europe/London", "America/Chicago"], "dupes/unknown dropped, capped at 4")
    }

    func testDayDeltaAcrossTheDateLine() {
        let utc = TimeZone(identifier: "UTC")!
        let now = date(2026, 10, 11, 20, 0, in: utc) // 20:00 UTC
        let tokyo = WorldClockModel.reading(for: "Asia/Tokyo", at: now, local: utc)!
        XCTAssertEqual(tokyo.dayDelta, 1)
        XCTAssertEqual(tokyo.offsetLabel, "+9h")
        let la = WorldClockModel.reading(for: "America/Los_Angeles", at: date(2026, 10, 11, 3, 0, in: utc), local: utc)!
        XCTAssertEqual(la.dayDelta, -1)
        XCTAssertEqual(la.offsetLabel, "-7h") // PDT in October
        XCTAssertEqual(WorldClockModel.reading(for: "UTC", at: now, local: utc)?.offsetLabel, "same")
    }

    func testHalfHourOffsetAndNight() {
        let utc = TimeZone(identifier: "UTC")!
        let r = WorldClockModel.reading(for: "Asia/Kolkata", at: date(2026, 1, 1, 12, 0, in: utc), local: utc)!
        XCTAssertEqual(r.offsetLabel, "+5h30m")
        XCTAssertFalse(r.isNight) // 17:30
        let n = WorldClockModel.reading(for: "Asia/Kolkata", at: date(2026, 1, 1, 18, 0, in: utc), local: utc)!
        XCTAssertTrue(n.isNight) // 23:30
        XCTAssertNil(WorldClockModel.reading(for: "Bad/Zone", at: Date()))
    }

    // MARK: Focus
    func testFocusRunsAndCompletesIntoShortBreak() {
        var t = FocusTimerModel()
        XCTAssertFalse(t.tick(), "paused timers do not tick")
        t.toggle()
        for _ in 0..<(FocusTimerModel.focusSeconds - 1) { XCTAssertFalse(t.tick()) }
        XCTAssertTrue(t.tick())
        XCTAssertEqual(t.phase, .shortBreak)
        XCTAssertEqual(t.completedInCycle, 1)
        XCTAssertEqual(t.remaining, FocusTimerModel.shortBreakSeconds)
    }

    func testFourFocusSessionsEarnALongBreakThenCycleResets() {
        var t = FocusTimerModel()
        for _ in 0..<3 { t.skip(); XCTAssertEqual(t.phase, .shortBreak); t.skip(); XCTAssertEqual(t.phase, .focus) }
        t.skip()
        XCTAssertEqual(t.phase, .longBreak)
        XCTAssertEqual(t.completedInCycle, 4)
        t.skip()
        XCTAssertEqual(t.phase, .focus)
        XCTAssertEqual(t.completedInCycle, 0)
    }

    func testResetAndProgress() {
        var t = FocusTimerModel()
        t.toggle()
        for _ in 0..<(25 * 30) { t.tick() }
        XCTAssertEqual(t.progress, 0.5, accuracy: 0.001)
        t.reset()
        XCTAssertFalse(t.isRunning)
        XCTAssertEqual(t.remaining, FocusTimerModel.focusSeconds)
    }

    // MARK: Alarms
    func testNextFireOneShotRollsToTomorrow() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = date(2026, 10, 11, 9, 0, in: cal.timeZone)
        let alarm = AlarmItem(hour: 7, minute: 30)
        XCTAssertEqual(alarm.nextFire(after: now, calendar: cal), date(2026, 10, 12, 7, 30, in: cal.timeZone))
        XCTAssertEqual(AlarmItem(hour: 10, minute: 0).nextFire(after: now, calendar: cal), date(2026, 10, 11, 10, 0, in: cal.timeZone))
    }

    func testNextFireHonorsWeekdaysAndDisabled() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let sunday = date(2026, 10, 11, 9, 0, in: cal.timeZone) // a Sunday
        XCTAssertEqual(cal.component(.weekday, from: sunday), 1)
        let mondays = AlarmItem(hour: 8, minute: 0, weekdays: [2])
        XCTAssertEqual(mondays.nextFire(after: sunday, calendar: cal), date(2026, 10, 12, 8, 0, in: cal.timeZone))
        var off = mondays; off.isEnabled = false
        XCTAssertNil(off.nextFire(after: sunday, calendar: cal))
    }

    func testNextFireAcrossDSTSpringForward() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
        let before = date(2026, 3, 7, 12, 0, in: cal.timeZone) // DST starts Mar 8; 02:30 does not exist
        let fire = AlarmItem(hour: 2, minute: 30).nextFire(after: before, calendar: cal)
        XCTAssertNotNil(fire)
        XCTAssertGreaterThan(fire!, before)
        XCTAssertLessThan(fire!.timeIntervalSince(before), 3 * 86400)
    }

    func testNextAlarmPicksEarliestEnabled() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = date(2026, 10, 11, 6, 0, in: cal.timeZone)
        var off = AlarmItem(hour: 6, minute: 30); off.isEnabled = false
        let alarms = [AlarmItem(hour: 9, minute: 0, label: "b"), off, AlarmItem(hour: 7, minute: 0, label: "a")]
        XCTAssertEqual(AlarmList.next(in: alarms, after: now, calendar: cal)?.0.label, "a")
        XCTAssertEqual(AlarmList.sorted(alarms).map(\.hour), [6, 7, 9])
    }

    // MARK: Agenda fitting
    func testAgendaFitting() {
        XCTAssertEqual(AgendaFitting.visibleCount(total: 3, height: 100, rowHeight: 30, reservedForMore: 18).shown, 3)
        let r = AgendaFitting.visibleCount(total: 10, height: 100, rowHeight: 30, reservedForMore: 18)
        XCTAssertEqual(r.shown, 2)
        XCTAssertEqual(r.more, 8)
        XCTAssertEqual(AgendaFitting.visibleCount(total: 0, height: 100, rowHeight: 30, reservedForMore: 18).shown, 0)
        XCTAssertEqual(AgendaFitting.visibleCount(total: 5, height: 10, rowHeight: 30, reservedForMore: 18).more, 5)
    }

    // MARK: Ported Pinboard-only widgets (Phase 16k)
    func testPortedPinboardTilesHaveFiniteAccentsInEveryPalette() {
        let ported: [TileKind] = [.calculator, .screenTime, .network, .battery, .topApps, .batteries]
        XCTAssertEqual(ported.count, 6, "quickSettings lives on as the Control Center grid, not a tile")
        for tile in ported {
            XCTAssertTrue(TileKind.allCases.contains(tile))
            for palette in TilePalette.allCases {
                let c = palette.accent(for: tile)
                XCTAssertTrue([c.r, c.g, c.b].allSatisfy { (0...1).contains($0) }, "\(palette)/\(tile)")
            }
        }
    }

    // MARK: Control Center widget order (Phase 16n)
    func testControlCenterWidgetParseRoundTripsAndDropsUnknown() {
        XCTAssertEqual(TileKind.parse(nil), TileKind.controlCenterDefault)
        XCTAssertEqual(TileKind.parse(""), [])
        XCTAssertEqual(TileKind.parse("battery,bogus,battery,network"), [.battery, .network])
        XCTAssertEqual(TileKind.parse(TileKind.serialize([.topApps, .calculator])), [.topApps, .calculator])
    }

    // MARK: Event tap (Phase 48a)
    func testEventTapJoinsWebLinksAndFallsBackToTheDay() {
        let utc = TimeZone(identifier: "UTC")!
        let start = date(2026, 10, 16, 9, 0, in: utc)
        let meet = URL(string: "https://meet.google.com/abc-defg-hij")!
        XCTAssertEqual(AgendaEventAction.target(url: meet, start: start), .join(meet))
        let zoom = URL(string: "http://zoom.us/j/42")!
        XCTAssertEqual(AgendaEventAction.target(url: zoom, start: start), .join(zoom), "http counts too")
        // Not links to join: these reveal the day instead of launching a mail client or opening a file.
        XCTAssertEqual(AgendaEventAction.target(url: URL(string: "mailto:owner@example.com"), start: start), .calendar(start))
        XCTAssertEqual(AgendaEventAction.target(url: URL(string: "file:///tmp/note.txt"), start: start), .calendar(start))
        XCTAssertEqual(AgendaEventAction.target(url: nil, start: start), .calendar(start))
    }

    func testCalendarFallbackIsSecondsSince2001() {
        let start = date(2026, 10, 16, 9, 0, in: TimeZone(identifier: "UTC")!)
        let url = AgendaEventAction.calendarURL(for: start)
        XCTAssertEqual(url?.scheme, "calshow")
        XCTAssertEqual(url?.absoluteString, "calshow:\(Int(start.timeIntervalSinceReferenceDate))")
    }
}
