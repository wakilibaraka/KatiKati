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
