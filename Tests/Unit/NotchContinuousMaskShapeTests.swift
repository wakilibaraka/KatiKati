import CoreGraphics
import SwiftUI
import XCTest
@testable import KatiKati

final class NotchContinuousMaskShapeTests: XCTestCase {
    func testHardwareNotchPathContainsInteriorPoints() {
        let shape = NotchContinuousMaskShape(topCornerRadius: 8, bottomCornerRadius: 14, flaringTopEars: true)
        let rect = CGRect(x: 100, y: 0, width: 200, height: 38)
        let path = shape.path(in: rect)

        XCTAssertFalse(path.isEmpty)

        // Center point of the notch should be inside
        XCTAssertTrue(path.contains(CGPoint(x: 200, y: 19)))

        // Point inside the notch body
        XCTAssertTrue(path.contains(CGPoint(x: 110, y: 10)))
        XCTAssertTrue(path.contains(CGPoint(x: 290, y: 10)))

        // Point near top bezel within the flaring ears (x in (105..295) at y=3)
        XCTAssertTrue(path.contains(CGPoint(x: 106, y: 3)))
        XCTAssertTrue(path.contains(CGPoint(x: 294, y: 3)))

        // Point outside the flaring ears at y=3
        XCTAssertFalse(path.contains(CGPoint(x: 102, y: 3)))
        XCTAssertFalse(path.contains(CGPoint(x: 298, y: 3)))

        // Point outside the bounding box must not be contained
        XCTAssertFalse(path.contains(CGPoint(x: 50, y: 19)))
        XCTAssertFalse(path.contains(CGPoint(x: 350, y: 19)))
        XCTAssertFalse(path.contains(CGPoint(x: 200, y: 50)))
    }

    func testFloatingIslandPathContainsInteriorPoints() {
        let shape = NotchContinuousMaskShape(topCornerRadius: 14, bottomCornerRadius: 14, flaringTopEars: false)
        let rect = CGRect(x: 100, y: 10, width: 200, height: 38)
        let path = shape.path(in: rect)

        XCTAssertFalse(path.isEmpty)

        // Center point of the island
        XCTAssertTrue(path.contains(CGPoint(x: 200, y: 29)))

        // Top-left extreme corner (x: 101, y: 11) is outside the convex squircle corner
        XCTAssertFalse(path.contains(CGPoint(x: 101, y: 11)))
    }

    func testAnimatableDataUpdatesRadii() {
        var shape = NotchContinuousMaskShape(topCornerRadius: 8, bottomCornerRadius: 14, flaringTopEars: true)
        XCTAssertEqual(shape.animatableData.first, 8)
        XCTAssertEqual(shape.animatableData.second, 14)

        shape.animatableData = AnimatablePair(22, 26)
        XCTAssertEqual(shape.topCornerRadius, 22)
        XCTAssertEqual(shape.bottomCornerRadius, 26)
    }

    func testDegenerateRectProducesEmptyPath() {
        let shape = NotchContinuousMaskShape()
        XCTAssertTrue(shape.path(in: .zero).isEmpty)
        XCTAssertTrue(shape.path(in: CGRect(x: 0, y: 0, width: -10, height: 30)).isEmpty)
    }
}
