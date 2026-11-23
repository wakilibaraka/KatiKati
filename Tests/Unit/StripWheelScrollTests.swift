import XCTest
@testable import KatiKati

final class StripWheelScrollTests: XCTestCase {
    private func input(dx: CGFloat = 0,
                       dy: CGFloat,
                       precise: Bool,
                       inverted: Bool) -> StripWheelScroll.Input {
        StripWheelScroll.Input(deltaX: dx, deltaY: dy,
                               hasPreciseDeltas: precise, isDirectionInverted: inverted)
    }

    // MARK: - 不接管的情形

    func testNoVerticalComponentIsNotClaimed() {
        XCTAssertNil(StripWheelScroll.horizontalStep(for: input(dx: 12, dy: 0, precise: true, inverted: true)))
        XCTAssertNil(StripWheelScroll.horizontalStep(for: input(dy: 0, precise: false, inverted: false)))
    }

    /// 横向为主的手势必须放行给 `NSScrollView`——它的惯性和橡皮筋是原生的，接管过来只会更差。
    func testHorizontallyDominantGestureIsNotClaimed() {
        XCTAssertNil(StripWheelScroll.horizontalStep(for: input(dx: 30, dy: 4, precise: true, inverted: true)))
        XCTAssertNil(StripWheelScroll.horizontalStep(for: input(dx: -30, dy: 4, precise: true, inverted: true)))
        // 相等也算横向为主：只有严格「垂直压过横向」才接管。
        XCTAssertNil(StripWheelScroll.horizontalStep(for: input(dx: 8, dy: 8, precise: true, inverted: true)))
    }

    func testVerticallyDominantGestureIsClaimedEvenWithSomeHorizontalDrift() {
        XCTAssertNotNil(StripWheelScroll.horizontalStep(for: input(dx: 3, dy: 20, precise: true, inverted: true)))
    }

    // MARK: - 离散滚轮（带格子的鼠标）

    /// 这四格必须与改动前 `sign * deltaY * 56` 的结果逐值一致——手感是已签收的。
    func testDiscreteWheelMatchesTheShippedFeel() {
        let table: [(dy: CGFloat, inverted: Bool, expected: CGFloat)] = [
            (1, false, 56), (-1, false, -56),
            (1, true, -56), (-1, true, 56),
        ]
        for row in table {
            XCTAssertEqual(
                StripWheelScroll.horizontalStep(for: input(dy: row.dy, precise: false, inverted: row.inverted)),
                row.expected,
                "dy=\(row.dy) inverted=\(row.inverted)"
            )
        }
    }

    func testDiscreteWheelStepIsClamped() {
        XCTAssertEqual(StripWheelScroll.horizontalStep(for: input(dy: 10, precise: false, inverted: false)),
                       StripWheelScroll.maxStep)
        XCTAssertEqual(StripWheelScroll.horizontalStep(for: input(dy: -10, precise: false, inverted: false)),
                       -StripWheelScroll.maxStep)
    }

    // MARK: - 连续事件（触控板 / 妙控鼠标 / 平滑滚轮）

    /// 连续事件的 delta 本来就是点数：1:1 搬运，既不乘 `wheelSpeed` 也不封顶
    /// （惯性阶段的大 delta 正是它该有的手感）。
    func testPreciseDeltasArePassedThroughOneToOne() {
        let table: [(dy: CGFloat, inverted: Bool, expected: CGFloat)] = [
            (7, false, 7), (-7, false, -7),
            (7, true, -7), (-7, true, 7),
            (400, true, -400),
        ]
        for row in table {
            XCTAssertEqual(
                StripWheelScroll.horizontalStep(for: input(dy: row.dy, precise: true, inverted: row.inverted)),
                row.expected,
                "dy=\(row.dy) inverted=\(row.inverted)"
            )
        }
    }

    /// 同一个 delta，连续事件绝不能被当成离散滚轮放大——那会一下甩到头。
    func testPreciseDeltasAreNotAmplifiedLikeAWheelNotch() {
        let precise = StripWheelScroll.horizontalStep(for: input(dy: 1, precise: true, inverted: false))
        let discrete = StripWheelScroll.horizontalStep(for: input(dy: 1, precise: false, inverted: false))
        XCTAssertEqual(precise, 1)
        XCTAssertEqual(discrete, StripWheelScroll.wheelSpeed)
    }
}

