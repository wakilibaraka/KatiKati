import XCTest

/// Phase 32a: the dock widgets' motion language is data, so it is tested as data — the numbers the
/// widgets and the tile chrome actually move with, the stored choice, and Reduce Motion's precedence.
final class WidgetMotionSpecTests: XCTestCase {

    /// The default is not "some spring": it is the one the dock already moved with. `DockTileChrome`'s
    /// hover was hardcoded to 0.28/0.75 at 1.04 before this table existed, so `fluid` pinning those
    /// numbers is what keeps a preset from silently re-timing every tile in the bar.
    func testFluidMatchesTheMotionTheDockAlreadyHad() {
        XCTAssertEqual(WidgetMotion.fluid.hoverSpring, SpringParameters(response: 0.28, dampingRatio: 0.75))
        XCTAssertEqual(WidgetMotion.fluid.hoverScale, 1.04, accuracy: 0.0001)
        XCTAssertEqual(WidgetMotion.fluid.contentSpring, SpringParameters(response: 0.34, dampingRatio: 0.80))
        XCTAssertTrue(WidgetMotion.fluid.morphsContent)
    }

    /// Snappy is a real spring, just faster and firmer — never a longer one.
    func testSnappyIsFasterAndFirmerThanFluid() {
        let fluid = WidgetMotion.fluid, snappy = WidgetMotion.snappy
        XCTAssertLessThan(snappy.hoverSpring!.response, fluid.hoverSpring!.response)
        XCTAssertGreaterThan(snappy.hoverSpring!.dampingRatio, fluid.hoverSpring!.dampingRatio)
        XCTAssertLessThan(snappy.contentSpring!.response, fluid.contentSpring!.response)
        XCTAssertLessThanOrEqual(snappy.hoverScale, fluid.hoverScale)
        XCTAssertTrue(snappy.morphsContent)
    }

    /// Instant is the absence of motion, on both axes — the state Reduce Motion has to produce.
    func testInstantHasNoMotionAtAll() {
        XCTAssertNil(WidgetMotion.instant.contentSpring)
        XCTAssertNil(WidgetMotion.instant.hoverSpring)
        XCTAssertEqual(WidgetMotion.instant.hoverScale, 1.0, accuracy: 0.0001)
        XCTAssertFalse(WidgetMotion.instant.morphsContent)
    }

    func testEveryPresetHasItsOwnMotionAndATitle() {
        XCTAssertEqual(WidgetMotionPreset.allCases.count, 3)
        XCTAssertEqual(WidgetMotionPreset.default, .fluid)
        XCTAssertEqual(WidgetMotionPreset.allCases.map(\.title), ["Fluid", "Snappy", "Instant"])
        XCTAssertEqual(WidgetMotionPreset.fluid.motion, .fluid)
        XCTAssertEqual(WidgetMotionPreset.snappy.motion, .snappy)
        XCTAssertEqual(WidgetMotionPreset.instant.motion, .instant)
    }

    /// The key is a contract with the stored preference, the Settings row and any menu that offers the
    /// presets, so it is pinned here rather than typed three times.
    func testStorageKey() {
        XCTAssertEqual(WidgetMotionPreset.storageKey, "com.katikati.widgets.dockMotion")
    }

    func testResolveFallsBackToFluidForUnsetAndUnknownValues() {
        let suite = UserDefaults(suiteName: "WidgetMotionSpecTests")!
        suite.removeObject(forKey: WidgetMotionPreset.storageKey)
        XCTAssertEqual(WidgetMotionPreset.resolve(defaults: suite, reduceMotion: false), .fluid)

        suite.set("hexagon", forKey: WidgetMotionPreset.storageKey)
        XCTAssertEqual(WidgetMotionPreset.resolve(defaults: suite, reduceMotion: false), .fluid)

        suite.set(WidgetMotionPreset.snappy.rawValue, forKey: WidgetMotionPreset.storageKey)
        XCTAssertEqual(WidgetMotionPreset.resolve(defaults: suite, reduceMotion: false), .snappy)

        suite.removeObject(forKey: WidgetMotionPreset.storageKey)
    }

    /// Reduce Motion always wins — the same rule the notch's animation preset follows.
    func testReduceMotionOverridesEveryPreset() {
        for preset in WidgetMotionPreset.allCases {
            XCTAssertEqual(preset.effective(reduceMotion: true), .instant, "\(preset) ignores Reduce Motion")
        }
        let suite = UserDefaults(suiteName: "WidgetMotionSpecTests")!
        suite.set(WidgetMotionPreset.snappy.rawValue, forKey: WidgetMotionPreset.storageKey)
        XCTAssertEqual(WidgetMotionPreset.resolve(defaults: suite, reduceMotion: true), .instant)
        suite.removeObject(forKey: WidgetMotionPreset.storageKey)
    }
}
