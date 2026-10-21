import XCTest
@testable import KatiKati

final class SkyTintTests: XCTestCase {
    private func valid(_ c: TileRGB) -> Bool { [c.r, c.g, c.b].allSatisfy { (0...1).contains($0) } }

    func testEveryConditionAndNightHasValidColoursAndThreeRidges() {
        for cond in WeatherCondition.allCases {
            for night in [false, true] {
                let t = SkyTint.tint(condition: cond, isNight: night)
                XCTAssertTrue(valid(t.top) && valid(t.bottom), "\(cond) night=\(night)")
                XCTAssertEqual(t.ridges.count, 3)
                XCTAssertTrue(t.ridges.allSatisfy(valid))
                XCTAssertNotEqual(t.top, t.bottom)
            }
        }
    }

    func testMixEndpointsAndClamping() {
        let t = SkyTint.tint(condition: .clear, isNight: false)
        XCTAssertEqual(t.mix(0), t.top); XCTAssertEqual(t.mix(1), t.bottom)
        XCTAssertEqual(t.mix(-3), t.top); XCTAssertEqual(t.mix(9), t.bottom)
        let mid = t.mix(0.5)
        XCTAssertEqual(mid.r, (t.top.r + t.bottom.r) / 2, accuracy: 1e-9)
    }

    func testNightIsDarkerThanDayForEveryCondition() {
        for cond in WeatherCondition.allCases {
            XCTAssertLessThan(SkyTint.tint(condition: cond, isNight: true).luminance, SkyTint.tint(condition: cond, isNight: false).luminance, "\(cond)")
        }
    }

    func testTextContrastFollowsBrightness() {
        XCTAssertTrue(SkyTint.tint(condition: .snow, isNight: false).prefersDarkText)
        XCTAssertTrue(SkyTint.tint(condition: .fog, isNight: false).prefersDarkText)
        for night in [true] { for cond in WeatherCondition.allCases { XCTAssertFalse(SkyTint.tint(condition: cond, isNight: night).prefersDarkText, "\(cond) night") } }
        XCTAssertFalse(SkyTint.tint(condition: .thunderstorm, isNight: false).prefersDarkText)
        XCTAssertFalse(SkyTint.tint(condition: .rain, isNight: false).prefersDarkText)
    }

    func testRidgeIsDeterministicBoundedAndPeaksNearTheMainPeak() {
        for layer in 0..<3 {
            for i in 0...100 {
                let y = SceneGeometry.ridge(x: Double(i) / 100, layer: layer)
                XCTAssertTrue((0.05...1).contains(y))
                XCTAssertEqual(y, SceneGeometry.ridge(x: Double(i) / 100, layer: layer))
            }
        }
        XCTAssertGreaterThan(SceneGeometry.ridge(x: 0.5, layer: 2), SceneGeometry.ridge(x: 0.05, layer: 2) + 0.2)
    }

    func testPresetEnumsKeepBothDesigns() {
        XCTAssertEqual(WeatherHeroStyle.allCases, [.scene, .classic])
        XCTAssertEqual(WeatherLayoutPreset.allCases, [.glance, .fullScreen, .classic])
        XCTAssertEqual(WeatherHeroStyle.storageKey, "com.katikati.weather.heroStyle")
    }
}