/// Slice E (OpenTaskbar): the wheel's decision table and the window cycle it lands on.
final class WheelActionMapTests: XCTestCase {
    private func input(dx: CGFloat = 0, dy: CGFloat, precise: Bool = false, inverted: Bool = false) -> StripWheelScroll.Input {
        StripWheelScroll.Input(deltaX: dx, deltaY: dy, hasPreciseDeltas: precise, isDirectionInverted: inverted)
    }

    func testOverflowScrollingKeepsPriorityOverEveryNewAction() {
        let step = WheelActionMap.action(for: input(dy: 2),
                                         target: .appCard(bundleID: "com.apple.Safari"),
                                         stripOverflows: true)
        XCTAssertEqual(step, .scrollStrip(by: StripWheelScroll.horizontalStep(for: input(dy: 2))!))
    }

    func testWheelOverACardCyclesThatAppsWindows() {
        XCTAssertEqual(WheelActionMap.action(for: input(dy: 1), target: .appCard(bundleID: "com.apple.Safari"),
                                             stripOverflows: false),
                       .cycleWindows(bundleID: "com.apple.Safari", direction: .next))
        XCTAssertEqual(WheelActionMap.action(for: input(dy: -1), target: .appCard(bundleID: "com.apple.Safari"),
                                             stripOverflows: false),
                       .cycleWindows(bundleID: "com.apple.Safari", direction: .previous))
    }

    func testWheelOverEmptyBarTurnsTheVolumeAndRespectsNaturalScrolling() {
        XCTAssertEqual(WheelActionMap.action(for: input(dy: 1), target: .emptyBar, stripOverflows: false),
                       .volume(delta: WheelActionMap.volumeStepPerNotch))
        XCTAssertEqual(WheelActionMap.action(for: input(dy: -1), target: .emptyBar, stripOverflows: false),
                       .volume(delta: -WheelActionMap.volumeStepPerNotch))
        XCTAssertEqual(WheelActionMap.action(for: input(dy: 1, inverted: true), target: .emptyBar, stripOverflows: false),
                       .volume(delta: -WheelActionMap.volumeStepPerNotch))
        XCTAssertEqual(WheelActionMap.action(for: input(dy: 4, precise: true), target: .emptyBar, stripOverflows: false),
                       .volume(delta: WheelActionMap.preciseVolumeStep))
    }

    func testOtherChromeAndHorizontalGesturesAreLeftAlone() {
        XCTAssertEqual(WheelActionMap.action(for: input(dy: 1), target: .otherSurface, stripOverflows: false), .ignore)
        XCTAssertEqual(WheelActionMap.action(for: input(dx: 20, dy: 2), target: .emptyBar, stripOverflows: false), .ignore)
        XCTAssertEqual(WheelActionMap.action(for: input(dx: 20, dy: 0), target: .emptyBar, stripOverflows: false), .ignore)
    }

    func testWindowCycleWrapsBothWaysAndFallsBackToTheFirstWindow() {
        let ids = ["a", "b", "c"]
        XCTAssertEqual(WheelWindowCycle.next(ids: ids, front: "b", direction: .next), "c")
        XCTAssertEqual(WheelWindowCycle.next(ids: ids, front: "c", direction: .next), "a")
        XCTAssertEqual(WheelWindowCycle.next(ids: ids, front: "a", direction: .previous), "c")
        XCTAssertEqual(WheelWindowCycle.next(ids: ids, front: nil, direction: .next), "a")
        XCTAssertEqual(WheelWindowCycle.next(ids: ["only"], front: "only", direction: .previous), "only")
        XCTAssertNil(WheelWindowCycle.next(ids: [], front: nil, direction: .next))
    }

    func testWheelVolumeThrottleAccumulatesPreciseDeltasAndRateLimits() {
        var state = WheelVolumeThrottle.State()
        let t0 = Date(timeIntervalSince1970: 1000)

        // Precise events (0.02 each) accumulate until reaching 0.05
        XCTAssertNil(WheelVolumeThrottle.consume(delta: 0.02, state: &state, now: t0))
        XCTAssertNil(WheelVolumeThrottle.consume(delta: 0.02, state: &state, now: t0.addingTimeInterval(0.01)))
        XCTAssertEqual(WheelVolumeThrottle.consume(delta: 0.02, state: &state, now: t0.addingTimeInterval(0.02)),
                       WheelActionMap.preciseVolumeStep)

        // Burst within 60 ms is throttled even if threshold is crossed
        XCTAssertNil(WheelVolumeThrottle.consume(delta: 0.05, state: &state, now: t0.addingTimeInterval(0.04)))
        // After 60 ms, a discrete notch passes immediately
        XCTAssertEqual(WheelVolumeThrottle.consume(delta: 0.05, state: &state, now: t0.addingTimeInterval(0.09)), 0.05)
    }

