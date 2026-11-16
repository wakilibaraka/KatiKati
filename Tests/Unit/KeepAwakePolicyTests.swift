import XCTest
@testable import KatiKati

final class KeepAwakePolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testManualHoldsAndTimerEnds() {
        var p = KeepAwakePolicy()
        var i = KeepAwakeInputs(manualOn: true, manualEnd: t0.addingTimeInterval(60))
        XCTAssertEqual(p.decide(i, now: t0).reason, .manual)
        XCTAssertEqual(p.decide(i, now: t0.addingTimeInterval(61)).reason, .timerEnded)
        i.manualEnd = nil
        XCTAssertTrue(p.decide(i, now: t0.addingTimeInterval(9999)).hold)
    }

    func testAgentsHoldThenGraceThenRelease() {
        var p = KeepAwakePolicy()
        var i = KeepAwakeInputs(agentsWorking: true)
        XCTAssertEqual(p.decide(i, now: t0).reason, .agents)
        i.agentsWorking = false
        XCTAssertEqual(p.decide(i, now: t0.addingTimeInterval(120)).reason, .grace)
        XCTAssertEqual(p.decide(i, now: t0.addingTimeInterval(181)).reason, .off)
    }

    func testAgentsDisabledIgnoresWork() {
        var p = KeepAwakePolicy()
        XCTAssertFalse(p.decide(KeepAwakeInputs(agentsEnabled: false, agentsWorking: true), now: t0).hold)
    }

    func testBatteryFloorBeatsEverythingOnlyOnBattery() {
        var p = KeepAwakePolicy()
        var i = KeepAwakeInputs(manualOn: true, agentsWorking: true, batteryPercent: 15, onBattery: true, floorPercent: 20)
        XCTAssertEqual(p.decide(i, now: t0), KeepAwakeDecision(hold: false, reason: .batteryLow, lidGuard: false))
        i.onBattery = false
        XCTAssertTrue(p.decide(i, now: t0).hold, "on AC the floor never applies")
        i.onBattery = true; i.batteryPercent = 20
        XCTAssertTrue(p.decide(i, now: t0).hold, "at the floor still holds; below releases")
    }

    func testScrubberTicksSpanOneMinuteToEightHours() {
        let t = PomodoroScrubberMath.ticks
        XCTAssertEqual(t.first, 1)
        XCTAssertEqual(t.last, 480)
        XCTAssertEqual(t, t.sorted())
        XCTAssertEqual(Set(t).count, t.count)
    }

    func testScrubberDragMovesWholeTicksAndClamps() {
        let p = PomodoroScrubberMath.pointsPerTick
        XCTAssertEqual(PomodoroScrubberMath.minutes(start: 5, dragDelta: 0), 5)
        XCTAssertEqual(PomodoroScrubberMath.minutes(start: 5, dragDelta: p * 2), 7)
        XCTAssertEqual(PomodoroScrubberMath.minutes(start: 10, dragDelta: p), 15, "steps coarsen past 10 min")
        XCTAssertEqual(PomodoroScrubberMath.minutes(start: 5, dragDelta: -p * 99), 1)
        XCTAssertEqual(PomodoroScrubberMath.minutes(start: 60, dragDelta: p * 9999), 480)
        XCTAssertEqual(PomodoroScrubberMath.minutes(start: 25, dragDelta: p * 0.9), 25, "under one tick does not move")
        XCTAssertEqual(PomodoroScrubberMath.minutes(start: 25, dragDelta: .nan), 25)
    }

    func testScrubberSnapsOffGridStartAndLabels() {
        XCTAssertEqual(PomodoroScrubberMath.snap(0), 1)
        XCTAssertEqual(PomodoroScrubberMath.snap(9999), 480)
        XCTAssertEqual(PomodoroScrubberMath.snap(27), 25)
        XCTAssertEqual(PomodoroScrubberMath.label(minutes: 25), "25m")
        XCTAssertEqual(PomodoroScrubberMath.label(minutes: 60), "1h")
        XCTAssertEqual(PomodoroScrubberMath.label(minutes: 90), "1h 30m")
        XCTAssertEqual(PomodoroScrubberMath.label(minutes: 480), "8h")
    }

    func testLidGuardNeedsOptInAndNoExternalDisplay() {
        var p = KeepAwakePolicy()
        var i = KeepAwakeInputs(manualOn: true, lidClosedEnabled: true)
        XCTAssertTrue(p.decide(i, now: t0).lidGuard)
        i.externalDisplay = true
        XCTAssertFalse(p.decide(i, now: t0).lidGuard)
        i.externalDisplay = false; i.manualOn = false
        XCTAssertFalse(p.decide(i, now: t0).lidGuard, "no hold, no lid guard")
    }
}
