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
        q.barStyle = .fluid; q.save(d)
        XCTAssertEqual(EdgeBarPrefs.load(d).barStyle, .fluid)
        q.barStyle = .bezelDock; q.save(d)
        XCTAssertEqual(EdgeBarPrefs.load(d).barStyle, .bezelDock)
        XCTAssertEqual(EdgeBarStyle.allCases.map(\.rawValue), ["paper", "liquidGlass", "fluid", "bezelDock"], "stored ids are frozen")
    }

    func testNewPrefsDefaults() {
        XCTAssertFalse(EdgeBarPrefs().openOnClick)
        XCTAssertTrue(EdgeBarPrefs().hoverLabels)
        XCTAssertTrue(EdgeBarPrefs().appsRunningOnly)
        XCTAssertTrue(EdgeBarPrefs().showRunningDots)
        XCTAssertFalse(EdgeBarPrefs().collapseToButton)
        XCTAssertFalse(EdgeBarPrefs().showAppsInBar)
        XCTAssertEqual(EdgeBarPrefs().hydrationIntervalMinutes, 45)
        XCTAssertEqual(EdgeBarPrefs().hydrationDailyGoal, 8)
        XCTAssertEqual(EdgeBarPrefs().foodFastingProtocol, "16:8")
        XCTAssertTrue(EdgeBarPrefs().edgeSoundEffectsEnabled)
    }
}

final class TendederoStoreTests: XCTestCase {
    func testAddDeduplicatesAndTracksUnread() {
        var store = TendederoStore()
        let t0 = Date(timeIntervalSince1970: 1000)
        let first = store.add(kind: .text("hello"), title: "hello", now: t0)
        _ = store.add(kind: .link(URL(string: "https://example.com")!), title: "example.com", now: t0.addingTimeInterval(1))
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.unreadCount, 2)

        // Re-adding identical text moves it to the top instead of duplicating
        _ = store.add(kind: .text("hello"), title: "hello", now: t0.addingTimeInterval(2))
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.first?.id, first.id)

        store.markAllRead()
        XCTAssertEqual(store.unreadCount, 0)
    }

    func testPinningPersistsThroughCapacityEvictionAndClearUnpinned() {
        var store = TendederoStore()
        store.capacityMode = .capped(maxUnpinned: 2, expireAfter: 3600)
        let t0 = Date(timeIntervalSince1970: 1000)

        let pinned = store.add(kind: .text("keep me"), title: "keep me", now: t0)
        store.togglePin(id: pinned.id)
        XCTAssertTrue(store.items.first?.isPinned == true)

        _ = store.add(kind: .text("u1"), title: "u1", now: t0.addingTimeInterval(1))
        _ = store.add(kind: .text("u2"), title: "u2", now: t0.addingTimeInterval(2))
        _ = store.add(kind: .text("u3"), title: "u3", now: t0.addingTimeInterval(3))

        // u1 evicted (FIFO), pinned + u2 + u3 remain
        XCTAssertEqual(store.items.count, 3)
        XCTAssertTrue(store.items.contains(where: { $0.id == pinned.id }))
        XCTAssertFalse(store.items.contains(where: { $0.title == "u1" }))

        store.clearUnpinned()
        XCTAssertEqual(store.items.map(\.id), [pinned.id])
    }

    func testExpiryAndUnlimitedModeAndSpringDamping() {
        var store = TendederoStore()
        store.capacityMode = .capped(maxUnpinned: 10, expireAfter: 60)
        let t0 = Date(timeIntervalSince1970: 1000)
        let old = store.add(kind: .text("old"), title: "old", now: t0)
        store.pruneExpired(now: t0.addingTimeInterval(120))
        XCTAssertFalse(store.items.contains(where: { $0.id == old.id }))

        store.capacityMode = .unlimited
        for i in 0..<25 { _ = store.add(kind: .text("item-\(i)"), title: "item-\(i)", now: t0) }
        XCTAssertEqual(store.items.count, 25)

        let target = store.items[0].id
        store.applyImpulse(id: target, degrees: 12)
        for _ in 0..<240 { store.tickPhysics(dt: 1.0 / 60.0) }
        XCTAssertEqual(store.items[0].swingAngleDegrees, 0, accuracy: 0.1)
    }
}

