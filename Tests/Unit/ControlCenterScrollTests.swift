import XCTest
@testable import KatiKati

/// 57a: the wheel-to-volume table behind the Control Center volume row.
final class ControlCenterScrollTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    func testPreciseTrackpadTravelAddsUpToSteps() {
        var state = ControlCenterScroll.State()
        // 3 pt is half a step: nothing yet, and nothing lost.
        XCTAssertNil(ControlCenterScroll.consume(deltaY: 3, precise: true, level: 0.5, state: &state, now: t0))
        // The other 3 pt completes it, upward.
        XCTAssertEqual(ControlCenterScroll.consume(deltaY: 3, precise: true, level: 0.5, state: &state, now: t0 + 0.1),
                       0.5 + ControlCenterScroll.volumePerStep)
        // Downward at the next tick, from the new level.
        XCTAssertEqual(ControlCenterScroll.consume(deltaY: -6, precise: true, level: 0.5125, state: &state, now: t0 + 0.2),
                       0.5125 - ControlCenterScroll.volumePerStep)
    }

    func testOneEventCanCarrySeveralSteps() {
        var state = ControlCenterScroll.State()
        XCTAssertEqual(ControlCenterScroll.consume(deltaY: 18, precise: true, level: 0.2, state: &state, now: t0),
                       0.2 + 3 * ControlCenterScroll.volumePerStep)
    }

    func testRateLimitHoldsASecondStepBackUntilTheIntervalPasses() {
        var state = ControlCenterScroll.State()
        _ = ControlCenterScroll.consume(deltaY: 6, precise: true, level: 0.4, state: &state, now: t0)
        // Enough travel, but 40 ms after the last step: the level must not move.
        XCTAssertNil(ControlCenterScroll.consume(deltaY: 6, precise: true, level: 0.4125, state: &state, now: t0 + 0.04))
        // The travel was kept, so the next event past the interval spends it.
        XCTAssertEqual(ControlCenterScroll.consume(deltaY: 0.0001, precise: true, level: 0.4125, state: &state, now: t0 + 0.061),
                       0.4125 + ControlCenterScroll.volumePerStep)
    }

    func testClampedAtBothEnds() {
        var state = ControlCenterScroll.State()
        XCTAssertEqual(ControlCenterScroll.consume(deltaY: 60, precise: true, level: 0.99, state: &state, now: t0), 1)
        var other = ControlCenterScroll.State()
        XCTAssertEqual(ControlCenterScroll.consume(deltaY: -60, precise: true, level: 0.01, state: &other, now: t0), 0)
    }

    func testNotchedWheelCountsOneClickAsTwoStepsWhateverItsLineSize() {
        for lines in [CGFloat(1), 3, 0.5] {
            var state = ControlCenterScroll.State()
            let up = ControlCenterScroll.consume(deltaY: lines, precise: false, level: 0.5, state: &state, now: t0)
            XCTAssertEqual(up, 0.5 + 2 * ControlCenterScroll.volumePerStep, "up, line size \(lines)")
            var down = ControlCenterScroll.State()
            XCTAssertEqual(ControlCenterScroll.consume(deltaY: -lines, precise: false, level: 0.5, state: &down, now: t0),
                           0.5 - 2 * ControlCenterScroll.volumePerStep, "down, line size \(lines)")
        }
    }

    func testNoiseIsIgnored() {
        var state = ControlCenterScroll.State()
        XCTAssertNil(ControlCenterScroll.consume(deltaY: 0, precise: true, level: 0.5, state: &state, now: t0))
        XCTAssertEqual(state, ControlCenterScroll.State())
    }
}
