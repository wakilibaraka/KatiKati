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
}
