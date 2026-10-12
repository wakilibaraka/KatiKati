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

    func testWallColumnsFromWidth() {
        // A 2-column wall exactly fits a 320pt card wall (unit 154 + gap 12, twice).
        XCTAssertEqual(PinboardFullScreen.columns(forWidth: 320), 2)
        // 1300pt wide: 7 full columns of (154+12) slots.
        XCTAssertEqual(PinboardFullScreen.columns(forWidth: 1300), 7)
        // 1660pt wide: 10 columns.
        XCTAssertEqual(PinboardFullScreen.columns(forWidth: 1660), 10)
        // Thinner-than-2-columns: never below the panel's own two-column wall.
        XCTAssertEqual(PinboardFullScreen.columns(forWidth: 40), 2)
        // Zero/undefined: the same guard in production, no crash on a truncated screen.
        XCTAssertEqual(PinboardFullScreen.columns(forWidth: 0), 2)
    }

    func testWallPacksIntoFullWidthRows() {
        // Four columns: a small takes one slot, a wide two. Rows flush at 4 slots.
        let rows = PinboardLayout.wall([.weather, .calendar, .nowPlaying, .countdown, .clock, .weather, .calculator, .battery, .topApps], columns: 4)
        XCTAssertEqual(rows, [ [.weather, .calendar, .nowPlaying, .countdown],
                               [.clock, .weather],
                               [.calculator, .battery, .topApps] ])
        // A wide that does not fit flushes the row first; left-overs stay left.
        let rows2 = PinboardLayout.wall([.weather, .calendar, .nowPlaying, .calculator, .countdown, .clock], columns: 4)
        XCTAssertEqual(rows2, [ [.weather, .calendar, .nowPlaying],
                                [.calculator, .countdown],
                                [.clock] ])
        // Two-columns: wide takes a row of its own; single smalls go left.
        let rows3 = PinboardLayout.wall([.calculator, .weather, .clock], columns: 2)
        XCTAssertEqual(rows3, [ [.calculator], [.weather], [.clock] ])
        // Nothing to pack.
        XCTAssertEqual(PinboardLayout.wall([], columns: 4), [])
        // Order is preserved: the four slots fill first-come-first-served.
        let rows4 = PinboardLayout.wall([.weather, .battery, .clock, .nowPlaying, .countdown], columns: 4)
        // (clock is wide: 1 + 1 + 2 fills the four slots.)
        XCTAssertEqual(rows4, [ [.weather, .battery, .clock], [.nowPlaying, .countdown] ])
    }

    func testWallLargeOpensATallRow() {
        // Quick Settings is large: it opens a 7-column row; the following smalls stack two per slot
        // (weather,calendar | nowPlaying,countdown | battery,topApps) leaving 5 slots used of 7.
        // The wide that arrives afterwards flushes that row and starts its own; 2 + 2 + 1 + 2 fills 7.
        let rows = PinboardLayout.wall([.quickSettings, .weather, .calendar, .nowPlaying, .countdown, .battery, .topApps, .clock, .batteries, .network, .calculator], columns: 7)
        XCTAssertEqual(rows, [ [.quickSettings, .weather, .calendar, .nowPlaying, .countdown, .battery, .topApps],
                               [.clock, .batteries, .network, .calculator] ])
    }
}
