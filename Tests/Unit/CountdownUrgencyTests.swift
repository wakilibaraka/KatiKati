import XCTest
@testable import KatiKati

final class CountdownUrgencyTests: XCTestCase {
    func testUrgencyTiersAcrossCountdownThresholds() {
        XCTAssertEqual(CountdownUrgency.tier(secondsUntil: 1200), .neutral)
        XCTAssertEqual(CountdownUrgency.tier(secondsUntil: 900), .accent)
        XCTAssertEqual(CountdownUrgency.tier(secondsUntil: 300), .amber)
        XCTAssertEqual(CountdownUrgency.tier(secondsUntil: 60), .red)
        XCTAssertEqual(CountdownUrgency.tier(secondsUntil: -120), .red)
        XCTAssertEqual(CountdownUrgency.tier(secondsUntil: -400), .accent)
    }

    func testAutoJoinEnforcesSafetyGates() {
        XCTAssertTrue(MeetingAutoJoinPolicy.shouldAutoJoin(
            eventID: "evt-1",
            hasMeetingURL: true,
            secondsUntil: 20,
            isScreenLocked: false,
            idleSeconds: 45,
            alreadyFired: [],
            enabled: true
        ))

        XCTAssertFalse(MeetingAutoJoinPolicy.shouldAutoJoin(
            eventID: "evt-1",
            hasMeetingURL: true,
            secondsUntil: 20,
            isScreenLocked: true,
            idleSeconds: 45,
            alreadyFired: [],
            enabled: true
        ))

        XCTAssertFalse(MeetingAutoJoinPolicy.shouldAutoJoin(
            eventID: "evt-1",
            hasMeetingURL: true,
            secondsUntil: 20,
            isScreenLocked: false,
            idleSeconds: 300,
            alreadyFired: [],
            enabled: true
        ))

        XCTAssertFalse(MeetingAutoJoinPolicy.shouldAutoJoin(
            eventID: "evt-1",
            hasMeetingURL: true,
            secondsUntil: 20,
            isScreenLocked: false,
            idleSeconds: 10,
            alreadyFired: ["evt-1"],
            enabled: true
        ))

        XCTAssertFalse(MeetingAutoJoinPolicy.shouldAutoJoin(
            eventID: "evt-1",
            hasMeetingURL: false,
            secondsUntil: 20,
            isScreenLocked: false,
            idleSeconds: 10,
            alreadyFired: [],
            enabled: true
        ))

        XCTAssertFalse(MeetingAutoJoinPolicy.shouldAutoJoin(
            eventID: "evt-1",
            hasMeetingURL: true,
            secondsUntil: 20,
            isScreenLocked: false,
            idleSeconds: 10,
            alreadyFired: [],
            enabled: false
        ))
    }
}
