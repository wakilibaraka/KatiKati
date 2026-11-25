import XCTest
@testable import KatiKati

/// 57a: the wheel-to-volume table behind the Control Center volume row.
final class ControlCenterScrollTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    func testPreciseTrackpadTravelAddsUpToSteps() {
        var state = ControlCenterScroll.State()
        // 3 pt is half a step: nothing yet, and nothing lost.
        XCTAssertNil(ControlCenterScroll.consume(deltaY: 3, precise: true, level: 0.5, state: &state, now: t0))
        // The other 3 pt completes it, upward.
        XCTAssertEqual(ControlCenterScroll.consume(deltaY: 3, precise: true, level: 0.5, state: &state, now: t0 + 0.1),
                       0.5 + ControlCenterScroll.volumePerStep)
        // Downward at the next tick, from the new level.
        XCTAssertEqual(ControlCenterScroll.consume(deltaY: -6, precise: true, level: 0.5125, state: &state, now: t0 + 0.2),
                       0.5125 - ControlCenterScroll.volumePerStep)
    }

    func testOneEventCanCarrySeveralSteps() {
        var state = ControlCenterScroll.State()
        XCTAssertEqual(ControlCenterScroll.consume(deltaY: 18, precise: true, level: 0.2, state: &state, now: t0),
                       0.2 + 3 * ControlCenterScroll.volumePerStep)
    }

    func testRateLimitHoldsASecondStepBackUntilTheIntervalPasses() {
        var state = ControlCenterScroll.State()
        _ = ControlCenterScroll.consume(deltaY: 6, precise: true, level: 0.4, state: &state, now: t0)
        // Enough travel, but 40 ms after the last step: the level must not move.
        XCTAssertNil(ControlCenterScroll.consume(deltaY: 6, precise: true, level: 0.4125, state: &state, now: t0 + 0.04))
        // The travel was kept, so the next event past the interval spends it.
        XCTAssertEqual(ControlCenterScroll.consume(deltaY: 0.0001, precise: true, level: 0.4125, state: &state, now: t0 + 0.061),
                       0.4125 + ControlCenterScroll.volumePerStep)
    }

    func testClampedAtBothEnds() {
        var state = ControlCenterScroll.State()
        XCTAssertEqual(ControlCenterScroll.consume(deltaY: 60, precise: true, level: 0.99, state: &state, now: t0), 1)
        var other = ControlCenterScroll.State()
        XCTAssertEqual(ControlCenterScroll.consume(deltaY: -60, precise: true, level: 0.01, state: &other, now: t0), 0)
    }

    func testNotchedWheelCountsOneClickAsTwoStepsWhateverItsLineSize() {
        for lines in [CGFloat(1), 3, 0.5] {
            var state = ControlCenterScroll.State()
            let up = ControlCenterScroll.consume(deltaY: lines, precise: false, level: 0.5, state: &state, now: t0)
            XCTAssertEqual(up, 0.5 + 2 * ControlCenterScroll.volumePerStep, "up, line size \(lines)")
            var down = ControlCenterScroll.State()
            XCTAssertEqual(ControlCenterScroll.consume(deltaY: -lines, precise: false, level: 0.5, state: &down, now: t0),
                           0.5 - 2 * ControlCenterScroll.volumePerStep, "down, line size \(lines)")
        }
    }

    func testNoiseIsIgnored() {
        var state = ControlCenterScroll.State()
        XCTAssertNil(ControlCenterScroll.consume(deltaY: 0, precise: true, level: 0.5, state: &state, now: t0))
        XCTAssertEqual(state, ControlCenterScroll.State())
    }
}

/// The switch grid's 4-or-5-per-row choice.
final class ControlCenterLayoutTests: XCTestCase {
    func testClassicPresetKeepsTodaysSectionOrder() {
        let classic = ControlCenterLayoutSpec.preset(.classic)
        XCTAssertEqual(classic.preset, .classic)
        XCTAssertEqual(classic.tiles.map(\.id), [
            .section(.header), .section(.peripherals), .section(.connectivity),
            .section(.nowPlaying), .section(.network), .section(.sliders),
            .section(.utilities), .section(.account),
        ])
        XCTAssertEqual(classic.tiles.first?.size, .hero)
        XCTAssertEqual(ControlCenterLayoutSpec.preset(.custom), classic)
    }

