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
        XCTAssertEqual(QuickToggleID.parse(nil).count, 12)
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

    func testFullScreenCentersTheTwoColumnWall() {
        // Same wall as the floating panel: cards keep their size, only the frame changes.
        XCTAssertEqual(PinboardFullScreen.gridWidth(), 320)
        let o = PinboardFullScreen.origin(gridWidth: 320, gridHeight: 400,
                                          visible: (x: 0, y: 0, w: 1440, h: 900))
        XCTAssertEqual(o.x, 560); XCTAssertEqual(o.y, 250)
        // Taller than the screen: pins to the top, the view scrolls.
        let tall = PinboardFullScreen.origin(gridWidth: 320, gridHeight: 2000,
                                             visible: (x: 0, y: 0, w: 1440, h: 900))
        XCTAssertEqual(tall.x, 560); XCTAssertEqual(tall.y, 0)
        // Respects a non-zero visible origin.
        let off = PinboardFullScreen.origin(gridWidth: 320, gridHeight: 400,
                                            visible: (x: 100, y: 50, w: 1000, h: 800))
        XCTAssertEqual(off.x, 440); XCTAssertEqual(off.y, 250)
    }
}
