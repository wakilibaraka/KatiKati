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
        let home = NotchPage.home
        let shelf = home.next()
        XCTAssertEqual(shelf, .shelf)
        XCTAssertEqual(shelf.next(), .aiTracker)

        let last = NotchPage.keepAwake
        XCTAssertEqual(last.next(wrap: true), .home)
        XCTAssertEqual(last.next(wrap: false), last)
        XCTAssertEqual(home.previous(wrap: true), last)
        XCTAssertEqual(home.previous(wrap: false), home)
    }

    func testPagingPolicyContextAwareSelection() {
        // User pinned page takes highest priority
        let pinned = NotchPagingPolicy.defaultPage(aiTurnActive: true, userPinnedPage: .studioHub)
        XCTAssertEqual(pinned, .studioHub)

        // AI turn active -> AI Mission Control
        XCTAssertEqual(NotchPagingPolicy.defaultPage(aiTurnActive: true), .aiTracker)

        XCTAssertEqual(NotchPagingPolicy.defaultPage(aiTurnActive: false), .home)
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

    func testBoringHomeHonorsPinnedPage() {
        XCTAssertEqual(NotchPagingPolicy.defaultPage(aiTurnActive: true, usesBoringHome: true), .home)
        XCTAssertEqual(NotchPagingPolicy.defaultPage(aiTurnActive: true, userPinnedPage: .calendar, usesBoringHome: true), .home)
    }

    func testNotchTransportPreservesOrderAndFiltersInvalidControls() {
        let controls: [NotchTransportControl] = [.next, .backward, .playPause]
        XCTAssertEqual(NotchTransportControl.decode(NotchTransportControl.encode(controls) + ",bogus,next"), controls)
        XCTAssertEqual(NotchTransportControl.decode("bogus"), [.previous, .playPause, .next])
    }

    func testPageDirectionFollowsTarget() {
        let visible = NotchPage.visible(teleprompter: false, mirror: false, layout: NotchPageLayout())
        XCTAssertEqual(NotchPageDirection.between(from: .home, to: .shelf, visible: visible), 1)
        XCTAssertEqual(NotchPageDirection.between(from: .shelf, to: .home, visible: visible), -1)
        XCTAssertEqual(NotchPageDirection.between(from: .keepAwake, to: .home, visible: visible), 1)
        XCTAssertEqual(NotchPageDirection.between(from: .home, to: .keepAwake, visible: visible), -1)
    }

    func testTeleprompterPageIsOptional() {
        XCTAssertEqual(NotchPage.visible(teleprompter: false, mirror: true).count, 7)
        XCTAssertEqual(NotchPage.visible(teleprompter: false, mirror: false).count, 6)
        XCTAssertEqual(NotchPage.visible(teleprompter: true, mirror: false).dropLast().last, .teleprompter)
        XCTAssertEqual(NotchPage.studioHub.next(teleprompter: true, mirror: false), .teleprompter)
        XCTAssertEqual(NotchPage.teleprompter.next(teleprompter: false, mirror: false), .home)
    }

    func testNotchPageLayoutReordersAndHidesPages() {
        let all = NotchPage.visible(teleprompter: false, mirror: false, layout: NotchPageLayout())
        XCTAssertEqual(all, [.home, .shelf, .aiTracker, .peripherals, .studioHub, .keepAwake])
        XCTAssertEqual(NotchPage.audioDeck.navigationPage, .home)
        XCTAssertEqual(NotchPage.calendar.navigationPage, .home)
        let saved = NotchPageLayout(raw: "9,3,8|2")
        XCTAssertEqual(NotchPage.visible(teleprompter: false, mirror: false, layout: saved),
                       [.studioHub, .home, .shelf, .peripherals, .keepAwake])
        XCTAssertEqual(NotchPageLayout(raw: saved.raw), saved)
        XCTAssertEqual(NotchPageLayout(raw: "junk|99,x"), NotchPageLayout())
        let hidden = NotchPageLayout(hidden: Set(NotchPage.allCases))
        XCTAssertEqual(NotchPage.visible(teleprompter: false, mirror: false, layout: hidden), all)
    }

    func testDisplayDesignDefaultsAndOverrides() {
        XCTAssertEqual(NotchDesign.resolve(display: "1", hasHardwareNotch: true, stored: [:]), .notch)
        XCTAssertEqual(NotchDesign.resolve(display: "2", hasHardwareNotch: false, stored: [:]), .wideBar)
        XCTAssertEqual(NotchDesign.resolve(display: "2", hasHardwareNotch: false, stored: ["2": .off]), .off)
        let d = UserDefaults(suiteName: "NotchDesignTests")!
        d.removePersistentDomain(forName: "NotchDesignTests")
        NotchDesign.set(.notch, for: "2", d)
        XCTAssertEqual(NotchDesign.stored(d), ["2": .notch])
    }

    func testWideBarSpec() {
        XCTAssertEqual(NotchWideBarSpec.items(width: 300), [.time])
        XCTAssertEqual(NotchWideBarSpec.items(width: 768).count, 7, "storage left the wide bar (SD-3b)")
        XCTAssertEqual(NotchWideBarSpec.items(width: 450), [.time, .battery, .status, .nowPlaying])
    }
}