    func testPackerFillsRowsWithoutClippingATile() {
        let tiles: [ControlCenterTileSpec] = [
            .init(id: .section(.header), size: .hero),
            .init(id: .section(.network), size: .wide),
            .init(id: .section(.utilities)),
            .init(id: .section(.account)),
        ]
        let rows = ControlCenterPacker.rows(tiles, columns: 4)
        XCTAssertEqual(rows.map { $0.tiles.count }, [1, 3])
        XCTAssertEqual(rows.map(\.columnsUsed), [4, 4])
        XCTAssertEqual(rows[1].tiles.map(\.id), [tiles[1].id, tiles[2].id, tiles[3].id])
    }

    func testPackerStartsANewRowWhenTheRemainderIsTooSmall() {
        let tiles: [ControlCenterTileSpec] = [
            .init(id: .section(.network), size: .wide),
            .init(id: .section(.utilities), size: .wide),
            .init(id: .section(.account), size: .wide),
        ]
        let rows = ControlCenterPacker.rows(tiles, columns: 4)
        XCTAssertEqual(rows.map { $0.tiles.count }, [2, 1])
        XCTAssertEqual(rows.map(\.columnsUsed), [4, 2])
    }

    func testPackerDegradesToOneColumnBelowFourHundredPoints() {
        XCTAssertEqual(ControlCenterPacker.columns(width: 300), 1)
        XCTAssertEqual(ControlCenterPacker.columns(width: 399), 1)
        XCTAssertEqual(ControlCenterPacker.columns(width: 400), 4)
        let rows = ControlCenterPacker.rows(ControlCenterLayoutSpec.preset(.bento).tiles, columns: 1)
        XCTAssertEqual(rows.count, ControlCenterLayoutSpec.preset(.bento).tiles.count)
        XCTAssertTrue(rows.allSatisfy { $0.columnsUsed == 1 })
    }

    func testDedupeOnlyHidesWhatTheHeaderAlreadyAnswers() {
        let on = ControlCenterDedupeOptions()
        XCTAssertTrue(ControlCenterDedupe.hidesSystemRow(hasBatteryPill: true, options: on))
        XCTAssertFalse(ControlCenterDedupe.hidesSystemRow(hasBatteryPill: false, options: on))
        var off = on
        off.singleBattery = false
        XCTAssertFalse(ControlCenterDedupe.hidesSystemRow(hasBatteryPill: true, options: off))

        XCTAssertFalse(ControlCenterDedupe.hidesNowPlaying(surfacesOn: [], options: on))
        XCTAssertTrue(ControlCenterDedupe.hidesNowPlaying(surfacesOn: [.notch], options: on))
        XCTAssertTrue(ControlCenterDedupe.hidesNowPlaying(surfacesOn: [.dock], options: on))
        var override = on
        override.showNowPlayingAnyway = true
        XCTAssertFalse(ControlCenterDedupe.hidesNowPlaying(surfacesOn: [.notch, .dock], options: override))
        override.singleNowPlaying = false
        override.showNowPlayingAnyway = false
        XCTAssertFalse(ControlCenterDedupe.hidesNowPlaying(surfacesOn: [.notch], options: override))
    }

    func testMenuBarModeRepurposesTheEdgeDeckOnceAndOnlyOnce() {
        let edge = ControlCenterEdgeRole.implied(by: .edge, hasBeenTold: false)
        XCTAssertEqual(edge.role, .controlCenter)
        XCTAssertFalse(edge.needsPrompt)

        let first = ControlCenterEdgeRole.implied(by: .menuBar, hasBeenTold: false)
        XCTAssertEqual(first.role, .backgroundActivity)
        XCTAssertTrue(first.needsPrompt)

        let later = ControlCenterEdgeRole.implied(by: .menuBar, hasBeenTold: true)
        XCTAssertEqual(later.role, .backgroundActivity)
        XCTAssertFalse(later.needsPrompt)
        XCTAssertEqual(ControlCenterSurfaceMode.parse("menuBar"), .menuBar)
        XCTAssertEqual(ControlCenterSurfaceMode.parse("bogus"), .edge)
    }

    func testGlassParsesKnownValuesAndFallsBack() {
        XCTAssertEqual(ControlCenterGlassStyle.parse(nil), .semi)
        XCTAssertEqual(ControlCenterGlassStyle.parse("nonsense"), .semi)
        XCTAssertEqual(ControlCenterGlassStyle.parse("tinted"), .tinted)
        XCTAssertLessThan(ControlCenterGlassStyle.clear.cardAlpha, ControlCenterGlassStyle.tinted.cardAlpha)
    }

