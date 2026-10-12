import XCTest
@testable import KatiKati

final class WidgetTallTests: XCTestCase {
    private func tiles() -> [TallTile] {
        [TallTile("clock", min: 150, ideal: 190, flex: 2), TallTile("cal", min: 200, ideal: 280, flex: 3),
         TallTile("lists", min: 200, ideal: 240, flex: 1), TallTile("timers", min: 170, ideal: 200, flex: 1),
         TallTile("notes", min: 120, ideal: 160, flex: 1, optional: 1), TallTile("stop", min: 140, ideal: 170, flex: 1, optional: 2)]
    }
    private func sum(_ p: [(id: String, height: Double)], gap: Double) -> Double {
        p.reduce(0) { $0 + $1.height } + gap * Double(p.count - 1)
    }

    func testShortScreenDropsOptionalTilesButKeepsRequired() {
        let p = TallLayoutPlanner.plan(tiles(), available: 800, gap: 10)
        XCTAssertEqual(p.map(\.id), ["clock", "cal", "lists", "timers"])
        XCTAssertEqual(sum(p, gap: 10), 800, accuracy: 0.5, "leftover is distributed")
    }

    func testTallScreenAddsOptionalsByPriorityAndFillsHeight() {
        let p = TallLayoutPlanner.plan(tiles(), available: 1100, gap: 10)
        XCTAssertEqual(p.map(\.id), ["clock", "cal", "lists", "timers", "notes", "stop"])
        XCTAssertEqual(sum(p, gap: 10), 1100, accuracy: 0.5)
        for (t, h) in zip(tiles(), p) { XCTAssertGreaterThanOrEqual(h.height, t.minHeight - 0.001); XCTAssertLessThanOrEqual(h.height, t.maxHeight + 0.001) }
    }

    func testMiddleScreenFitsOnlyTheHigherPriorityOptional() {
        // required min total = 720 + 30 gaps; notes (120) fits, stopwatch (140) does not.
        let p = TallLayoutPlanner.plan(tiles(), available: 900, gap: 10)
        XCTAssertTrue(p.contains { $0.id == "notes" })
        XCTAssertFalse(p.contains { $0.id == "stop" })
    }

    func testTinyScreenKeepsRequiredAtMinimumAndOverflows() {
        let p = TallLayoutPlanner.plan(tiles(), available: 300, gap: 10)
        XCTAssertEqual(p.map(\.id), ["clock", "cal", "lists", "timers"])
        XCTAssertEqual(p.map(\.height), [150, 200, 200, 170])
    }

    func testFlexWeightsFavourHeavierTilesAndFixedTilesNeverGrow() {
        let t = [TallTile("fixed", min: 100, flex: 0), TallTile("a", min: 100, ideal: 300, flex: 3), TallTile("b", min: 100, ideal: 300, flex: 1)]
        let p = TallLayoutPlanner.plan(t, available: 400, gap: 0)
        XCTAssertEqual(p[0].height, 100)
        XCTAssertGreaterThan(p[1].height, p[2].height)
        XCTAssertEqual(p.reduce(0) { $0 + $1.height }, 400, accuracy: 0.5)
        // Everything capped → stack stays shorter than the screen instead of stretching forever.
        let capped = TallLayoutPlanner.plan([TallTile("x", min: 100, ideal: 120, max: 150)], available: 1000, gap: 0)
        XCTAssertEqual(capped[0].height, 150)
    }

    func testAnimationTimingAndReduceMotion() {
        XCTAssertEqual(WidgetAnimationTiming.effective(.slide, reduceMotion: true), .instant)
        XCTAssertEqual(WidgetAnimationTiming.effective(.springPop, reduceMotion: false), .springPop)
        XCTAssertEqual(WidgetAnimationTiming.staggerDelay(forTile: 0), 0)
        XCTAssertEqual(WidgetAnimationTiming.staggerDelay(forTile: 3), 0.105, accuracy: 1e-9)
        XCTAssertEqual(WidgetAnimationTiming.staggerDelay(forTile: 99), WidgetAnimationTiming.staggerDelay(forTile: 8), "stagger is capped")
        XCTAssertEqual(WidgetAnimationTiming.closeDelay(.instant), 0)
        XCTAssertGreaterThan(WidgetAnimationTiming.closeDelay(.slide), 0)
        XCTAssertEqual(WidgetAnimationTiming.slideStartX(target: 0, width: 420, side: .right, screenMinX: 0, screenMaxX: 1728), 1736)
        XCTAssertEqual(WidgetAnimationTiming.slideStartX(target: 0, width: 420, side: .left, screenMinX: 0, screenMaxX: 1728), -428)
        XCTAssertEqual(WidgetAnimationPreset.default, .slide)
    }

    func testCountdownTimerLifecycle() {
        var t = CountdownTimerModel()
        XCTAssertEqual(t.remaining, 300)
        XCTAssertFalse(t.tick(), "idle timers do not tick")
        t.set(seconds: 3); t.toggle()
        XCTAssertFalse(t.tick()); XCTAssertFalse(t.tick()); XCTAssertTrue(t.tick())
        XCTAssertTrue(t.isFinished); XCTAssertFalse(t.isRunning); XCTAssertEqual(t.remaining, 0)
        t.toggle() // finished → reset + start
        XCTAssertEqual(t.remaining, 3); XCTAssertTrue(t.isRunning)
        t.reset(); XCTAssertEqual(t.remaining, 3); XCTAssertFalse(t.isRunning)
    }