/// NP-1: the clothesline is quiet unless the owner asked for it. Both reads use the unset-key idiom, so a
/// never-set key, an explicit off and a stale value all land on the calm behaviour.
final class TendederoPolicyTests: XCTestCase {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "TendederoPolicyTests.\(UUID())")!
    }

    func testQuietByDefault() {
        let d = defaults()
        XCTAssertEqual(TendederoPolicy.captureMode(d), .screenshotsAndManualClipboard)
        XCTAssertFalse(TendederoPolicy.showSidebarOnNewItem(d))
        XCTAssertFalse(TendederoPolicy.shouldStartMonitoringAtLaunch(d))
    }

    func testExplicitChoicesSurviveAndUnknownRawValuesFallBack() {
        let d = defaults()
        d.set(TendederoCaptureMode.screenshotsAndAutoClipboard.rawValue, forKey: TendederoPolicy.captureModeKey)
        XCTAssertEqual(TendederoPolicy.captureMode(d), .screenshotsAndAutoClipboard)
        XCTAssertTrue(TendederoPolicy.shouldStartMonitoringAtLaunch(d))
        d.set(TendederoCaptureMode.screenshotsAndManualClipboard.rawValue, forKey: TendederoPolicy.captureModeKey)
        XCTAssertEqual(TendederoPolicy.captureMode(d), .screenshotsAndManualClipboard)
        XCTAssertFalse(TendederoPolicy.shouldStartMonitoringAtLaunch(d))
        d.set("someFutureMode", forKey: TendederoPolicy.captureModeKey)
        XCTAssertEqual(TendederoPolicy.captureMode(d), .screenshotsAndManualClipboard,
                       "a stale value must not re-enable auto-hanging")

        TendederoPolicy.setShowSidebarOnNewItem(true, defaults: d)
        XCTAssertTrue(TendederoPolicy.showSidebarOnNewItem(d))
        XCTAssertTrue(TendederoPolicy.shouldStartMonitoringAtLaunch(d))
        TendederoPolicy.setShowSidebarOnNewItem(false, defaults: d)
        XCTAssertFalse(TendederoPolicy.showSidebarOnNewItem(d))
        XCTAssertFalse(TendederoPolicy.shouldStartMonitoringAtLaunch(d))
    }

    func testClipboardToastIsOffUnlessStoredOn() {
        let d = defaults()
        XCTAssertFalse(ClipboardToastDefaults.enabledByDefault)
        XCTAssertFalse(ClipboardToastDefaults.isEnabled(d))
        d.set(true, forKey: ClipboardSettingsKeys.notchToastKey)
        XCTAssertTrue(ClipboardToastDefaults.isEnabled(d))
    }

    func testRestOptionGrabRejectsExpandedZoneOutsidePillFrame() {
        let pillFrame = CGRect(x: 0, y: 300, width: 14, height: 100)
        XCTAssertTrue(DeckGeometry.acceptsRestOptionGrab(mouse: CGPoint(x: 7, y: 350), pillFrame: pillFrame, optionDown: true))
        XCTAssertFalse(DeckGeometry.acceptsRestOptionGrab(mouse: CGPoint(x: 7, y: 350), pillFrame: pillFrame, optionDown: false))
        // Expanded restZone (`dx: -2, dy: -6`) covers (15, 350) and (7, 296); both must remain click-through.
        XCTAssertFalse(DeckGeometry.acceptsRestOptionGrab(mouse: CGPoint(x: 15, y: 350), pillFrame: pillFrame, optionDown: true))
        XCTAssertFalse(DeckGeometry.acceptsRestOptionGrab(mouse: CGPoint(x: 7, y: 296), pillFrame: pillFrame, optionDown: true))
        XCTAssertFalse(DeckGeometry.acceptsRestOptionGrab(mouse: CGPoint(x: 7, y: 350), pillFrame: .zero, optionDown: true))
    }
}