    func testLayoutCodecRoundTripsAndRejectsGarbage() {
        let spec = ControlCenterLayoutSpec.preset(.modular)
        let decoded = ControlCenterLayoutCodec.decode(ControlCenterLayoutCodec.encode(spec))
        XCTAssertEqual(decoded, spec)
        XCTAssertNil(ControlCenterLayoutCodec.decode(nil))
        XCTAssertNil(ControlCenterLayoutCodec.decode("v1|modular|modular|"))
        XCTAssertNil(ControlCenterLayoutCodec.decode("v2|modular|modular|section.header:hero"))
        let tolerant = ControlCenterLayoutCodec.decode("v1|bento|bento|section.header:hero,bogus.x:wide,section.network:wide")
        XCTAssertEqual(tolerant?.tiles.map(\.id), [.section(.header), .section(.network)])
        XCTAssertEqual(tolerant?.tiles.last?.size, .wide)
    }

    func testTileTokensRoundTripAndUnknownTokensDrop() {
        XCTAssertEqual(ControlCenterTileID(token: "section.nowPlaying"), .section(.nowPlaying))
        XCTAssertEqual(ControlCenterTileID(token: "section.nowPlaying")?.token, "section.nowPlaying")
        XCTAssertEqual(ControlCenterTileID(token: "toggle.nonsense"), nil)
        XCTAssertEqual(ControlCenterTileID(token: "section.nope"), nil)
    }
}

final class ControlCenterGridTests: XCTestCase {
    func testRowsRoundUp() {
        XCTAssertEqual(ControlCenterGrid.rows(count: 16, columns: 4), 4)
        XCTAssertEqual(ControlCenterGrid.rows(count: 16, columns: 5), 4)
        XCTAssertEqual(ControlCenterGrid.rows(count: 17, columns: 4), 5)
        XCTAssertEqual(ControlCenterGrid.rows(count: 17, columns: 5), 4)
        XCTAssertEqual(ControlCenterGrid.rows(count: 0, columns: 4), 0)
    }

    /// Room for four rows keeps the balanced 4 × 4 grid.
    func testFourFittingRowsKeepFourAcross() {
        XCTAssertEqual(ControlCenterGrid.columns(count: 16, rowsFit: 4), 4)
        XCTAssertEqual(ControlCenterGrid.columns(count: 16, rowsFit: 6), 4)
    }

    /// A short panel that can only hold three rows goes five per row.
    func testThreeFittingRowsGoFiveAcross() {
        XCTAssertEqual(ControlCenterGrid.columns(count: 16, rowsFit: 3), 5)
    }

    func testEmptyGridAndZeroRowsFallBackToFour() {
        XCTAssertEqual(ControlCenterGrid.columns(count: 0, rowsFit: 4), 4)
        XCTAssertEqual(ControlCenterGrid.columns(count: 16, rowsFit: 0), 4)
    }

    func testMicMuteTransitionPreservesPreMuteVolume() {
        let muted = QuickToggleID.resolvedMicTransition(turningMuteOn: true, currentInputVolume: 85, savedPrevious: 70)
        XCTAssertEqual(muted.targetVolume, 0)
        XCTAssertEqual(muted.nextSavedPrevious, 85)

        let unmuted = QuickToggleID.resolvedMicTransition(turningMuteOn: false, currentInputVolume: 0, savedPrevious: muted.nextSavedPrevious)
        XCTAssertEqual(unmuted.targetVolume, 85)
        XCTAssertEqual(unmuted.nextSavedPrevious, 85)

        let floored = QuickToggleID.resolvedMicTransition(turningMuteOn: false, currentInputVolume: 0, savedPrevious: 15)
        XCTAssertEqual(floored.targetVolume, 40)
    }

    func testVPNServiceParserParsesMultipleServices() {
        let sample = """
        Available network connection services in the current set (*=enabled):
        * (Connected)      11111111-2222-3333-4444-555555555555 PPP --> L2TP       "Corp VPN"                     [PPP:L2TP]
        * (Disconnected)   AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE IPSec              "Personal WireGuard"           [IPSec]
        """
        let entries = VPNServiceParser.parse(sample)
        XCTAssertEqual(entries, [
            VPNServiceParser.Entry(id: "11111111-2222-3333-4444-555555555555", name: "Corp VPN", connected: true),
            VPNServiceParser.Entry(id: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", name: "Personal WireGuard", connected: false)
        ])
    }
}