    func testCountdownAdjustClampsAndRunningShifts() {
        var t = CountdownTimerModel()
        t.set(seconds: 10_000); XCTAssertEqual(t.total, CountdownTimerModel.maxSeconds)
        t.set(seconds: -5); XCTAssertEqual(t.total, 0)
        t.toggle(); XCTAssertFalse(t.isRunning, "a zero timer cannot start")
        t.set(seconds: 60); t.adjust(by: 60); XCTAssertEqual(t.total, 120)
        t.toggle(); t.adjust(by: 30); XCTAssertEqual(t.remaining, 150)
        XCTAssertEqual(t.progress, 0, accuracy: 0.001)
        t.tick(); XCTAssertEqual(CountdownTimerModel.label(t.remaining), "02:29")
    }

    func testStopwatchAccumulatesAcrossPausesAndLaps() {
        let t0 = Date(timeIntervalSince1970: 1000)
        var s = StopwatchModel()
        XCTAssertEqual(s.elapsed(at: t0), 0)
        s.lap(at: t0); XCTAssertTrue(s.laps.isEmpty, "laps need a running watch")
        s.toggle(at: t0)
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(5)), 5, accuracy: 1e-9)
        s.lap(at: t0.addingTimeInterval(5))
        s.toggle(at: t0.addingTimeInterval(8))           // paused at 8s
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(100)), 8, accuracy: 1e-9)
        s.toggle(at: t0.addingTimeInterval(100))          // resume
        s.lap(at: t0.addingTimeInterval(102))             // 8 + 2 = 10s
        XCTAssertEqual(s.splits, [5, 5])
        XCTAssertEqual(StopwatchModel.label(75.678), "01:15.67")
        s.reset(); XCTAssertEqual(s.elapsed(at: t0), 0); XCTAssertTrue(s.laps.isEmpty)
    }

    func testEventCountdownDaysAndOrdering() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 23))!
        func ev(_ l: String, _ d: Int) -> EventCountdown { EventCountdown(label: l, date: cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: 1))!) }
        XCTAssertEqual(ev("tomorrow", 12).daysRemaining(from: now, calendar: cal), 1, "calendar days, not 24h blocks")
        XCTAssertEqual(ev("today", 11).daysRemaining(from: now, calendar: cal), 0)
        XCTAssertEqual(ev("past", 8).daysRemaining(from: now, calendar: cal), -3)
        let ordered = EventCountdown.ordered([ev("past", 8), ev("far", 30), ev("soon", 12), ev("older", 1)], now: now, calendar: cal)
        XCTAssertEqual(ordered.map(\.label), ["soon", "far", "past", "older"])
        let many = (1...10).map { ev("e\($0)", 12 + $0) }
        XCTAssertEqual(EventCountdown.ordered(many, now: now, calendar: cal).count, EventCountdown.limit)
    }

    func testTallLayoutVocabulary() {
        XCTAssertEqual(CalendarPanelLayout.tall.width(forScreenWidth: 1728), 420)
        XCTAssertTrue(CalendarPanelLayout.tall.fillsHeight)
        XCTAssertFalse(CalendarPanelLayout.mac.fillsHeight)
        XCTAssertEqual(CalendarPanelLayout.allCases, [.mac, .ipad, .tall], "old presets are kept")
    }
}

final class WidgetPanelSettingsTests: XCTestCase {
    func testFreshInstallsGetTallAndStoredChoicesAreKept() {
        let suite = TestDefaults.make("widget-layout", for: self)
        XCTAssertEqual(CalendarPanelLayout.resolve(defaults: suite), .tall)
        XCTAssertEqual(suite.string(forKey: CalendarPanelLayout.storageKey), "tall", "default is persisted")
        suite.set("ipad", forKey: CalendarPanelLayout.storageKey)
        XCTAssertEqual(CalendarPanelLayout.resolve(defaults: suite), .ipad)

        let legacy = TestDefaults.make("widget-layout", for: self)
        legacy.set("compact420", forKey: "com.katikati.calendar.panelPreset")
        XCTAssertEqual(CalendarPanelLayout.resolve(defaults: legacy), .mac, "old size preset still maps to the old Mac layout")
    }

    func testAnimationPresetDefaultsStoredValueAndReduceMotion() {
        let suite = TestDefaults.make("widget-anim", for: self)
        XCTAssertEqual(WidgetAnimationPreset.resolve(defaults: suite, reduceMotion: false), .slide)
        suite.set("springPop", forKey: WidgetAnimationPreset.storageKey)
        XCTAssertEqual(WidgetAnimationPreset.resolve(defaults: suite, reduceMotion: false), .springPop)
        XCTAssertEqual(WidgetAnimationPreset.resolve(defaults: suite, reduceMotion: true), .instant)
        suite.set("bogus", forKey: WidgetAnimationPreset.storageKey)
        XCTAssertEqual(WidgetAnimationPreset.resolve(defaults: suite, reduceMotion: false), .slide)
    }
}
