import XCTest
@testable import KatiKati

final class SideDeckConfigTests: XCTestCase {
    func testDefaultsMatchTheDeckAsItShips() {
        let config = SideDeckConfig.standard
        XCTAssertEqual(config.side, .left)
        XCTAssertEqual(config.width, 400)
        XCTAssertFalse(config.edgeActivation, "edge activation stays opt-in")
        XCTAssertEqual(config.dwell, 0.18, accuracy: 0.0001)
        XCTAssertFalse(config.identityStrip, "the identity strip is off by default")
        XCTAssertFalse(config.mergedWeatherHandle)
    }

    func testValuesClampToTheSupportedRanges() {
        XCTAssertEqual(SideDeckConfig(width: 100).width, 360)
        XCTAssertEqual(SideDeckConfig(width: 900).width, 560)
        XCTAssertEqual(SideDeckConfig(dwell: 0).dwell, 0.08, accuracy: 0.0001)
        XCTAssertEqual(SideDeckConfig(dwell: 5).dwell, 0.6, accuracy: 0.0001)
    }

    func testPanelSitsBelowTheMenuBarAndAboveTheDockOnEitherSide() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 900)
        let left = SideDeckConfig(side: .left).panelFrame(in: visible)
        XCTAssertEqual(left.minX, 8)
        XCTAssertEqual(left.minY, SideDeckConfig.bottomInset)
        XCTAssertEqual(left.height, visible.height - SideDeckConfig.topInset - SideDeckConfig.bottomInset)
        XCTAssertEqual(left.maxY, visible.maxY - SideDeckConfig.topInset, "the panel starts below the menu bar")

        let right = SideDeckConfig(side: .right).panelFrame(in: visible)
        XCTAssertEqual(right.maxX, visible.maxX - 8)
        XCTAssertEqual(right.width, 400)
        XCTAssertEqual(SideDeckConfig(side: .left).side.toggled, .right)
    }

    func testNarrowDisplayNeverLetsThePanelEscape() {
        let visible = CGRect(x: 0, y: 0, width: 600, height: 400)
        let frame = SideDeckConfig(width: 560).panelFrame(in: visible)
        XCTAssertGreaterThanOrEqual(frame.minX, visible.minX)
        XCTAssertLessThanOrEqual(frame.maxX, visible.maxX)
    }

    func testBentoColumnsFollowTheContentWidthBreakpoints() {
        XCTAssertEqual(SideDeckConfig.columns(forContentWidth: 1_200), 3)
        XCTAssertEqual(SideDeckConfig.columns(forContentWidth: 900), 3)
        XCTAssertEqual(SideDeckConfig.columns(forContentWidth: 899), 2)
        XCTAssertEqual(SideDeckConfig.columns(forContentWidth: 620), 2)
        XCTAssertEqual(SideDeckConfig.columns(forContentWidth: 619), 1)
    }

    func testReduceMotionDropsTheScaleButNotTheFade() {
        XCTAssertEqual(SideDeckConfig.entryScale(reduceMotion: false), 0.98)
        XCTAssertEqual(SideDeckConfig.entryScale(reduceMotion: true), 1)
    }

    func testLegacyEdgeHoverMigratesOnceBehindAStamp() {
        let suite = "SideDeckConfigMigrationTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: "com.katikati.drawer.edgeHover")

        let migrated = SideDeckConfig.migrating(from: defaults)
        XCTAssertTrue(migrated.edgeActivation)
        XCTAssertTrue(defaults.bool(forKey: SideDeckConfig.migrationKey))

        // Stamped: a choice made after the migration is never overwritten by the legacy key.
        defaults.set(false, forKey: SideDeckConfig.defaultsKey + ".edgeActivation")
        XCTAssertFalse(SideDeckConfig.migrating(from: defaults).edgeActivation)
    }

    func testRoundTripThroughDefaults() {
        let suite = "SideDeckConfigRoundTripTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let config = SideDeckConfig(side: .right, width: 480, edgeActivation: true, dwell: 0.3,
                                    identityStrip: true, mergedWeatherHandle: true)
        config.write(to: defaults)
        XCTAssertEqual(SideDeckConfig.stored(in: defaults), config)
    }

    /// SD-8: the shared swap exchanges both edges at once, and is its own inverse.
    func testTheSharedSwapExchangesBothEdges() {
        let shipped = SideDeckEdgeSwap.Sides(deck: .left, edgeBar: .right)
        let swapped = SideDeckEdgeSwap.exchange(shipped)
        XCTAssertEqual(swapped.deck, .right)
        XCTAssertEqual(swapped.edgeBar, .left)
        XCTAssertEqual(SideDeckEdgeSwap.exchange(swapped), shipped, "applying the swap twice is the identity")

        let bothRight = SideDeckEdgeSwap.Sides(deck: .right, edgeBar: .right)
        XCTAssertEqual(SideDeckEdgeSwap.exchange(bothRight), bothRight,
                       "two surfaces already on one edge cannot exchange anything")
    }
}
