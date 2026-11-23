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
        XCTAssertEqual(run(&d, fingers: 4, spreads: [0.3, 0.3, 0.3, 0.3, 0.2, 0.19]), 1)
        XCTAssertEqual(run(&d, fingers: 4, spreads: [0.1, 0.09]), 0, "still the same gesture")
        _ = d.feed(fingers: 0, spread: 0)
        XCTAssertEqual(run(&d, fingers: 4, spreads: [0.3, 0.3, 0.3, 0.3, 0.2, 0.19]), 1)
    }

    func testFourFingerTapWithJitterAndStaggeredLiftoffNeverFires() {
        var d = PinchDetector()
        // 4 fingers settle around 0.25 spread, slight fingertip roll/compression, then staggered 4 -> 3 -> 0 liftoff.
        var fired = run(&d, fingers: 4, spreads: [0.25, 0.252, 0.249, 0.25, 0.242, 0.238])
        fired += run(&d, fingers: 3, spreads: [0.19, 0.14])
        fired += run(&d, fingers: 0, spreads: [0])
        XCTAssertEqual(fired, 0)
    }

    func testSingleFrameLiftoffSpikeNeverFires() {
        var d = PinchDetector()
        var fired = run(&d, fingers: 4, spreads: [0.3, 0.3, 0.3, 0.3, 0.15])
        fired += run(&d, fingers: 0, spreads: [0])
        XCTAssertEqual(fired, 0)
    }

    func testBunchedFourFingerTapBelowMinBaseSpreadNeverFires() {
        var d = PinchDetector()
        XCTAssertEqual(run(&d, fingers: 4, spreads: [0.05, 0.05, 0.05, 0.05, 0.03, 0.02]), 0)
    }

    func testMTTouchFrameParserReads96ByteStrideAndFiltersInactiveStates() {
        let count = 4
        var data = Data(count: count * MTTouchFrameParser.recordStride)
        let states: [Int32] = [3, 4, 5, 6]
        data.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            for i in 0..<count {
                let p = base.advanced(by: i * MTTouchFrameParser.recordStride)
                p.storeBytes(of: states[i], toByteOffset: MTTouchFrameParser.stateOffset, as: Int32.self)
                p.storeBytes(of: Int32(i + 1), toByteOffset: MTTouchFrameParser.fingerOffset, as: Int32.self)
                p.storeBytes(of: Float(0.2 + Double(i) * 0.2), toByteOffset: MTTouchFrameParser.xOffset, as: Float.self)
                p.storeBytes(of: Float(0.5), toByteOffset: MTTouchFrameParser.yOffset, as: Float.self)
                p.storeBytes(of: Float(0.1), toByteOffset: MTTouchFrameParser.vxOffset, as: Float.self)
                p.storeBytes(of: Float(-0.1), toByteOffset: MTTouchFrameParser.vyOffset, as: Float.self)
                // Put bogus high velocity noise in offsets 80..87 (previously misread as finger i+1 x/y under 48-byte stride).
                p.storeBytes(of: Float(420.0), toByteOffset: 80, as: Float.self)
                p.storeBytes(of: Float(-310.0), toByteOffset: 84, as: Float.self)
            }
        }
        let points = data.withUnsafeBytes { raw -> [MultitouchPoint] in
            guard let base = raw.baseAddress else { return [] }
            return MTTouchFrameParser.parse(raw: base, count: count)
        }
        XCTAssertEqual(points.count, 2, "only makeTouch (3) and touching (4) should be included")
        XCTAssertEqual(points[0].id, 1)
        XCTAssertEqual(points[0].x, 0.2, accuracy: 1e-5)
        XCTAssertEqual(points[1].id, 2)
        XCTAssertEqual(points[1].x, 0.4, accuracy: 1e-5)
    }

    func testSpreadOfPoints() {
        XCTAssertEqual(PinchDetector.spread(of: []), 0)
        XCTAssertEqual(PinchDetector.spread(of: [(0.5, 0.5)]), 0)
        XCTAssertEqual(PinchDetector.spread(of: [(0, 0), (1, 0)]), 0.5, accuracy: 1e-9)
    }
}
