import XCTest
@testable import KatiKati

final class PinboardWidgetsTests: XCTestCase {
    func testParseDefaultsAndDrops() {
        XCTAssertEqual(PinboardWidget.parse(nil), PinboardWidget.defaultOrder)
        XCTAssertEqual(PinboardWidget.parse(""), [])
        XCTAssertEqual(PinboardWidget.parse("clock,bogus,clock,weather"), [.clock, .weather])
    }

    func testRoundTrip() {
        let w: [PinboardWidget] = [.weather, .clock, .quickSettings]
        XCTAssertEqual(PinboardWidget.parse(PinboardWidget.serialize(w)), w)
    }

    func testLayoutPairsSmalls() {
        let rows = PinboardLayout.rows([.weather, .calendar, .clock, .nowPlaying, .quickSettings, .countdown])
        XCTAssertEqual(rows, [[.weather, .calendar], [.clock], [.quickSettings], [.nowPlaying, .countdown]])
    }

    func testLayoutSmallsAcrossWideWaitForPair() {
        XCTAssertEqual(PinboardLayout.rows([.weather, .clock, .calendar]), [[.clock], [.weather, .calendar]])
    }

    func testToggleParseAndFlags() {
        XCTAssertEqual(QuickToggleID.parse(nil).count, 14, "trueTone + vpn joined the catalog")
        XCTAssertEqual(QuickToggleID.parse("wifi,nope,darkMode"), [.wifi, .darkMode])
        XCTAssertTrue(QuickToggleID.emptyTrash.needsConfirm)
        XCTAssertFalse(QuickToggleID.darkMode.isAction)
        XCTAssertTrue(QuickToggleID.ejectDisks.isAction)
    }

    func testPlacementClamp() {
        let r = PinboardPlacement.clamp(origin: (x: 5000, y: -50), size: (w: 300, h: 400), visible: (x: 0, y: 0, w: 1440, h: 900))
        XCTAssertEqual(r.x, 1140); XCTAssertEqual(r.y, 0)
    }

    func testPinboardStyleDefaultsFullScreenAndRejectsGarbage() {
        XCTAssertEqual(PinboardStyle.parse(nil), .fullScreen)
        XCTAssertEqual(PinboardStyle.parse("bogus"), .fullScreen)
        XCTAssertEqual(PinboardStyle.parse("floating"), .floating)
        XCTAssertEqual(PinboardStyle.allCases.count, 2)
    }

    func testGridPlacesCardsDenselyWithoutHoles() {
        // Four columns: Quick Settings (2x2) takes the top-left, the smalls fill the space beside it.
        let r = PinboardGrid.pack([.quickSettings, .weather, .calendar, .nowPlaying, .countdown], columns: 4)
        XCTAssertEqual(r.cells.first, PinboardGrid.Cell(widget: .quickSettings, col: 0, row: 0, cols: 2, rows: 2))
        XCTAssertEqual(r.cells.dropFirst().map { [$0.col, $0.row] }, [[2, 0], [3, 0], [2, 1], [3, 1]])
        XCTAssertEqual(r.rows, 2)
    }

    func testGridWideSkipsToTheFirstFreeSpotAndSmallsBackfill() {
        // Three columns: the wide card sits beside the small (columns 1-2); the next small starts a new row.
        let r = PinboardGrid.pack([.weather, .clock, .calendar], columns: 3)
        XCTAssertEqual(r.cells.map { [$0.col, $0.row] }, [[0, 0], [1, 0], [0, 1]])
        // A wide that does not fit after a small in two columns drops to the next row; a later small backfills the gap.
        let t = PinboardGrid.pack([.weather, .clock, .calendar], columns: 2)
        XCTAssertEqual(t.cells.map { [$0.col, $0.row] }, [[0, 0], [0, 1], [1, 0]])
    }

    func testGridNeverOverlapsAndKeepsEveryCard() {
        let all = PinboardWidget.defaultOrder
        for columns in 2...12 {
            let r = PinboardGrid.pack(all, columns: columns)
            XCTAssertEqual(r.cells.count, all.count)
            var used = Set<[Int]>()
            for c in r.cells {
                XCTAssertLessThanOrEqual(c.col + c.cols, max(2, columns))
                for rr in c.row..<(c.row + c.rows) { for cc in c.col..<(c.col + c.cols) {
                    XCTAssertTrue(used.insert([rr, cc]).inserted, "overlap at \(rr),\(cc) with \(columns) columns")
                } }
            }
        }
    }

    func testFitPicksTheColumnCountThatFillsTheScreen() {
        let all = PinboardWidget.defaultOrder
        let f = PinboardGrid.fit(all, width: 1614, height: 1016)
        // The chosen grid, scaled, must fit the screen and beat a narrow two-column layout.
        let w = Double(f.columns) * 154 + Double(f.columns - 1) * 12
        let h = Double(f.rows) * 154 + Double(f.rows - 1) * 12
        XCTAssertLessThanOrEqual(w * f.scale, 1614 + 1e-6)
        XCTAssertLessThanOrEqual(h * f.scale, 1016 + 1e-6)
        XCTAssertGreaterThan(f.scale, PinboardGrid.fit(all, width: 1614, height: 1016, maxColumns: 2).scale)
        XCTAssertGreaterThan(f.scale, 1.2, "a full-size screen should enlarge the cards")
        XCTAssertGreaterThan(w * f.scale, 1614 * 0.6, "and use most of the width")
    }

    func testFitHandlesEmptyAndTinyScreens() {
        XCTAssertEqual(PinboardGrid.fit([], width: 1000, height: 800), PinboardGrid.Fit(columns: 2, rows: 0, scale: 1))
        XCTAssertGreaterThan(PinboardGrid.fit(PinboardWidget.defaultOrder, width: 300, height: 300).scale, 0)
    }

    func testControlCenterTileMapsOnlyTheSixPortedWidgets() {
        XCTAssertEqual(PinboardWidget.calculator.controlCenterTile, .calculator)
        XCTAssertEqual(PinboardWidget.screenTime.controlCenterTile, .screenTime)
        XCTAssertEqual(PinboardWidget.network.controlCenterTile, .network)
        XCTAssertEqual(PinboardWidget.battery.controlCenterTile, .battery)
        XCTAssertEqual(PinboardWidget.topApps.controlCenterTile, .topApps)
        XCTAssertEqual(PinboardWidget.batteries.controlCenterTile, .batteries)
        for w in PinboardWidget.allCases where w.controlCenterTile != nil {
            XCTAssertTrue([PinboardWidget.calculator, .screenTime, .network, .battery, .topApps, .batteries].contains(w))
        }
        XCTAssertNil(PinboardWidget.quickSettings.controlCenterTile, "quick settings lives on as the grid")
        XCTAssertNil(PinboardWidget.weather.controlCenterTile, "already a pane tile")
    }
}
