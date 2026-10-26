import SwiftUI
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
        XCTAssertEqual(WidgetMotionPreset.allCases.count, 4)
        XCTAssertEqual(WidgetMotionPreset.default, .fluid)
        XCTAssertEqual(WidgetMotionPreset.allCases.map(\.title), ["Fluid", "Snappy", "Instant", "Slow"])
        XCTAssertEqual(WidgetMotionPreset.fluid.motion, .fluid)
        XCTAssertEqual(WidgetMotionPreset.snappy.motion, .snappy)
        XCTAssertEqual(WidgetMotionPreset.instant.motion, .instant)
        XCTAssertEqual(WidgetMotionPreset.slow.motion, .slow)
    }

    /// Slow is slow in both directions — it is the far end of Animation Speed, not a second Fluid.
    func testSlowIsSlowerAndSofterThanFluid() {
        let fluid = WidgetMotion.fluid, slow = WidgetMotion.slow
        XCTAssertGreaterThan(slow.hoverSpring!.response, fluid.hoverSpring!.response)
        XCTAssertLessThan(slow.hoverSpring!.dampingRatio, fluid.hoverSpring!.dampingRatio)
        XCTAssertGreaterThan(slow.contentSpring!.response, fluid.contentSpring!.response)
        XCTAssertGreaterThanOrEqual(slow.hoverScale, fluid.hoverScale)
        XCTAssertTrue(slow.morphsContent)
    }

    /// The Settings card's speed row is a scale, so it may not just be `allCases` in storage order.
    func testDockSpeedOrderRunsFastToSlow() {
        let order = [WidgetMotionPreset.instant, .snappy, .fluid, .slow]
        XCTAssertEqual(order, WidgetMotionPreset.allCases.sorted { lhs, rhs in
            (lhs.motion.hoverSpring?.response ?? 0) < (rhs.motion.hoverSpring?.response ?? 0)
        })
        XCTAssertEqual(Set(order), Set(WidgetMotionPreset.allCases))
    }

    // MARK: - Animation Delay presets

    /// Every preset is a stop on the auto-hide slider's 0.1 s grid inside its finite range, so
    /// selecting one writes the number the slider would have written.
    func testDelayPresetsAreOnTheStoresDelayGrid() {
        for preset in DockRevealDelayPreset.allCases {
            XCTAssertGreaterThanOrEqual(preset.seconds, 0.1)
            XCTAssertLessThanOrEqual(preset.seconds, 3.0)
            XCTAssertEqual(preset.seconds, (preset.seconds * 10).rounded() / 10, accuracy: 0.0001)
        }
    }

    func testDelayPresetsRunFromNoneToALot() {
        XCTAssertEqual(DockRevealDelayPreset.allCases.map(\.seconds),
                       DockRevealDelayPreset.allCases.map(\.seconds).sorted())
        XCTAssertEqual(Set(DockRevealDelayPreset.allCases.map(\.title)).count,
                       DockRevealDelayPreset.allCases.count)
    }

    /// The stored delay comes back as the nearest preset; `neverHideDelay` (-1, always visible) has
    /// no delay at all, and neither does a nonsense value.
    func testDelayMatchingPicksTheNearestPreset() {
        XCTAssertEqual(DockRevealDelayPreset.matching(0.3), .little)
        XCTAssertEqual(DockRevealDelayPreset.matching(0.31), .little)
        XCTAssertEqual(DockRevealDelayPreset.matching(1.2), .aLot)
        XCTAssertEqual(DockRevealDelayPreset.matching(2.5), .aLot)
        XCTAssertNil(DockRevealDelayPreset.matching(-1))  // the store's "never hide" sentinel
        XCTAssertNil(DockRevealDelayPreset.matching(.nan))
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

    /// Phase 32b: the bridge the widgets actually call. `Instant` — and therefore Reduce Motion — is
    /// the absence of motion at the call site, not only a `nil` in the table.
    func testInstantCutsTheContentAnimationTheWidgetsUse() {
        XCTAssertNotNil(WidgetMotion.fluid.contentAnimation)
        XCTAssertNotNil(WidgetMotion.snappy.contentAnimation)
        XCTAssertNil(WidgetMotion.instant.contentAnimation)
        XCTAssertEqual(SpringParameters(response: 0.34, dampingRatio: 0.80).animation,
                       Animation.spring(response: 0.34, dampingFraction: 0.80))
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
