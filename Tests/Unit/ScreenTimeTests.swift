import XCTest
@testable import KatiKati

final class ScreenTimeTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter(); f.timeZone = cal.timeZone
        return f.date(from: s)!
    }

    func testAdvanceCreditsCurrentAppOnlyWhileCounting() {
        var ledger = ScreenTimeLedger()
        var t = ScreenTimeTracker()
        let t0 = date("2026-10-12T10:00:00Z")
        t.appActivated(bundleID: "a", name: "A", at: t0, ledger: &ledger, calendar: cal)
        t.advance(to: t0.addingTimeInterval(30), ledger: &ledger, calendar: cal)
        XCTAssertEqual(ledger.total(day: "2026-10-12"), 0, "not counting yet")
        t.setCounting(true, at: t0.addingTimeInterval(30), ledger: &ledger, calendar: cal)
        t.advance(to: t0.addingTimeInterval(90), ledger: &ledger, calendar: cal)
        XCTAssertEqual(ledger.seconds(bundleID: "a", day: "2026-10-12"), 60)
        XCTAssertEqual(ledger.names["a"], "A")
    }

    func testSwitchingAppsSplitsTime() {
        var ledger = ScreenTimeLedger()
        var t = ScreenTimeTracker()
        let t0 = date("2026-10-12T10:00:00Z")
        t.setCounting(true, at: t0, ledger: &ledger, calendar: cal)
        t.appActivated(bundleID: "a", name: "A", at: t0, ledger: &ledger, calendar: cal)
        t.appActivated(bundleID: "b", name: "B", at: t0.addingTimeInterval(50), ledger: &ledger, calendar: cal)
        t.advance(to: t0.addingTimeInterval(80), ledger: &ledger, calendar: cal)
        XCTAssertEqual(ledger.seconds(bundleID: "a", day: "2026-10-12"), 50)
        XCTAssertEqual(ledger.seconds(bundleID: "b", day: "2026-10-12"), 30)
    }

    func testPausingStopsCredit() {
        var ledger = ScreenTimeLedger()
        var t = ScreenTimeTracker()
        let t0 = date("2026-10-12T10:00:00Z")
        t.setCounting(true, at: t0, ledger: &ledger, calendar: cal)
        t.appActivated(bundleID: "a", name: "A", at: t0, ledger: &ledger, calendar: cal)
        t.setCounting(false, at: t0.addingTimeInterval(40), ledger: &ledger, calendar: cal)
        t.advance(to: t0.addingTimeInterval(400), ledger: &ledger, calendar: cal)
        XCTAssertEqual(ledger.total(day: "2026-10-12"), 40)
    }

    func testLongGapIsNotCredited() {
        var ledger = ScreenTimeLedger()
        var t = ScreenTimeTracker()
        let t0 = date("2026-10-12T10:00:00Z")
        t.setCounting(true, at: t0, ledger: &ledger, calendar: cal)
        t.appActivated(bundleID: "a", name: "A", at: t0, ledger: &ledger, calendar: cal)
        t.advance(to: t0.addingTimeInterval(3600), ledger: &ledger, calendar: cal) // machine slept
        XCTAssertEqual(ledger.total(day: "2026-10-12"), ScreenTimeTracker.maxCreditedGap)
    }

    func testMidnightSplit() {
        var ledger = ScreenTimeLedger()
        var t = ScreenTimeTracker()
        let t0 = date("2026-10-12T23:59:30Z")
        t.setCounting(true, at: t0, ledger: &ledger, calendar: cal)
        t.appActivated(bundleID: "a", name: "A", at: t0, ledger: &ledger, calendar: cal)
        t.advance(to: t0.addingTimeInterval(60), ledger: &ledger, calendar: cal)
        XCTAssertEqual(ledger.seconds(bundleID: "a", day: "2026-10-12"), 30)
        XCTAssertEqual(ledger.seconds(bundleID: "a", day: "2026-10-13"), 30)
    }

    func testTopWeekAndPrune() {
        var l = ScreenTimeLedger()
        l.add(bundleID: "a", name: "A", seconds: 100, day: "2026-10-12")
        l.add(bundleID: "b", name: "B", seconds: 300, day: "2026-10-12")
        l.add(bundleID: "c", name: "C", seconds: 5, day: "2026-07-01")
        XCTAssertEqual(l.top(day: "2026-10-12", limit: 1).map(\.bundleID), ["b"])
        let w = l.week(endingAt: date("2026-10-12T12:00:00Z"), calendar: cal)
        XCTAssertEqual(w.count, 7); XCTAssertEqual(w.last?.seconds, 400); XCTAssertEqual(w.first?.seconds, 0)
        l.prune(keepDays: 90, now: date("2026-10-12T12:00:00Z"), calendar: cal)
        XCTAssertNil(l.days["2026-07-01"]); XCTAssertNil(l.names["c"]); XCTAssertEqual(l.names["a"], "A")
    }

    func testIgnoresEmptyAndNonPositive() {
        var l = ScreenTimeLedger()
        l.add(bundleID: "", name: "x", seconds: 5, day: "d")
        l.add(bundleID: "a", name: "A", seconds: 0, day: "d")
        XCTAssertTrue(l.days.isEmpty)
    }

    func testAwayAndFormat() {
        XCTAssertTrue(ScreenTimeTracker.isAway(idleSeconds: 120, screenAsleep: false))
        XCTAssertTrue(ScreenTimeTracker.isAway(idleSeconds: 0, screenAsleep: true))
        XCTAssertFalse(ScreenTimeTracker.isAway(idleSeconds: 5, screenAsleep: false))
        XCTAssertEqual(ScreenTimeLedger.format(59 * 60), "59m")
        XCTAssertEqual(ScreenTimeLedger.format(3720), "1h 2m")
    }
}

