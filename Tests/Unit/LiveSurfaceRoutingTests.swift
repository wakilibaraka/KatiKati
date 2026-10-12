import XCTest
@testable import KatiKati

// Phase 8b-5 — tests for the pure notch/dock event router. The whole routing matrix, the dedupe
// cooldown and the OS-banner rule are pinned here: no UI, no clock, no permissions.

final class LiveSurfaceRoutingTests: XCTestCase {
    private let both: Set<LiveSurface> = [.dock, .notch]

    // MARK: - targets

    func testAutomaticPrefersNotchWhenUsable() {
        XCTAssertEqual(LiveSurfaceRouting.targets(route: .automatic, usable: both), [.notch])
    }

    func testAutomaticFallsBackToDockWithoutNotch() {
        XCTAssertEqual(LiveSurfaceRouting.targets(route: .automatic, usable: [.dock]), [.dock])
    }

    func testExplicitNotchAndDockHonouredWhenBothUsable() {
        XCTAssertEqual(LiveSurfaceRouting.targets(route: .notch, usable: both), [.notch])
        XCTAssertEqual(LiveSurfaceRouting.targets(route: .dock, usable: both), [.dock])
    }

    /// A chosen surface that is disabled / hidden / absent falls through — never doubled, never lost.
    func testChosenSurfaceUnusableFallsThroughToTheOther() {
        XCTAssertEqual(LiveSurfaceRouting.targets(route: .notch, usable: [.dock]), [.dock])
        XCTAssertEqual(LiveSurfaceRouting.targets(route: .dock, usable: [.notch]), [.notch])
    }

    func testBothIsExplicitOptInAndLimitedToUsable() {
        XCTAssertEqual(LiveSurfaceRouting.targets(route: .both, usable: both), both)
        XCTAssertEqual(LiveSurfaceRouting.targets(route: .both, usable: [.dock]), [.dock])
    }

    func testOffAndNothingUsableDeliverNowhere() {
        XCTAssertEqual(LiveSurfaceRouting.targets(route: .off, usable: both), [])
        for route in LiveEventRoute.allCases {
            XCTAssertEqual(LiveSurfaceRouting.targets(route: route, usable: []), [])
        }
    }

    /// Only `.both` may ever produce two targets.
    func testNonBothRoutesNeverDuplicate() {
        for route in LiveEventRoute.allCases where route != .both {
            XCTAssertLessThanOrEqual(LiveSurfaceRouting.targets(route: route, usable: both).count, 1, "\(route)")
        }
    }

    // MARK: - OS banner

    func testBannerOnlyWhenNoInAppSurfaceShowedIt() {
        XCTAssertTrue(LiveSurfaceRouting.shouldPostOSBanner(bannersEnabled: true, route: .automatic, shownOn: []))
        XCTAssertFalse(LiveSurfaceRouting.shouldPostOSBanner(bannersEnabled: true, route: .automatic, shownOn: [.notch]))
    }

    func testBannerOffByDefaultSettingAndWhenEventsOff() {
        XCTAssertFalse(LiveSurfaceRouting.shouldPostOSBanner(bannersEnabled: false, route: .automatic, shownOn: []))
        XCTAssertFalse(LiveSurfaceRouting.shouldPostOSBanner(bannersEnabled: true, route: .off, shownOn: []))
    }

    // MARK: - dedupe

    func testRepeatInsideCooldownIsDropped() {
        var d = LiveEventDeduper(cooldown: 5)
        let t0 = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(d.shouldDeliver(.timerFinished(total: 60), now: t0))
        XCTAssertFalse(d.shouldDeliver(.timerFinished(total: 60), now: t0.addingTimeInterval(4.9)))
    }

    func testRepeatAfterCooldownIsDelivered() {
        var d = LiveEventDeduper(cooldown: 5)
        let t0 = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(d.shouldDeliver(.timerFinished(total: 60), now: t0))
        XCTAssertTrue(d.shouldDeliver(.timerFinished(total: 60), now: t0.addingTimeInterval(5)))
    }

    func testDifferentEventsAreIndependent() {
        var d = LiveEventDeduper(cooldown: 5)
        let t0 = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(d.shouldDeliver(.timerFinished(total: 60), now: t0))
        XCTAssertTrue(d.shouldDeliver(.stopwatchStopped(elapsed: 3), now: t0))
        XCTAssertTrue(d.shouldDeliver(.focusPhaseChanged(phase: .focus), now: t0))
        XCTAssertTrue(d.shouldDeliver(.focusPhaseChanged(phase: .shortBreak), now: t0))
    }

