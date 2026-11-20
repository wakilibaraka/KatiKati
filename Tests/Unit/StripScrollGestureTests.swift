import XCTest

final class StripScrollGestureTests: XCTestCase {
    func testAccumulatesUntilTheThreshold() {
        var gesture = StripScrollGesture(stepDistance: 60, cooldown: 0.28)
        XCTAssertNil(gesture.feed(delta: -25, isMomentum: false, at: 0))
        XCTAssertNil(gesture.feed(delta: -25, isMomentum: false, at: 0.05))
        XCTAssertEqual(gesture.feed(delta: -25, isMomentum: false, at: 0.1), .next,
                       "75 pt of travel crosses the 60 pt step")
        XCTAssertEqual(gesture.accumulated, 0, "a step resets the travel")
    }

    func testDirectionFollowsTheDeltaSign() {
        var gesture = StripScrollGesture(stepDistance: 40, cooldown: 0)
        XCTAssertEqual(gesture.feed(delta: -40, isMomentum: false, at: 0), .next)
        XCTAssertEqual(gesture.feed(delta: 40, isMomentum: false, at: 1), .previous)
    }

    func testCooldownSwallowsTheRestOfOneFlick() {
        var gesture = StripScrollGesture(stepDistance: 30, cooldown: 0.28)
        XCTAssertEqual(gesture.feed(delta: -30, isMomentum: false, at: 0), .next)
        // The finger keeps going inside the cooldown window: the travel is kept, the step is not.
        XCTAssertNil(gesture.feed(delta: -30, isMomentum: false, at: 0.1))
        XCTAssertEqual(gesture.feed(delta: -5, isMomentum: false, at: 0.3), .next,
                       "past the cooldown, the banked travel steps")
    }

    func testMomentumNeverSteps() {
        var gesture = StripScrollGesture(stepDistance: 20, cooldown: 0)
        XCTAssertEqual(gesture.feed(delta: -20, isMomentum: false, at: 0), .next)
        XCTAssertNil(gesture.feed(delta: -200, isMomentum: true, at: 0.1))
        XCTAssertNil(gesture.feed(delta: -200, isMomentum: true, at: 0.2))
        XCTAssertEqual(gesture.accumulated, 0, "momentum clears the bank instead of stepping on it")
    }

    func testResetForgetsTheBank() {
        var gesture = StripScrollGesture(stepDistance: 50, cooldown: 0)
        XCTAssertNil(gesture.feed(delta: -40, isMomentum: false, at: 0))
        gesture.reset()
        XCTAssertNil(gesture.feed(delta: -40, isMomentum: false, at: 1),
                     "releasing Option must not leave travel banked")
    }

    func testReversingDirectionDoesNotBankTheOldTravel() {
        var gesture = StripScrollGesture(stepDistance: 50, cooldown: 0)
        XCTAssertNil(gesture.feed(delta: -40, isMomentum: false, at: 0))
        XCTAssertNil(gesture.feed(delta: 45, isMomentum: false, at: 1),
                     "the 40 banked forward is discarded, not netted off")
    }

    func testWheelNotchScalingCrossesTheThreshold() {
        // The service scales a non-precise notch by 10 pt before feeding it: two 3-notch events are
        // 60 pt of travel even though the raw deltas are single digits.
        var gesture = StripScrollGesture(stepDistance: 60, cooldown: 0)
        XCTAssertNil(gesture.feed(delta: -30, isMomentum: false, at: 0), "one notch is not enough")
        XCTAssertEqual(gesture.feed(delta: -30, isMomentum: false, at: 0.2), .next)
    }
}
