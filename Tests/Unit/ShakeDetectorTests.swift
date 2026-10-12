import XCTest
@testable import KatiKati

final class ShakeDetectorTests: XCTestCase {
    private func feed(_ d: inout ShakeDetector, _ xs: [Double], start: TimeInterval = 0, step: TimeInterval = 0.05) -> Bool {
        var fired = false
        for (i, x) in xs.enumerated() { if d.add(x: x, at: start + Double(i) * step) { fired = true } }
        return fired
    }

    func testQuickShakeFires() {
        var d = ShakeDetector()
        XCTAssertTrue(feed(&d, [0, 50, 0, 50, 0, 50, 0]))
    }

    func testStraightDragDoesNotFire() {
        var d = ShakeDetector()
        XCTAssertFalse(feed(&d, Array(stride(from: 0.0, to: 600, by: 20))))
    }

    func testSmallJitterDoesNotFire() {
        var d = ShakeDetector()
        XCTAssertFalse(feed(&d, [0, 8, 0, 8, 0, 8, 0, 8, 0, 8]))
    }

    func testSlowWobbleOutsideWindowDoesNotFire() {
        var d = ShakeDetector()
        XCTAssertFalse(feed(&d, [0, 60, 0, 60, 0, 60, 0], step: 0.5))
    }

    func testTwoStrokesAreNotEnough() {
        var d = ShakeDetector()
        XCTAssertFalse(feed(&d, [0, 60, 0]))
    }

    func testCooldownSuppressesImmediateRepeat() {
        var d = ShakeDetector()
        XCTAssertTrue(feed(&d, [0, 50, 0, 50, 0, 50, 0]))
        XCTAssertFalse(feed(&d, [0, 50, 0, 50, 0, 50, 0], start: 0.4), "inside the cooldown")
        XCTAssertTrue(feed(&d, [0, 50, 0, 50, 0, 50, 0], start: 3), "after the cooldown")
    }
}