    /// Payload that makes it a different event (the track) is part of the key; payload that does not
    /// (the stopwatch's elapsed time) is not.
    func testKeyIncludesIdentityNotIncidentalPayload() {
        var d = LiveEventDeduper(cooldown: 5)
        let t0 = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(d.shouldDeliver(.trackChanged(title: "A", artist: "X"), now: t0))
        XCTAssertTrue(d.shouldDeliver(.trackChanged(title: "B", artist: "X"), now: t0))
        XCTAssertTrue(d.shouldDeliver(.stopwatchStopped(elapsed: 3), now: t0))
        XCTAssertFalse(d.shouldDeliver(.stopwatchStopped(elapsed: 99), now: t0.addingTimeInterval(1)))
    }

    // MARK: - dispatcher (what LiveEventCenter delegates to)

    private let event = LiveEvent.timerFinished(total: 60)
    private let t0 = Date(timeIntervalSince1970: 5_000)

    func testDispatcherShowsOnOneSurfaceByDefault() {
        var d = LiveEventDispatcher()
        XCTAssertEqual(d.targets(for: event, route: .automatic, usable: both, now: t0), [.notch])
    }

    func testDispatcherBothIsTheOnlyWayToShowTwice() {
        var d = LiveEventDispatcher()
        XCTAssertEqual(d.targets(for: event, route: .both, usable: both, now: t0), both)
    }

    func testDispatcherDropsRepeatInsideCooldownAndAllowsLater() {
        var d = LiveEventDispatcher()
        XCTAssertEqual(d.targets(for: event, route: .dock, usable: both, now: t0), [.dock])
        XCTAssertEqual(d.targets(for: event, route: .dock, usable: both, now: t0.addingTimeInterval(1)), [])
        XCTAssertEqual(d.targets(for: event, route: .dock, usable: both, now: t0.addingTimeInterval(6)), [.dock])
    }

    /// A routed-off or unusable event must not burn the cooldown for a later, real delivery.
    func testDispatcherOffDoesNotConsumeCooldown() {
        var d = LiveEventDispatcher()
        XCTAssertEqual(d.targets(for: event, route: .off, usable: both, now: t0), [])
        XCTAssertEqual(d.targets(for: event, route: .automatic, usable: [], now: t0), [])
        XCTAssertEqual(d.targets(for: event, route: .automatic, usable: [.dock], now: t0.addingTimeInterval(1)), [.dock])
    }

    // MARK: - shared feed tick gate

    func testTickGateIsRefcountedAcrossSurfaces() {
        var g = LiveTickGate()
        XCTAssertFalse(g.isActive)
        XCTAssertTrue(g.retain(), "first surface starts the tick")
        XCTAssertFalse(g.retain(), "second surface shares it")
        XCTAssertFalse(g.release(), "one surface still needs the tick")
        XCTAssertTrue(g.isActive)
        XCTAssertTrue(g.release(), "last surface stops the tick")
        XCTAssertFalse(g.isActive)
        XCTAssertFalse(g.release(), "extra release is ignored")
        XCTAssertEqual(g.users, 0)
        XCTAssertTrue(g.retain(), "can start again after a full stop")
    }

    // MARK: - OS banner fallback

    func testBannerPostedOnlyWhenNoInAppSurfaceUsable() {
        var d = LiveEventDispatcher()
        XCTAssertEqual(d.plan(for: event, route: .automatic, usable: [], bannersEnabled: true, now: t0), .init(surfaces: [], postBanner: true))
    }

    func testBannerNeverAccompaniesAnInAppToast() {
        var d = LiveEventDispatcher()
        XCTAssertEqual(d.plan(for: event, route: .automatic, usable: both, bannersEnabled: true, now: t0), .init(surfaces: [.notch], postBanner: false))
    }

    /// The in-app repeat inside cooldown must not leak out as a banner.
    func testInAppRepeatIsNotRebannered() {
        var d = LiveEventDispatcher()
        _ = d.plan(for: event, route: .dock, usable: both, bannersEnabled: true, now: t0)
        XCTAssertEqual(d.plan(for: event, route: .dock, usable: both, bannersEnabled: true, now: t0.addingTimeInterval(1)), .init(surfaces: [], postBanner: false))
    }

    func testBannerOptInOffAndRoutedOffNeverPost() {
        var d = LiveEventDispatcher()
        XCTAssertFalse(d.plan(for: event, route: .automatic, usable: [], bannersEnabled: false, now: t0).postBanner)
        XCTAssertFalse(d.plan(for: event, route: .off, usable: [], bannersEnabled: true, now: t0).postBanner)
    }

    func testBannerRepeatInsideCooldownDropped() {
        var d = LiveEventDispatcher()
        XCTAssertTrue(d.plan(for: event, route: .automatic, usable: [], bannersEnabled: true, now: t0).postBanner)
        XCTAssertFalse(d.plan(for: event, route: .automatic, usable: [], bannersEnabled: true, now: t0.addingTimeInterval(2)).postBanner)
    }
}
