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
        let p0 = NotchPage.audioDeck
        let p1 = p0.next()
        XCTAssertEqual(p1, .calendar)
        let p2 = p1.next()
        XCTAssertEqual(p2, .aiTracker)
        let p3 = p2.next()
        XCTAssertEqual(p3, .peripherals)
        let p4 = p3.next()
        XCTAssertEqual(p4, .studioHub)
        let p5 = p4.next()
        XCTAssertEqual(p5, .cameraMirror)
        let p6 = p5.next()
        XCTAssertEqual(p6, .keepAwake)

        // Wrapping forward
        XCTAssertEqual(p6.next(wrap: true), .audioDeck)
        // Clamping forward without wrap
        XCTAssertEqual(p6.next(wrap: false), .keepAwake)

        // Wrapping backward
        XCTAssertEqual(p0.previous(wrap: true), .keepAwake)
        // Clamping backward without wrap
        XCTAssertEqual(p0.previous(wrap: false), .audioDeck)
    }

    func testPagingPolicyContextAwareSelection() {
        // User pinned page takes highest priority
        let pinned = NotchPagingPolicy.defaultPage(nowPlayingActive: true, aiTurnActive: true, userPinnedPage: .calendar)
        XCTAssertEqual(pinned, .calendar)

        // AI turn active -> AI Mission Control
        XCTAssertEqual(NotchPagingPolicy.defaultPage(nowPlayingActive: true, aiTurnActive: true), .aiTracker)

        // Music playing -> Music & Calendar
        XCTAssertEqual(NotchPagingPolicy.defaultPage(nowPlayingActive: true, aiTurnActive: false), .audioDeck)

        // Default idle fallback is the first page
        XCTAssertEqual(NotchPagingPolicy.defaultPage(nowPlayingActive: false, aiTurnActive: false), .audioDeck)
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
        let visible = NotchPage.visible(teleprompter: false, mirror: false)
        XCTAssertEqual(NotchPageDirection.between(from: .audioDeck, to: .calendar, visible: visible), 1)
        XCTAssertEqual(NotchPageDirection.between(from: .calendar, to: .audioDeck, visible: visible), -1)
        XCTAssertEqual(NotchPageDirection.between(from: .keepAwake, to: .audioDeck, visible: visible), 1, "wrap keeps swipe direction")
        XCTAssertEqual(NotchPageDirection.between(from: .audioDeck, to: .keepAwake, visible: visible), -1, "wrap keeps swipe direction")
    }

    func testTeleprompterPageIsOptional() {
        XCTAssertEqual(NotchPage.visible(teleprompter: false, mirror: true).count, 7)
        XCTAssertEqual(NotchPage.visible(teleprompter: false, mirror: false).count, 6)
        XCTAssertEqual(NotchPage.visible().count, 7)
        XCTAssertEqual(NotchPage.visible(teleprompter: true, mirror: false).count, 7)
        XCTAssertEqual(NotchPage.visible(teleprompter: true, mirror: false).last, .keepAwake)
        XCTAssertEqual(NotchPage.visible(teleprompter: true, mirror: false).dropLast().last, .teleprompter)
        XCTAssertEqual(NotchPage.keepAwake.next(wrap: true, teleprompter: false, mirror: false), .audioDeck)
        XCTAssertEqual(NotchPage.studioHub.next(wrap: true, teleprompter: true, mirror: false), .teleprompter)
        XCTAssertEqual(NotchPage.teleprompter.next(wrap: true, teleprompter: true, mirror: false), .keepAwake)
        XCTAssertEqual(NotchPage.audioDeck.previous(wrap: true, teleprompter: true, mirror: false), .keepAwake)
        XCTAssertEqual(NotchPage.teleprompter.next(wrap: true, teleprompter: false, mirror: false), .audioDeck)
    }

    func testPageLayoutOrdersHidesAndRoundTrips() {
        let all = NotchPage.visible(teleprompter: false, mirror: false, layout: NotchPageLayout())
        XCTAssertEqual(all, [.audioDeck, .calendar, .aiTracker, .peripherals, .studioHub, .keepAwake])
        var layout = NotchPageLayout(order: [.audioDeck, .calendar, .studioHub, .aiTracker])
        layout.hidden = [.aiTracker]
        XCTAssertEqual(NotchPage.visible(teleprompter: false, mirror: false, layout: layout), [.audioDeck, .calendar, .studioHub, .peripherals, .keepAwake])
        XCTAssertEqual(NotchPageLayout(raw: layout.raw), layout)
        XCTAssertEqual(NotchPageLayout(raw: "junk|99,x"), NotchPageLayout())
        layout.hidden = Set(NotchPage.allCases)
        XCTAssertEqual(NotchPage.visible(teleprompter: false, mirror: false, layout: layout).count, 6)
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
