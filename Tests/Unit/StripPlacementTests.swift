import CoreGraphics
import XCTest
@testable import KatiKati

final class StripPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1710, height: 1112)

    func testBottomMappingIsTheIdentity() {
        let solved = CGRect(x: 12, y: 8, width: 243, height: 54)
        XCTAssertEqual(StripAxis.map(solved, placement: .bottom, screen: screen, topInset: 38), solved)
        XCTAssertEqual(StripAxis.mainLength(placement: .bottom, screen: screen, topInset: 38), 1710)
    }

    func testLeftRailRunsDownFromBelowTheMenuBar() {
        // Solver x = 12 from the rail's top end, 8 pt off the edge, 54 thick, 243 long.
        let solved = CGRect(x: 12, y: 8, width: 243, height: 54)
        let frame = StripAxis.map(solved, placement: .left, screen: screen, topInset: 38)
        XCTAssertEqual(frame, CGRect(x: 8, y: 1112 - 38 - 12 - 243, width: 54, height: 243))
        XCTAssertEqual(StripAxis.mainLength(placement: .left, screen: screen, topInset: 38), 1074)
    }

    func testRightRailMirrorsTheLeftOne() {
        let solved = CGRect(x: 12, y: 8, width: 243, height: 54)
        let left = StripAxis.map(solved, placement: .left, screen: screen, topInset: 38)
        let right = StripAxis.map(solved, placement: .right, screen: screen, topInset: 38)
        XCTAssertEqual(right.minY, left.minY)
        XCTAssertEqual(right.maxX, screen.maxX - 8)
        XCTAssertEqual(right.width, left.width)
    }

    func testMappedRailsStayOnAnOffsetScreen() {
        let second = CGRect(x: 1710, y: -200, width: 1440, height: 900)
        let solved = CGRect(x: 0, y: 0, width: 900 - 25, height: 46)
        for placement in [StripPlacement.left, .right] {
            let frame = StripAxis.map(solved, placement: placement, screen: second, topInset: 25)
            XCTAssertTrue(second.contains(frame), "\(placement) \(frame)")
        }
    }

    func testReservedInsetPerEdge() {
        XCTAssertEqual(StripAxis.reservedInset(frame: CGRect(x: 100, y: 8, width: 500, height: 54),
                                               placement: .bottom, screen: screen), 62)
        XCTAssertEqual(StripAxis.reservedInset(frame: CGRect(x: 8, y: 100, width: 54, height: 500),
                                               placement: .left, screen: screen), 62)
        XCTAssertEqual(StripAxis.reservedInset(frame: CGRect(x: 1648, y: 100, width: 54, height: 500),
                                               placement: .right, screen: screen), 62)
    }

    func testSideRailsFoldTheWideSplitsIntoThree() {
        XCTAssertEqual(StripPlacement.bottom.effectiveMode(.split5), .split5)
        XCTAssertEqual(StripPlacement.left.effectiveMode(.split5), .split3)
        XCTAssertEqual(StripPlacement.right.effectiveMode(.split4), .split3)
        XCTAssertEqual(StripPlacement.left.effectiveMode(.centered), .centered)
        XCTAssertEqual(StripPlacement.left.effectiveMode(.windows), .windows)
    }

    func testPerDisplayOverridesFallBackToGlobal() {
        var map = StripPlacementMap()
        XCTAssertEqual(map.placement(forDisplay: "A"), .bottom)
        map = map.setting(.left, forDisplay: "A")
        XCTAssertEqual(map.placement(forDisplay: "A"), .left)
        XCTAssertEqual(map.placement(forDisplay: "B"), .bottom)
        XCTAssertEqual(map.placement(forDisplay: nil), .bottom)
        map = map.setting(.bottom, forDisplay: "A")
        XCTAssertTrue(map.perDisplay.isEmpty, "setting the global value clears the override")
        let round = StripPlacementMap.decode(map.setting(.right, forDisplay: "C").encoded())
        XCTAssertEqual(round?.placement(forDisplay: "C"), .right)
    }

    func testRailTilesAreCompact() {
        for section in BarSection.allCases where section != .apps {
            let tile = section.railTileLength(barHeight: 54)
            XCTAssertGreaterThan(tile, 0)
            XCTAssertLessThanOrEqual(tile, 54 * 1.2, "\(section) stays a compact tile on a rail")
        }
    }

    func testUnmapInvertsMapForPointsOnARail() {
        let solved = CGRect(x: 40, y: 8, width: 300, height: 54)
        for placement in [StripPlacement.left, .right] {
            let mapped = StripAxis.map(solved, placement: placement, screen: screen, topInset: 0)
            XCTAssertEqual(StripAxis.unmap(mapped, placement: placement, screen: screen), solved, "\(placement)")
        }
        XCTAssertEqual(StripAxis.unmap(CGPoint(x: 5, y: 7), placement: .bottom, screen: screen), CGPoint(x: 5, y: 7))
    }

    func testDistanceFromStripEdgeFollowsThePlacement() {
        let p = CGPoint(x: 3, y: 500)
        XCTAssertEqual(StripAxis.distanceFromStripEdge(p, placement: .left, screen: screen), 3)
        XCTAssertEqual(StripAxis.distanceFromStripEdge(p, placement: .bottom, screen: screen), 500)
        XCTAssertEqual(StripAxis.distanceFromStripEdge(CGPoint(x: 1707, y: 500), placement: .right, screen: screen), 3)
    }

    // MARK: 18g edge-bar occupancy

    func testBottomDockLeavesEdgeBarsAlone() {
        let content: [EdgeSide: [String]] = [.left: ["widgets"], .right: ["notes"]]
        XCTAssertEqual(EdgeOccupancy.resolve(content, dock: .bottom, policy: .moveAcross), content)
    }

    func testMoveAcrossToAFreeEdge() {
        let content: [EdgeSide: [String]] = [.right: ["notes", "status"]]
        let resolved = EdgeOccupancy.resolve(content, dock: .right, policy: .moveAcross)
        XCTAssertEqual(resolved, [.left: ["notes", "status"]])
    }

    func testBothEdgesTakenMergeIntoOneBarOnTheFreeEdge() {
        let content: [EdgeSide: [String]] = [.left: ["widgets", "notes"], .right: ["notes", "status"]]
        let resolved = EdgeOccupancy.resolve(content, dock: .left, policy: .moveAcross)
        XCTAssertEqual(resolved, [.right: ["notes", "status", "widgets"]], "free side first, duplicates dropped")
    }

    func testHidePolicyDropsTheDisplacedBar() {
        let content: [EdgeSide: [String]] = [.left: ["widgets"], .right: ["notes"]]
        XCTAssertEqual(EdgeOccupancy.resolve(content, dock: .left, policy: .hide), [.right: ["notes"]])
    }
}