    func testOptionPressedTriggersTimeTravelBeforeOverflowOrVolume() {
        let optUp = StripWheelScroll.Input(deltaX: 0, deltaY: 4, hasPreciseDeltas: true, isDirectionInverted: false, isOptionPressed: true)
        let optDown = StripWheelScroll.Input(deltaX: 0, deltaY: -4, hasPreciseDeltas: true, isDirectionInverted: false, isOptionPressed: true)
        XCTAssertEqual(WheelActionMap.action(for: optUp, target: .appCard(bundleID: "com.apple.Safari"), stripOverflows: true), .timeTravel(delta: -1))
        XCTAssertEqual(WheelActionMap.action(for: optDown, target: .emptyBar, stripOverflows: false), .timeTravel(delta: 1))

        let optHoriz = StripWheelScroll.Input(deltaX: 25, deltaY: 2, hasPreciseDeltas: true, isDirectionInverted: false, isOptionPressed: true)
        XCTAssertEqual(WheelActionMap.action(for: optHoriz, target: .emptyBar, stripOverflows: false), .ignore)
    }

    func testWidgetPageCycleWrapsForwardBackwardAndClamps() {
        XCTAssertEqual(WidgetPageCycle.clamped(-3, count: 4), 0)
        XCTAssertEqual(WidgetPageCycle.clamped(9, count: 4), 3)
        XCTAssertEqual(WidgetPageCycle.clamped(2, count: 0), 0)

        XCTAssertEqual(WidgetPageCycle.next(current: 0, count: 3, delta: 1), 1)
        XCTAssertEqual(WidgetPageCycle.next(current: 2, count: 3, delta: 1), 0)
        XCTAssertEqual(WidgetPageCycle.next(current: 0, count: 3, delta: -1), 2)
        XCTAssertEqual(WidgetPageCycle.next(current: 5, count: 1, delta: 1), 0)
    }

    func testWidgetPageScrollEngineIgnoresMomentumAndLocksOnePagePerSwipe() {
        var state = WidgetPageScrollEngine.State()

        func precise(_ dy: CGFloat, phase: WidgetPageScrollPhase, momentum: Bool = false, t: TimeInterval = 1) -> Int? {
            WidgetPageScrollEngine.consume(
                WidgetPageScrollInput(deltaX: 0, deltaY: dy, hasPreciseDeltas: true,
                                      isMomentum: momentum, phase: phase, timestamp: t),
                state: &state
            )
        }

        XCTAssertNil(precise(-10, phase: .began, t: 1.0))
        XCTAssertNil(precise(-12, phase: .changed, t: 1.02))
        // Crosses 28pt threshold -> advances +1 page and locks gesture
        XCTAssertEqual(precise(-8, phase: .changed, t: 1.04), 1)
        XCTAssertTrue(state.lockedForGesture)
        // Further deltas and momentum events in the same gesture do not flip again
        XCTAssertNil(precise(-40, phase: .changed, t: 1.06))
        XCTAssertNil(precise(-35, phase: .changed, momentum: true, t: 1.08))
        XCTAssertNil(precise(0, phase: .ended, t: 1.12))
        XCTAssertFalse(state.lockedForGesture)

        // Fresh upward swipe goes backward -1
        XCTAssertNil(precise(16, phase: .began, t: 2.0))
        XCTAssertEqual(precise(15, phase: .changed, t: 2.03), -1)
    }

    func testWidgetPageScrollEngineDiscreteWheelAppliesCooldown() {
        var state = WidgetPageScrollEngine.State()

        func discrete(_ dy: CGFloat, t: TimeInterval) -> Int? {
            WidgetPageScrollEngine.consume(
                WidgetPageScrollInput(deltaX: 0, deltaY: dy, hasPreciseDeltas: false,
                                      isMomentum: false, phase: .discrete, timestamp: t),
                state: &state
            )
        }

        XCTAssertEqual(discrete(-1, t: 10.0), 1)
        XCTAssertNil(discrete(-1, t: 10.10))
        XCTAssertEqual(discrete(1, t: 10.25), -1)
    }
}
