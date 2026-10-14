import CoreGraphics
import XCTest
@testable import KatiKati

final class NotificationPlacementTests: XCTestCase {
    private let workArea = CGRect(x: 0, y: 25, width: 1440, height: 835)
    private let banner = CGRect(x: 1200, y: 0, width: 360, height: 100)

    func testEverySlotLandsInsideTheWorkArea() {
        for slot in NotificationSlot.allCases {
            let frame = NotificationPlacement.frame(slot: slot, workArea: workArea, banner: banner)
            XCTAssertTrue(workArea.contains(frame), "\(slot) frame \(frame) escaped the work area")
        }
    }

    func testSlotAnchors() {
        let topLeft = NotificationPlacement.frame(slot: .topLeft, workArea: workArea, banner: banner)
        XCTAssertEqual(topLeft.origin, CGPoint(x: 12, y: 37))

        let topCenter = NotificationPlacement.frame(slot: .topCenter, workArea: workArea, banner: banner)
        XCTAssertEqual(topCenter.origin, CGPoint(x: (1440 - 360) / 2, y: 37))

        let bottomRight = NotificationPlacement.frame(slot: .bottomRight, workArea: workArea, banner: banner)
        XCTAssertEqual(bottomRight.origin, CGPoint(x: 1440 - 12 - 360, y: 25 + 835 - 12 - 100))

        let middleLeft = NotificationPlacement.frame(slot: .middleLeft, workArea: workArea, banner: banner)
        XCTAssertEqual(middleLeft.origin.y, 25 + (835 - 100) / 2)
    }

    func testBannerBiggerThanTheWorkAreaIsClampedNotFlung() {
        let huge = CGRect(x: 0, y: 0, width: 2000, height: 2000)
        for slot in NotificationSlot.allCases {
            let frame = NotificationPlacement.frame(slot: slot, workArea: workArea, banner: huge)
            XCTAssertEqual(frame.size, workArea.size)
            XCTAssertEqual(frame.origin, workArea.origin)
        }
    }

    func testSlotGridHasEightCellsAndNoDeadCentre() {
        XCTAssertEqual(NotificationSlot.allCases.count, 8)
        XCTAssertEqual(Set(NotificationSlot.allCases.map(\.rawValue)).count, 8)
        XCTAssertFalse(NotificationSlot.allCases.contains { $0.column == .center && $0.row == .middle })
    }
}

final class NotificationUICapabilityTests: XCTestCase {
    private func observation(_ mutate: (inout NotificationUIObservation) -> Void) -> NotificationUIObservation {
        var observed = NotificationUIObservation(
            bannerSubrole: "AXNotificationCenterBanner",
            bannerFrameReadable: true,
            windowFrameReadable: true,
            positionSettable: true,
            visitedNodes: 40
        )
        mutate(&observed)
        return observed
    }

    func testRecognisedBannerWithAReadableSettableWindowIsSafeToMove() {
        XCTAssertTrue(NotificationUICapability.evaluate(observation { _ in }))
        XCTAssertTrue(NotificationUICapability.evaluate(observation { $0.bannerSubrole = "AXNotificationCenterBannerWindow" }))
    }

    func testUnknownOrMissingSubroleFailsClosed() {
        XCTAssertFalse(NotificationUICapability.evaluate(observation { $0.bannerSubrole = nil }))
        XCTAssertFalse(NotificationUICapability.evaluate(observation { $0.bannerSubrole = "AXSnazzyNewBanner" }))
    }

    func testUnreadableFramesOrUnsettablePositionFailClosed() {
        XCTAssertFalse(NotificationUICapability.evaluate(observation { $0.bannerFrameReadable = false }))
        XCTAssertFalse(NotificationUICapability.evaluate(observation { $0.windowFrameReadable = false }))
        XCTAssertFalse(NotificationUICapability.evaluate(observation { $0.positionSettable = false }))
    }

    func testRunawayAXTreeFailsClosed() {
        XCTAssertFalse(NotificationUICapability.evaluate(observation { $0.visitedNodes = NotificationUICapability.maxNodes + 1 }))
    }
}

final class NotificationMoveGuardTests: XCTestCase {
    func testCooldownDebouncesBackToBackMoves() {
        var guard_ = NotificationMoveGuard(cooldown: 0.35)
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        XCTAssertTrue(guard_.shouldMove(now: t0))
        guard_.noteMove(at: t0)
        XCTAssertFalse(guard_.shouldMove(now: t0.addingTimeInterval(0.1)))
        XCTAssertTrue(guard_.shouldMove(now: t0.addingTimeInterval(0.35)))
    }
}
