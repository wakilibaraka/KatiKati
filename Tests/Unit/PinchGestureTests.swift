import XCTest
@testable import KatiKati

final class PinchGestureTests: XCTestCase {
    private func run(_ d: inout PinchDetector, fingers: Int, spreads: [Double]) -> Int {
        spreads.reduce(0) { $0 + (d.feed(fingers: fingers, spread: $1) ? 1 : 0) }
    }

    func testPinchInFiresOnceAfterSettling() {
        var d = PinchDetector()
        XCTAssertEqual(run(&d, fingers: 4, spreads: [0.3, 0.3, 0.3, 0.3, 0.3]), 0, "settling does not fire")
        XCTAssertEqual(run(&d, fingers: 4, spreads: [0.28, 0.25, 0.22, 0.2, 0.18]), 1, "fires once while closing")
    }

    func testSpreadOutAndThreeFingersNeverFire() {
        var d = PinchDetector()
        XCTAssertEqual(run(&d, fingers: 4, spreads: [0.3, 0.3, 0.3, 0.3, 0.4, 0.5]), 0)
        var e = PinchDetector()
        XCTAssertEqual(run(&e, fingers: 3, spreads: [0.3, 0.3, 0.3, 0.3, 0.1, 0.05]), 0)
    }

    func testFingerCountChangeResetsTheBaseline() {
        var d = PinchDetector()
        _ = run(&d, fingers: 4, spreads: [0.3, 0.3, 0.3, 0.3])
        // A fifth finger lands: the baseline is re-taken, so the jump in spread is not a pinch.
        XCTAssertEqual(run(&d, fingers: 5, spreads: [0.4, 0.4, 0.4, 0.4, 0.38]), 0)
    }

    func testLiftingRearms() {
        var d = PinchDetector()
        XCTAssertEqual(run(&d, fingers: 4, spreads: [0.3, 0.3, 0.3, 0.3, 0.2]), 1)
        XCTAssertEqual(run(&d, fingers: 4, spreads: [0.1]), 0, "still the same gesture")
        _ = d.feed(fingers: 0, spread: 0)
        XCTAssertEqual(run(&d, fingers: 4, spreads: [0.3, 0.3, 0.3, 0.3, 0.2]), 1)
    }

    func testSpreadOfPoints() {
        XCTAssertEqual(PinchDetector.spread(of: []), 0)
        XCTAssertEqual(PinchDetector.spread(of: [(0.5, 0.5)]), 0)
        XCTAssertEqual(PinchDetector.spread(of: [(0, 0), (1, 0)]), 0.5, accuracy: 1e-9)
    }
}
