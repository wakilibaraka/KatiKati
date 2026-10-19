import XCTest
@testable import KatiKati

final class EdgeBarPrefsTests: XCTestCase {
    func testDefaultsKeepOldZoneAndModernFlyout() {
        let p = EdgeBarPrefs()
        XCTAssertEqual(p.zoneInset.dx, 2, accuracy: 1e-9)
        XCTAssertEqual(p.zoneInset.dy, 6, accuracy: 1e-9)
        XCTAssertEqual(p.flyoutStyle, .modern)
        XCTAssertEqual(p.iconSet, .classic)
        XCTAssertEqual(p.magnifyAmount.peak, DeckMagnification.maxScale)
    }

    func testClampAndRoundTrip() {
        var p = EdgeBarPrefs()
        p.openDelay = 99; p.sensitivity = -3
        XCTAssertEqual(p.clamped().openDelay, 1.5); XCTAssertEqual(p.clamped().sensitivity, 0)
        p.openDelay = .nan
        XCTAssertEqual(p.clamped().openDelay, EdgeBarPrefs.defaultOpenDelay)
        let d = UserDefaults(suiteName: "EdgeBarPrefsTests.\(UUID())")!
        XCTAssertEqual(EdgeBarPrefs.load(d), EdgeBarPrefs())
        var q = EdgeBarPrefs(); q.iconSet = .realistic; q.flyoutStyle = .glass; q.magnifyAmount = .bold; q.openDelay = 1
        q.save(d)
        XCTAssertEqual(EdgeBarPrefs.load(d), q)
        XCTAssertEqual(EdgeMagnifyAmount.allCases.map(\.peak), [1.25, 1.55, 1.85])
    }

    func testDwellOpensOnlyAfterDelayAndIgnoresARestingPointerAfterFold() {
        var d = EdgeDwell()
        let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(d.update(inside: true, now: t0, delay: 0.4))
        XCTAssertFalse(d.update(inside: true, now: t0.addingTimeInterval(0.2), delay: 0.4))
        XCTAssertTrue(d.update(inside: true, now: t0.addingTimeInterval(0.45), delay: 0.4))
        d.disarm()                                           // the bar opened, then folded with the pointer still on the pill
        XCTAssertFalse(d.update(inside: true, now: t0.addingTimeInterval(5), delay: 0.4))
        XCTAssertFalse(d.update(inside: true, now: t0.addingTimeInterval(9), delay: 0.4))
        XCTAssertFalse(d.update(inside: false, now: t0.addingTimeInterval(10), delay: 0.4))   // leaves → re-armed
        XCTAssertFalse(d.update(inside: true, now: t0.addingTimeInterval(11), delay: 0.4))
        XCTAssertTrue(d.update(inside: true, now: t0.addingTimeInterval(11.5), delay: 0.4))
    }

    func testLeavingBeforeTheDelayResetsTheDwell() {
        var d = EdgeDwell()
        let t0 = Date(timeIntervalSince1970: 1000)
        _ = d.update(inside: true, now: t0, delay: 0.4)
        _ = d.update(inside: false, now: t0.addingTimeInterval(0.3), delay: 0.4)
        XCTAssertFalse(d.update(inside: true, now: t0.addingTimeInterval(0.5), delay: 0.4))
    }

    func testZeroDelayOpensOnFirstPoll() {
        var d = EdgeDwell()
        XCTAssertTrue(d.update(inside: true, now: Date(), delay: 0))
    }

    func testClickOnlyOpensOnPressAndIgnoresADragInProgress() {
        var d = EdgeDwell()
        let t = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(d.update(inside: true, now: t, delay: 0.4, clickOnly: true), "hover alone does nothing")
        XCTAssertTrue(d.update(inside: true, pressed: true, now: t, delay: 0.4, clickOnly: true))
        var e = EdgeDwell()
        _ = e.update(inside: false, pressed: true, now: t, delay: 0, clickOnly: true)   // button held outside…
        XCTAssertFalse(e.update(inside: true, pressed: true, now: t, delay: 0, clickOnly: true), "…then dragged in")
        XCTAssertFalse(e.update(inside: true, pressed: false, now: t, delay: 0, clickOnly: true))
        XCTAssertTrue(e.update(inside: true, pressed: true, now: t, delay: 0, clickOnly: true), "a fresh press works")
    }

    func testHoverDwellAlsoIgnoresAHeldButtonArrival() {
        var d = EdgeDwell()
        let t = Date(timeIntervalSince1970: 1000)
        _ = d.update(inside: false, pressed: true, now: t, delay: 0)
        XCTAssertFalse(d.update(inside: true, pressed: true, now: t, delay: 0))
        XCTAssertTrue(d.update(inside: true, pressed: false, now: t.addingTimeInterval(1), delay: 0))
    }

    func testScreenshotCommandNeverWritesAFile() {
        XCTAssertEqual(ScreenshotCommand.arguments, ["-i", "-c"])
        XCTAssertFalse(ScreenshotCommand.arguments.contains { $0.hasPrefix("/") || $0.hasSuffix(".png") })
    }

    func testBarStyleDefaultsToPaperForOldBlobsAndRoundTrips() throws {
        let old = #"{"openDelay":1,"sensitivity":0.5,"magnifyAmount":"bold","iconSet":"modern","flyoutStyle":"glass","openOnClick":true,"hoverLabels":false}"#
        let p = try JSONDecoder().decode(EdgeBarPrefs.self, from: Data(old.utf8))
        XCTAssertEqual(p.barStyle, .paper)
        XCTAssertEqual(p.iconSet, .modern)
        XCTAssertTrue(p.openOnClick)
        let d = UserDefaults(suiteName: "EdgeBarPrefsTests.\(UUID())")!
        var q = EdgeBarPrefs(); q.barStyle = .liquidGlass; q.save(d)
        XCTAssertEqual(EdgeBarPrefs.load(d).barStyle, .liquidGlass)
        XCTAssertEqual(EdgeBarStyle.allCases.map(\.rawValue), ["paper", "liquidGlass"], "stored ids are frozen")
    }

    func testNewPrefsDefaults() {
        XCTAssertFalse(EdgeBarPrefs().openOnClick)
        XCTAssertTrue(EdgeBarPrefs().hoverLabels)
    }
}
