import XCTest
@testable import KatiKati

/// The numbers behind the fluid rail: waist, swell crest and its falloff. The drawing half is
/// checked live; these are the parts that must never quietly drift.
final class FluidRailGeometryTests: XCTestCase {
    private let radius: CGFloat = 27

    func testWaistIsNarrowerThanTheLobes() {
        XCTAssertLessThan(FluidRailGeometry.neckRatio, 1)
        XCTAssertEqual(FluidRailGeometry.coreThickness(plate: 54), 54 * FluidRailGeometry.neckRatio, accuracy: 1e-9)
    }

    func testTheBodyNeverSwellingPastThePanelsTransparentRoom() {
        // Every floating panel keeps 20 pt (`PanelCoordinator.shadowPadding`) around its plate;
        // a bulge that fits inside it cannot grow a window.
        XCTAssertLessThanOrEqual(FluidRailGeometry.maxSwell, 20)
        let peak = FluidRailGeometry.swells(centers: [100], pointer: 100, radius: radius).first
        XCTAssertEqual(peak, FluidRailGeometry.maxSwell)
    }

    func testPointerAtAnItemGivesItTheFullSwellAndLeavesDistantItemsAlone() {
        let swells = FluidRailGeometry.swells(centers: [0, 100, 400], pointer: 100, radius: radius)
        XCTAssertEqual(swells[1], FluidRailGeometry.maxSwell, accuracy: 1e-9)
        XCTAssertEqual(swells[0], 0, accuracy: 1e-9, "far above the reach")
        XCTAssertEqual(swells[2], 0, accuracy: 1e-9, "far below the reach")
    }

    func testNeighboursSoftenInsteadOfStepping() {
        // One pitch apart: inside the reach, so the neighbour bulges a little rather than not at all.
        let pitch = radius * 1.1
        let swells = FluidRailGeometry.swells(centers: [0, pitch], pointer: 0, radius: radius)
        XCTAssertEqual(swells[0], FluidRailGeometry.maxSwell, accuracy: 1e-9)
        XCTAssertGreaterThan(swells[1], 0)
        XCTAssertLessThan(swells[1], swells[0])
    }

    func testSwellFallsOffMonotonicallyThenStops() {
        let reach = radius * FluidRailGeometry.swellReach
        var previous = FluidRailGeometry.maxSwell
        for step in 1...8 {
            let distance = reach * CGFloat(step) / 8
            let swell = FluidRailGeometry.swells(centers: [0], pointer: distance, radius: radius)[0]
            XCTAssertLessThanOrEqual(swell, previous + 1e-9, "distance \(distance)")
            previous = swell
        }
        XCTAssertEqual(previous, 0, accuracy: 1e-9)
    }

    func testNoPointerMeansNoSwell() {
        XCTAssertEqual(FluidRailGeometry.swells(centers: [0, 40], pointer: nil, radius: radius), [0, 0])
        XCTAssertEqual(FluidRailGeometry.swells(centers: [], pointer: 10, radius: radius), [])
        XCTAssertEqual(FluidRailGeometry.swells(centers: [10], pointer: 10, radius: 0), [0],
                       "a zero radius has no reach to speak of")
    }

    func testSwellIsSymmetricAroundThePointer() {
        let above = FluidRailGeometry.swells(centers: [-30], pointer: 0, radius: radius)
        let below = FluidRailGeometry.swells(centers: [30], pointer: 0, radius: radius)
        XCTAssertEqual(above, below)
    }
}
