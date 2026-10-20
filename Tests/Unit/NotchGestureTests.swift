import Foundation
import XCTest
@testable import KatiKati

final class NotchGestureTests: XCTestCase {

    // MARK: - NotchGestureSupport Tests

    func testScrollDownWhenClosedTriggersOpen() {
        var gesture = NotchGestureSupport()
        // Precise scrolling down: begins, dy = 18 pt (exceeds 16 pt threshold)
        let action = gesture.handle(
            x: 0,
            y: 18,
            timestamp: 1.0,
            began: true,
            ended: false,
            momentum: false,
            precise: true,
            hasPhase: true,
            allowVertical: true,
            allowHorizontal: false,
            expanded: false
        )
        XCTAssertEqual(action, .open)
    }

    func testScrollUpWhenOpenTriggersClose() {
        var gesture = NotchGestureSupport()
        // Precise scrolling up: begins, dy = -20 pt (exceeds -16 pt threshold)
        let action = gesture.handle(
            x: 0,
            y: -20,
            timestamp: 1.0,
            began: true,
            ended: false,
            momentum: false,
            precise: true,
            hasPhase: true,
            allowVertical: true,
            allowHorizontal: false,
            expanded: true
        )
        XCTAssertEqual(action, .close)
    }

    func testScrollBelowThresholdDoesNotTriggerAction() {
        var gesture = NotchGestureSupport()
        let action = gesture.handle(
            x: 0,
            y: 8,
            timestamp: 1.0,
            began: true,
            ended: false,
            momentum: false,
            precise: true,
            hasPhase: true,
            allowVertical: true,
            allowHorizontal: false,
            expanded: false
        )
        XCTAssertNil(action)
    }

    func testFlickMomentumCompletesOpening() {
        var gesture = NotchGestureSupport()
        // 1. Initial short drag (below threshold)
        _ = gesture.handle(
            x: 0,
            y: 10,
            timestamp: 1.0,
            began: true,
            ended: false,
            momentum: false,
            precise: true,
            hasPhase: true,
            allowVertical: true,
            allowHorizontal: false,
            expanded: false
        )

        // 2. User lifts fingers (ended -> enters coasting)
        let endedAction = gesture.handle(
            x: 0,
            y: 0,
            timestamp: 1.05,
            began: false,
            ended: true,
            momentum: false,
            precise: true,
            hasPhase: true,
            allowVertical: true,
            allowHorizontal: false,
            expanded: false
        )
        XCTAssertNil(endedAction)

        // 3. Momentum arrives within 0.35s and adds enough travel to exceed 16pt
        let momentumAction = gesture.handle(
            x: 0,
            y: 8,
            timestamp: 1.10,
            began: false,
            ended: false,
            momentum: true,
            precise: true,
            hasPhase: false,
            allowVertical: true,
            allowHorizontal: false,
            expanded: false
        )
        XCTAssertEqual(momentumAction, .open)
    }

    func testHorizontalSwipeSwitchesPages() {
        var gesture = NotchGestureSupport()
        // Swipe left (negative x travel) in pageNavigation mode
        let action = gesture.handle(
            x: -45,
            y: 0,
            timestamp: 1.0,
            began: true,
            ended: false,
            momentum: false,
            precise: true,
            hasPhase: true,
            allowVertical: false,
            allowHorizontal: true,
            expanded: true,
            horizontalMode: .pageNavigation
        )
        XCTAssertEqual(action, .nextPage)

        // Swipe right (positive x travel) in pageNavigation mode
        var gestureRight = NotchGestureSupport()
        let actionRight = gestureRight.handle(
            x: 45,
            y: 0,
            timestamp: 1.0,
            began: true,
            ended: false,
            momentum: false,
            precise: true,
            hasPhase: true,
            allowVertical: false,
            allowHorizontal: true,
            expanded: true,
            horizontalMode: .pageNavigation
        )
        XCTAssertEqual(actionRight, .previousPage)
    }

    func testHorizontalSwipeSkipsTracksInTrackMode() {
        var gesture = NotchGestureSupport()
        let action = gesture.handle(
            x: -45,
            y: 0,
            timestamp: 1.0,
            began: true,
            ended: false,
            momentum: false,
            precise: true,
            hasPhase: true,
            allowVertical: false,
            allowHorizontal: true,
            expanded: true,
            horizontalMode: .trackSkip
        )
        XCTAssertEqual(action, .nextTrack)
    }

    func testMovementScaling() {
        // Precise trackpad delta
        let precise = NotchGestureSupport.movement(10.0, precise: true, inverted: false)
        XCTAssertEqual(precise, -10.0)

        // Non-precise mouse wheel notch
        let wheel = NotchGestureSupport.movement(1.0, precise: false, inverted: false)
        XCTAssertEqual(wheel, -24.0)

        // Inverted scrolling
        let inverted = NotchGestureSupport.movement(10.0, precise: true, inverted: true)
        XCTAssertEqual(inverted, 10.0)
    }

