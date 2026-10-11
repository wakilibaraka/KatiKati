import XCTest
@testable import KatiKati

final class EdgeBarSlotTests: XCTestCase {
    private let metrics = PanelLayoutMetrics.tungstenEdge

    private func screen(origin: CGPoint = .zero, size: CGSize = CGSize(width: 1728, height: 1117), menuBar: CGFloat = 25) -> PanelScreenGeometry {
        let frame = CGRect(origin: origin, size: size)
        return PanelScreenGeometry(
            frame: frame,
            visibleFrame: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - menuBar),
            safeAreaTop: 0
        )
    }

    // MARK: Slot keys

    func testSlotKeyDescription() {
        XCTAssertEqual(EdgeSlotSet.SlotKey(display: nil, side: .right).description, "follow#edge-right")
        XCTAssertEqual(EdgeSlotSet.SlotKey(display: "D1", side: .left).description, "D1#edge-left")
    }

    func testNoSidesMeansNoSlots() {
        XCTAssertTrue(EdgeSlotSet.desiredSlots(placement: .followMouse, connectedKeys: ["A"], sides: []).isEmpty)
    }

    func testFollowPlacementYieldsOneKeyPerSide() {
        let slots = EdgeSlotSet.desiredSlots(placement: .followMouse, connectedKeys: ["A", "B"], sides: [.right, .left])
        XCTAssertEqual(slots, [
            EdgeSlotSet.SlotKey(display: nil, side: .left),
            EdgeSlotSet.SlotKey(display: nil, side: .right),
        ])
    }

    func testEveryDisplayPlacementCrossesDisplaysWithSides() {
        let slots = EdgeSlotSet.desiredSlots(placement: .allScreens, connectedKeys: ["A", "B"], sides: [.right])
        XCTAssertEqual(slots, [
            EdgeSlotSet.SlotKey(display: "A", side: .right),
            EdgeSlotSet.SlotKey(display: "B", side: .right),
        ])
    }

    func testEdgeKeysNeverCollideWithIslandKeys() {
        let edge = EdgeSlotSet.SlotKey(display: "A", side: .right).description
        let island = IslandSlotSet.SlotKey(display: "A", slot: 0).description
        XCTAssertNotEqual(edge, island)
    }

    // MARK: Geometry

    func testRightBarHugsRightEdgeAndLeftBarHugsLeft() {
        let s = screen()
        let r = PanelGeometry.edgeBarTargetFrame(side: .right, contentHeight: 300, width: 56, on: s, metrics: metrics)
        let l = PanelGeometry.edgeBarTargetFrame(side: .left, contentHeight: 300, width: 56, on: s, metrics: metrics)
        XCTAssertEqual(r.maxX, s.visibleFrame.maxX - 8, accuracy: 0.001)
        XCTAssertEqual(l.minX, s.visibleFrame.minX + 8, accuracy: 0.001)
        XCTAssertEqual(r.height, 300)
    }

    func testTallContentIsClampedBetweenMenuBarAndBottomBar() {
        let s = screen()
        let f = PanelGeometry.edgeBarTargetFrame(side: .right, contentHeight: 5000, width: 56, on: s, metrics: metrics)
        XCTAssertGreaterThanOrEqual(f.minY, metrics.bottomGap + metrics.panelHeight)
        XCTAssertLessThanOrEqual(f.maxY, s.topUsableY + 0.001)
        XCTAssertTrue(s.visibleFrame.contains(f))
    }

    func testMinimumSpacingIsEnforced() {
        let s = screen()
        let f = PanelGeometry.edgeBarTargetFrame(side: .right, contentHeight: 5000, width: 56, on: s, gap: 0, margin: 0, metrics: metrics)
        XCTAssertEqual(s.visibleFrame.maxX - f.maxX, PanelGeometry.edgeBarMinimumSpacing, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(f.minY - (metrics.bottomGap + metrics.panelHeight), PanelGeometry.edgeBarMinimumSpacing - 0.001)
    }

    func testNonZeroOriginSecondaryDisplayStaysOnItsOwnDisplay() {
        let s = screen(origin: CGPoint(x: -1920, y: -300), size: CGSize(width: 1920, height: 1080))
        for side in EdgeSide.allCases {
            let f = PanelGeometry.edgeBarTargetFrame(side: side, contentHeight: 600, width: 56, on: s, metrics: metrics)
            XCTAssertTrue(s.visibleFrame.contains(f), "\(side) must stay inside visibleFrame")
        }
    }

    func testShortAndNarrowScreensNeverGoNegative() {
        let short = screen(size: CGSize(width: 1280, height: 60))
        let f = PanelGeometry.edgeBarTargetFrame(side: .left, contentHeight: 400, width: 56, on: short, metrics: metrics)
        XCTAssertGreaterThanOrEqual(f.height, 0)
        XCTAssertEqual(f.height, 0, "no room above the bottom bar collapses the bar")
        let narrow = screen(size: CGSize(width: 40, height: 800))
        let n = PanelGeometry.edgeBarTargetFrame(side: .right, contentHeight: 200, width: 56, on: narrow, metrics: metrics)
        XCTAssertGreaterThanOrEqual(n.width, 0)
        XCTAssertGreaterThanOrEqual(n.minX, narrow.frame.minX)
    }

    func testNotchSafeAreaCapsTheTop() {
        var s = screen()
        s.safeAreaTop = 60
        let f = PanelGeometry.edgeBarTargetFrame(side: .right, contentHeight: 5000, width: 56, on: s, metrics: metrics)
        XCTAssertLessThanOrEqual(f.maxY, s.topUsableY + 0.001)
    }
}
