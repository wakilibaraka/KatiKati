import XCTest
@testable import KatiKati

/// Ported from Spacewalk (MIT, © 2026 InsaneArts) along with the code, so the index arithmetic and
/// the fixed-point sign rules are pinned rather than assumed.
final class SpaceSwitchPlanTests: XCTestCase {
    // MARK: Plan

    func testStepsForwardOneSpace() {
        let plan = SpaceSwitchPlan.plan(currentIndex: 0, spaceCount: 3, direction: .right, wrap: false)
        XCTAssertEqual(plan, SpaceSwitchPlan(fromIndex: 0, toIndex: 1))
        XCTAssertEqual(plan?.steps, 1)
        XCTAssertEqual(plan?.direction, .right)
    }

    func testStepsBackwardCrossesEverySpaceBetween() {
        // 2 → 4 is two rightward Dock swipes, not one.
        let plan = SpaceSwitchPlan.plan(currentIndex: 1, spaceCount: 5, direction: .right, wrap: false)
        XCTAssertEqual(plan?.toIndex, 2)
        XCTAssertEqual(plan?.steps, 1)
        let far = SpaceSwitchPlan(fromIndex: 1, toIndex: 4)
        XCTAssertEqual(far.steps, 3)
        XCTAssertEqual(far.direction, .right)
        XCTAssertEqual(SpaceSwitchPlan(fromIndex: 4, toIndex: 1).direction, .left)
    }

    func testEdgesRefuseWithoutWrapAndWrapAroundWith() {
        XCTAssertNil(SpaceSwitchPlan.plan(currentIndex: 2, spaceCount: 3, direction: .right, wrap: false))
        XCTAssertNil(SpaceSwitchPlan.plan(currentIndex: 0, spaceCount: 3, direction: .left, wrap: false))
        XCTAssertEqual(SpaceSwitchPlan.plan(currentIndex: 2, spaceCount: 3, direction: .right, wrap: true)?.toIndex, 0)
        XCTAssertEqual(SpaceSwitchPlan.plan(currentIndex: 0, spaceCount: 3, direction: .left, wrap: true)?.toIndex, 2)
    }

    func testNowhereToGo() {
        // One Space: wrapping to yourself is not a switch.
        XCTAssertNil(SpaceSwitchPlan.plan(currentIndex: 0, spaceCount: 1, direction: .right, wrap: true))
        // The current id is not a desktop (a fullscreen Space, or the layout moved under us).
        XCTAssertNil(SpaceSwitchPlan.plan(currentIndex: 3, spaceCount: 3, direction: .right, wrap: true))
        XCTAssertNil(SpaceSwitchPlan.plan(currentIndex: -1, spaceCount: 3, direction: .left, wrap: true))
    }

    // MARK: Settings

    func testSettingsDefaultsAndClamping() {
        let defaults = UserDefaults(suiteName: "SpaceSwitchPlanTests.\(UUID().uuidString)")!
        XCTAssertEqual(SpaceTransitionSettings.effect(from: defaults), .fade)
        XCTAssertEqual(SpaceTransitionSettings.duration(from: defaults), SpaceTransitionSettings.defaultDuration)

        defaults.set("instant", forKey: SpaceTransitionSettings.effectKey)
        defaults.set(5.0, forKey: SpaceTransitionSettings.durationKey)
        XCTAssertEqual(SpaceTransitionSettings.effect(from: defaults), .instant)
        XCTAssertEqual(SpaceTransitionSettings.duration(from: defaults), SpaceTransitionSettings.durationRange.upperBound)

        // A hand-edited key cannot leave the slider's range, and an unknown effect falls back to fade.
        defaults.set(0.0, forKey: SpaceTransitionSettings.durationKey)
        defaults.set("cube", forKey: SpaceTransitionSettings.effectKey)
        XCTAssertEqual(SpaceTransitionSettings.duration(from: defaults), SpaceTransitionSettings.durationRange.lowerBound)
        XCTAssertEqual(SpaceTransitionSettings.effect(from: defaults), .fade)
    }

    // MARK: Swipe events

    func testFixedPointNeverRoundsTheSignAway() {
        XCTAssertEqual(DockSwipeEventPoster.fixed1616(1), 65_536)
        XCTAssertEqual(DockSwipeEventPoster.fixed1616(0.5), 32_768)
        XCTAssertEqual(DockSwipeEventPoster.fixed1616(0), 0)
        // The near-zero travel is what makes the Dock commit instantly; subnormal-rounded-to-zero would
        // lose the direction, so the smallest non-zero values must survive as ±1.
        XCTAssertEqual(DockSwipeEventPoster.fixed1616(0.00001), 1)
        XCTAssertEqual(DockSwipeEventPoster.fixed1616(-0.00001), -1)
    }

    func testRightwardSwipeMovesForward() {
        XCTAssertTrue(DockSwipeEventPoster.isRightward(1e-4))
        XCTAssertFalse(DockSwipeEventPoster.isRightward(-1e-4))
        XCTAssertFalse(DockSwipeEventPoster.isRightward(0))
    }
}
