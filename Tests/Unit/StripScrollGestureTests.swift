import XCTest

final class StripScrollGestureTests: XCTestCase {
    func testAccumulatesUntilTheThreshold() {
        var gesture = StripScrollGesture(stepDistance: 60, cooldown: 0.28)
        XCTAssertNil(gesture.feed(delta: -25, at: 0))
        XCTAssertNil(gesture.feed(delta: -25, at: 0.05))
        XCTAssertEqual(gesture.feed(delta: -25, at: 0.1), .next, "75 pt of travel crosses the 60 pt step")
        XCTAssertEqual(gesture.accumulated, 0, "a step resets the travel")
    }

    func testDirectionFollowsTheDeltaSign() {
        var gesture = StripScrollGesture(stepDistance: 40, cooldown: 0)
        XCTAssertEqual(gesture.feed(delta: -40, at: 0), .next)
        XCTAssertEqual(gesture.feed(delta: 40, at: 1), .previous)
    }

    func testCooldownSwallowsTheRestOfOneFlick() {
        var gesture = StripScrollGesture(stepDistance: 30, cooldown: 0.28)
        XCTAssertEqual(gesture.feed(delta: -30, at: 0), .next)
        // The finger keeps going inside the cooldown window: the travel is kept, the step is not.
        XCTAssertNil(gesture.feed(delta: -30, at: 0.1))
        XCTAssertEqual(gesture.feed(delta: -5, at: 0.3), .next, "past the cooldown, the banked travel steps")
    }

    func testMomentumNeverSteps() {
        var gesture = StripScrollGesture(stepDistance: 20, cooldown: 0)
        XCTAssertEqual(gesture.feed(delta: -20, at: 0), .next)
        XCTAssertNil(gesture.feed(horizontal: 0, vertical: -200, isMomentum: true, at: 0.1))
        XCTAssertNil(gesture.feed(horizontal: 0, vertical: -200, isMomentum: true, at: 0.2))
        XCTAssertEqual(gesture.accumulated, 0, "momentum clears the bank instead of stepping on it")
    }

    func testTheDominantAxisDecides() {
        var gesture = StripScrollGesture(stepDistance: 50, cooldown: 0)
        XCTAssertNil(gesture.feed(horizontal: -5, vertical: -40, isMomentum: false, at: 0),
                     "a mostly-vertical scroll is vertical, so it has only banked 40 of 50")
        XCTAssertEqual(gesture.feed(horizontal: -60, vertical: -5, isMomentum: false, at: 1), .next,
                       "now horizontal dominates") 

        var vertical = StripScrollGesture(stepDistance: 50, cooldown: 0)
        XCTAssertEqual(vertical.feed(horizontal: 2, vertical: 55, isMomentum: false, at: 0), .previous)
    }

    func testResetForgetsTheBank() {
        var gesture = StripScrollGesture(stepDistance: 50, cooldown: 0)
        XCTAssertNil(gesture.feed(delta: -40, at: 0))
        gesture.reset()
        XCTAssertNil(gesture.feed(delta: -40, at: 1), "releasing Option must not leave travel banked")
    }

    func testReversingDirectionDoesNotBankTheOldTravel() {
        var gesture = StripScrollGesture(stepDistance: 50, cooldown: 0)
        XCTAssertNil(gesture.feed(delta: -40, at: 0))
        XCTAssertNil(gesture.feed(delta: 45, at: 1), "the 40 banked forward is discarded, not netted off")
    }
}