final class ScreenTimeStoreTests: XCTestCase {
    private func url() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("st-\(UUID().uuidString)/screentime.json") }

    func testRoundTripAndDelete() throws {
        let store = ScreenTimeStore(url: url())
        var l = ScreenTimeLedger()
        l.add(bundleID: "a", name: "A", seconds: 42, day: "2026-10-12")
        try store.save(l)
        XCTAssertEqual(store.load(), l)
        store.deleteAll()
        XCTAssertEqual(store.load(), ScreenTimeLedger())
    }

    func testCorruptFileMovedAside() throws {
        let u = url()
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: u)
        XCTAssertEqual(ScreenTimeStore(url: u).load(), ScreenTimeLedger())
        XCTAssertTrue(FileManager.default.fileExists(atPath: u.appendingPathExtension("bak").path))
    }
}

final class ScreenTimeLimitTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testParseSerializeClampsAndDropsGarbage() {
        XCTAssertEqual(ScreenTimeLimits.parse("a.b:60, c:1,d:9999,bad,:5,e:x"), ["a.b": 60, "c": 5, "d": 720])
        XCTAssertEqual(ScreenTimeLimits.serialize(["b": 30, "a": 60]), "a:60,b:30")
        XCTAssertEqual(ScreenTimeLimits.parse(nil), [:])
    }

    func testNoLimitNoAction() {
        var s = ScreenTimeLimitState()
        XCTAssertNil(s.evaluate(bundleID: "a", usedSeconds: 9999, limitMinutes: nil, now: now, day: "d"))
    }

    func testWarnsOncePerDayThenReached() {
        var s = ScreenTimeLimitState()
        XCTAssertNil(s.evaluate(bundleID: "a", usedSeconds: 50 * 60, limitMinutes: 60, now: now, day: "d"))
        XCTAssertEqual(s.evaluate(bundleID: "a", usedSeconds: 56 * 60, limitMinutes: 60, now: now, day: "d"), .warn(minutesLeft: 4))
        XCTAssertNil(s.evaluate(bundleID: "a", usedSeconds: 57 * 60, limitMinutes: 60, now: now, day: "d"), "once")
        XCTAssertEqual(s.evaluate(bundleID: "a", usedSeconds: 60 * 60, limitMinutes: 60, now: now, day: "d"), .reached)
        XCTAssertEqual(s.evaluate(bundleID: "a", usedSeconds: 10, limitMinutes: 60, now: now, day: "d2"), nil)
    }

    func testReachedRepromptsAfterSnoozeWindowOnly() {
        var s = ScreenTimeLimitState()
        XCTAssertEqual(s.evaluate(bundleID: "a", usedSeconds: 4000, limitMinutes: 60, now: now, day: "d"), .reached)
        XCTAssertNil(s.evaluate(bundleID: "a", usedSeconds: 4010, limitMinutes: 60, now: now.addingTimeInterval(60), day: "d"))
        XCTAssertEqual(s.evaluate(bundleID: "a", usedSeconds: 4300, limitMinutes: 60, now: now.addingTimeInterval(301), day: "d"), .reached)
    }

    func testDismissForTodayQuietsUntilMidnight() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        var s = ScreenTimeLimitState()
        s.dismissForToday("a", now: now, calendar: cal)
        XCTAssertNil(s.evaluate(bundleID: "a", usedSeconds: 9999, limitMinutes: 10, now: now.addingTimeInterval(3600 * 5), day: "d"))
        XCTAssertNotNil(s.evaluate(bundleID: "a", usedSeconds: 9999, limitMinutes: 10, now: now.addingTimeInterval(3600 * 30), day: "d2"))
    }
}
