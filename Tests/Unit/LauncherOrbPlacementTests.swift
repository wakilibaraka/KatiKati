import CoreGraphics
import XCTest
@testable import KatiKati

/// 57c: the floating orb's corner, its clamp against a stored position and the drag/click split.
final class LauncherOrbPlacementTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 70, width: 1710, height: 1017)

    func testFirstRunSitsInTheBottomRightCorner() {
        XCTAssertEqual(LauncherOrbPlacement.defaultOrigin(in: visible),
                       CGPoint(x: 1710 - 56 - 8, y: 70 + 8))
    }

    func testAStoredPositionFromAnotherDisplayIsPulledBackOnScreen() {
        let farRight = LauncherOrbPlacement.clamp(CGPoint(x: 3000, y: 5000), in: visible)
        XCTAssertEqual(farRight, CGPoint(x: 1710 - 56 - 8, y: 70 + 1017 - 56 - 8))
        let negative = LauncherOrbPlacement.clamp(CGPoint(x: -400, y: -400), in: visible)
        XCTAssertEqual(negative, CGPoint(x: 8, y: 78))
    }

    func testAnOnScreenPositionIsKeptExactly() {
        let origin = CGPoint(x: 700, y: 400)
        XCTAssertEqual(LauncherOrbPlacement.clamp(origin, in: visible), origin)
    }

    func testACrampedScreenStillGetsAPosition() {
        let cramped = CGRect(x: 0, y: 0, width: 40, height: 40)
        let origin = LauncherOrbPlacement.clamp(CGPoint(x: 900, y: 900), in: cramped)
        XCTAssertEqual(origin, CGPoint(x: 8, y: 8))
    }

    func testTinyTravelIsAClickAndARealMoveIsADrag() {
        XCTAssertTrue(LauncherOrbPlacement.isClick(travel: CGPoint(x: 3, y: 0)))
        XCTAssertTrue(LauncherOrbPlacement.isClick(travel: CGPoint(x: 2, y: 2)))
        XCTAssertFalse(LauncherOrbPlacement.isClick(travel: CGPoint(x: 5, y: 0)))
        XCTAssertFalse(LauncherOrbPlacement.isClick(travel: CGPoint(x: 40, y: 40)))
    }
}