    // MARK: - NotchSectionPaging Tests

    func testPageNextPreviousNavigation() {
        let p0 = NotchPage.downloadDeck
        let p1 = p0.next()
        XCTAssertEqual(p1, .storage)
        let p2 = p1.next()
        XCTAssertEqual(p2, .aiTracker)
        let p3 = p2.next()
        XCTAssertEqual(p3, .audioDeck)

        // Wrapping forward
        XCTAssertEqual(p3.next(wrap: true), .downloadDeck)
        // Clamping forward without wrap
        XCTAssertEqual(p3.next(wrap: false), .audioDeck)

        // Wrapping backward
        XCTAssertEqual(p0.previous(wrap: true), .audioDeck)
        // Clamping backward without wrap
        XCTAssertEqual(p0.previous(wrap: false), .downloadDeck)
    }

    func testPagingPolicyContextAwareSelection() {
        // User pinned page takes highest priority
        let pinned = NotchPagingPolicy.defaultPage(nowPlayingActive: true, aiTurnActive: true, userPinnedPage: .storage)
        XCTAssertEqual(pinned, .storage)

        // AI turn active -> AI Mission Control
        XCTAssertEqual(NotchPagingPolicy.defaultPage(nowPlayingActive: true, aiTurnActive: true), .aiTracker)

        // Music playing -> Music & Calendar
        XCTAssertEqual(NotchPagingPolicy.defaultPage(nowPlayingActive: true, aiTurnActive: false), .audioDeck)

        // Default idle fallback is the first page
        XCTAssertEqual(NotchPagingPolicy.defaultPage(nowPlayingActive: false, aiTurnActive: false), .downloadDeck)
    }

    func testDockCompanionPolicy() {
        XCTAssertTrue(NotchDockCompanionPolicy.shouldHideDockCapsule(notchExpanded: true, dockCompanionAutoHide: true))
        XCTAssertFalse(NotchDockCompanionPolicy.shouldHideDockCapsule(notchExpanded: false, dockCompanionAutoHide: true))
        XCTAssertFalse(NotchDockCompanionPolicy.shouldHideDockCapsule(notchExpanded: true, dockCompanionAutoHide: false))
    }

    func testSectionScrollAccumulator() {
        var scroll = NotchSectionScroll()
        // Precise scroll delta below firstStep (24pt)
        let s0 = scroll.steps(deltaX: 10, timestamp: 1.0, precise: true, hasPhase: true, began: true, ended: false, momentum: false)
        XCTAssertEqual(s0, 0)

        // Accumulates to exceed firstStep (10 + 15 = 25pt)
        let s1 = scroll.steps(deltaX: 15, timestamp: 1.05, precise: true, hasPhase: true, began: false, ended: false, momentum: false)
        XCTAssertEqual(s1, -1) // negative delta moves forward, positive moves backward
    }

    func testPageDirectionFollowsTarget() {
        let visible = NotchPage.visible(teleprompter: false)
        XCTAssertEqual(NotchPageDirection.between(from: .downloadDeck, to: .storage, visible: visible), 1)
        XCTAssertEqual(NotchPageDirection.between(from: .storage, to: .downloadDeck, visible: visible), -1)
        XCTAssertEqual(NotchPageDirection.between(from: .audioDeck, to: .downloadDeck, visible: visible), 1, "wrap keeps swipe direction")
        XCTAssertEqual(NotchPageDirection.between(from: .downloadDeck, to: .audioDeck, visible: visible), -1, "wrap keeps swipe direction")
    }

    // Phase 37c: the teleprompter page is the 5th page only while switched on; off, paging is the original four.
    func testTeleprompterPageIsOptional() {
        XCTAssertEqual(NotchPage.visible(teleprompter: false).count, 4)
        XCTAssertEqual(NotchPage.visible(teleprompter: true).last, .teleprompter)
        XCTAssertEqual(NotchPage.audioDeck.next(wrap: true), .downloadDeck)
        XCTAssertEqual(NotchPage.audioDeck.next(wrap: true, teleprompter: true), .teleprompter)
        XCTAssertEqual(NotchPage.teleprompter.next(wrap: true, teleprompter: true), .downloadDeck)
        XCTAssertEqual(NotchPage.downloadDeck.previous(wrap: true, teleprompter: true), .teleprompter)
        XCTAssertEqual(NotchPage.teleprompter.next(wrap: true, teleprompter: false), .downloadDeck)   // switched off while on it
    }
}
