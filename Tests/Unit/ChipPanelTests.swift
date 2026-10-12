import XCTest
@testable import KatiKati

final class ChipPanelHoverMachineTests: XCTestCase {
    func testOpensOnlyAfterDelay() {
        var m = ChipPanelHoverMachine(openDelay: 0.35, closeGrace: 0.25)
        XCTAssertEqual(m.update(overChip: "a", overPanel: false, now: 0), .none)
        XCTAssertEqual(m.update(overChip: "a", overPanel: false, now: 0.34), .none)
        XCTAssertEqual(m.update(overChip: "a", overPanel: false, now: 0.36), .open(chipID: "a"))
        XCTAssertEqual(m.shown, "a")
    }

    func testSweepingAcrossChipsNeverOpens() {
        var m = ChipPanelHoverMachine(openDelay: 0.35, closeGrace: 0.25)
        XCTAssertEqual(m.update(overChip: "a", overPanel: false, now: 0), .none)
        XCTAssertEqual(m.update(overChip: "b", overPanel: false, now: 0.3), .none)   // restarts the clock
        XCTAssertEqual(m.update(overChip: "b", overPanel: false, now: 0.5), .none)
        XCTAssertEqual(m.update(overChip: nil, overPanel: false, now: 0.6), .none)
        XCTAssertTrue(m.isIdle)
    }

    func testBridgeToPanelKeepsItOpen() {
        var m = ChipPanelHoverMachine()
        _ = m.update(overChip: "a", overPanel: false, now: 0)
        _ = m.update(overChip: "a", overPanel: false, now: 0.4)
        XCTAssertEqual(m.update(overChip: nil, overPanel: false, now: 0.5), .none)   // gap starts
        XCTAssertEqual(m.update(overChip: nil, overPanel: true, now: 0.6), .none)    // reached the panel
        XCTAssertEqual(m.update(overChip: nil, overPanel: true, now: 5), .none)
        XCTAssertEqual(m.shown, "a")
    }

    func testClosesAfterGraceWhenPointerLeaves() {
        var m = ChipPanelHoverMachine()
        _ = m.update(overChip: "a", overPanel: false, now: 0)
        _ = m.update(overChip: "a", overPanel: false, now: 0.4)
        XCTAssertEqual(m.update(overChip: nil, overPanel: false, now: 1.0), .none)
        XCTAssertEqual(m.update(overChip: nil, overPanel: false, now: 1.2), .none)
        XCTAssertEqual(m.update(overChip: nil, overPanel: false, now: 1.26), .close)
        XCTAssertTrue(m.isIdle)
    }

    func testMovingToNeighbourSwitchesImmediately() {
        var m = ChipPanelHoverMachine()
        _ = m.update(overChip: "a", overPanel: false, now: 0)
        _ = m.update(overChip: "a", overPanel: false, now: 0.4)
        XCTAssertEqual(m.update(overChip: "b", overPanel: false, now: 0.5), .switchTo(chipID: "b"))
        XCTAssertEqual(m.shown, "b")
    }

    func testBlockedClosesAndPreventsOpening() {
        var m = ChipPanelHoverMachine()
        XCTAssertEqual(m.update(overChip: "a", overPanel: false, blocked: true, now: 0), .none)
        XCTAssertEqual(m.update(overChip: "a", overPanel: false, blocked: true, now: 1), .none)
        _ = m.update(overChip: "a", overPanel: false, now: 2)
        _ = m.update(overChip: "a", overPanel: false, now: 2.4)
        XCTAssertEqual(m.update(overChip: "a", overPanel: false, blocked: true, now: 2.5), .close)
    }
}

final class ChipPanelLayoutTests: XCTestCase {
    func testPreviewGridWrapsAndCaps() {
        XCTAssertEqual(ChipPanelLayout.previewGrid(count: 0), .init(columns: 0, rows: 0, shown: 0, hidden: 0))
        XCTAssertEqual(ChipPanelLayout.previewGrid(count: 1), .init(columns: 1, rows: 1, shown: 1, hidden: 0))
        XCTAssertEqual(ChipPanelLayout.previewGrid(count: 5), .init(columns: 4, rows: 2, shown: 5, hidden: 0))
        XCTAssertEqual(ChipPanelLayout.previewGrid(count: 20), .init(columns: 4, rows: 3, shown: 12, hidden: 8))
    }

    func testPreviewPlateGrowsWithCards() {
        let t = CGSize(width: 160, height: 100)
        let one = ChipPanelLayout.previewPlateSize(count: 1, thumb: t)
        let two = ChipPanelLayout.previewPlateSize(count: 2, thumb: t)
        XCTAssertEqual(one.width, 160 + 24)
        XCTAssertEqual(two.width, 160 * 2 + 10 + 24)
        XCTAssertEqual(one.height, two.height)
    }

    func testPlacementCentresAboveAnchor() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let anchor = CGRect(x: 700, y: 10, width: 60, height: 60)
        let p = ChipPanelLayout.placement(anchor: anchor, plate: CGSize(width: 200, height: 120), screen: screen)
        XCTAssertEqual(p.arrowOffsetFromCenter, 0, accuracy: 0.01)
        let plate = ChipPanelLayout.plateFrame(panelFrame: p.panelFrame)
        XCTAssertEqual(plate.midX, anchor.midX, accuracy: 0.01)
        XCTAssertGreaterThan(plate.minY, anchor.maxY)
    }

    func testPlacementClampsAtScreenEdgeAndKeepsArrowOnChip() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let anchor = CGRect(x: 10, y: 10, width: 60, height: 60)
        let p = ChipPanelLayout.placement(anchor: anchor, plate: CGSize(width: 400, height: 120), screen: screen)
        let plate = ChipPanelLayout.plateFrame(panelFrame: p.panelFrame)
        XCTAssertGreaterThanOrEqual(plate.minX, 8 - 0.01)
        XCTAssertLessThan(p.arrowOffsetFromCenter, 0)
        XCTAssertGreaterThanOrEqual(p.arrowOffsetFromCenter, -(200 - StackPopupMetrics.arrowInset))
    }
}
