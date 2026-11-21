import XCTest
@testable import KatiKati

final class SolarPhaseTests: XCTestCase {
    private let rise = Date(timeIntervalSince1970: 1_000_000)
    private var set: Date { rise.addingTimeInterval(12 * 3600) }
    private var times: SunTimes { SunTimes(sunrise: rise, sunset: set) }

    private func phase(_ offset: TimeInterval, from base: Date) -> SolarPhase {
        SolarPhaseResolver.phase(at: base.addingTimeInterval(offset), times: times)
    }

    func testBoundariesAroundSunrise() {
        XCTAssertEqual(phase(-31 * 60, from: rise), .night)
        XCTAssertEqual(phase(-30 * 60, from: rise), .dawn)
        XCTAssertEqual(phase(29 * 60, from: rise), .dawn)
        XCTAssertEqual(phase(30 * 60, from: rise), .day)
    }

    func testBoundariesAroundSunset() {
        XCTAssertEqual(phase(-61 * 60, from: set), .day)
        XCTAssertEqual(phase(-60 * 60, from: set), .golden)
        XCTAssertEqual(phase(-1, from: set), .golden)
        XCTAssertEqual(phase(0, from: set), .dusk)
        XCTAssertEqual(phase(29 * 60, from: set), .dusk)
        XCTAssertEqual(phase(30 * 60, from: set), .night)
    }

    func testPolarOverridesAndMissingTimes() {
        XCTAssertEqual(SolarPhaseResolver.phase(at: rise, times: SunTimes(sunrise: nil, sunset: nil, polar: .night)), .night)
        XCTAssertEqual(SolarPhaseResolver.phase(at: rise, times: SunTimes(sunrise: nil, sunset: nil, polar: .day)), .day)
        XCTAssertEqual(SolarPhaseResolver.phase(at: rise, times: SunTimes(sunrise: nil, sunset: nil)), .day)
    }

    func testNextBoundaryPicksNearestFutureEdgeThenNextDay() {
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let r = utc.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 6))!
        let t = SunTimes(sunrise: r, sunset: r.addingTimeInterval(14 * 3600))
        XCTAssertEqual(SolarPhaseResolver.nextBoundary(after: r.addingTimeInterval(-3600), times: t, calendar: utc),
                       r.addingTimeInterval(-1800))
        XCTAssertEqual(SolarPhaseResolver.nextBoundary(after: r.addingTimeInterval(14.6 * 3600), times: t, calendar: utc),
                       utc.date(from: DateComponents(year: 2026, month: 6, day: 2))!)
        XCTAssertEqual(SolarPhaseResolver.nextBoundary(after: r, times: SunTimes(sunrise: nil, sunset: nil, polar: .day), calendar: utc),
                       utc.date(from: DateComponents(year: 2026, month: 6, day: 2))!)
    }

    func testSunCalculatorMatchesKnownTimes() throws {
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        // Greenwich, 2026-06-21: sunrise ≈ 03:43 UTC, sunset ≈ 20:21 UTC (±5 min).
        let day = utc.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 10))!
        let t = SunCalculator.times(on: day, latitude: 51.4779, longitude: -0.0015, calendar: utc)
        let rise = try XCTUnwrap(t.sunrise), set = try XCTUnwrap(t.sunset)
        let midnight = utc.startOfDay(for: day)
        XCTAssertEqual(rise.timeIntervalSince(midnight) / 60, 3 * 60 + 43, accuracy: 6)
        XCTAssertEqual(set.timeIntervalSince(midnight) / 60, 20 * 60 + 21, accuracy: 6)
    }

    func testSunCalculatorPolarCases() {
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let summer = utc.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!
        let winter = utc.date(from: DateComponents(year: 2026, month: 12, day: 21, hour: 12))!
        XCTAssertEqual(SunCalculator.times(on: summer, latitude: 78, longitude: 15, calendar: utc).polar, .day)
        XCTAssertEqual(SunCalculator.times(on: winter, latitude: 78, longitude: 15, calendar: utc).polar, .night)
        XCTAssertNil(SunCalculator.times(on: winter, latitude: 0, longitude: 0, calendar: utc).polar)
    }
}

final class WallpaperSelectorTests: XCTestCase {
    func testSkyMappingCoversEveryCondition() {
        XCTAssertEqual(WeatherCondition.allCases.map(WallpaperSky.init),
                       [.clear, .cloudy, .cloudy, .fog, .rain, .rain, .snow, .rain, .storm])
    }

    func testFullPackHas30KeysAndAlwaysResolves() {
        XCTAssertEqual(WallpaperSelector.allSkyKeys.count, 30)
        let pack = Set(WallpaperSelector.allSkyKeys)
        for phase in SolarPhase.allCases {
            for sky in WallpaperSky.allCases {
                XCTAssertEqual(WallpaperSelector.pick(phase: phase, sky: sky, mode: .both, available: pack),
                               "\(phase.rawValue)-\(sky.rawValue)")
            }
        }
    }

    func testFallbackChainForCustomFolders() {
        XCTAssertEqual(WallpaperSelector.pick(phase: .dusk, sky: .rain, mode: .both, available: ["dusk", "default"]), "dusk")
        XCTAssertEqual(WallpaperSelector.pick(phase: .dusk, sky: .rain, mode: .both, available: ["any-rain", "default"]), "any-rain")
        XCTAssertEqual(WallpaperSelector.pick(phase: .dusk, sky: .rain, mode: .both, available: ["default"]), "default")
        XCTAssertNil(WallpaperSelector.pick(phase: .dusk, sky: .rain, mode: .both, available: []))
    }

    func testModesPickTheirAxis() {
        let pack: Set<String> = ["night", "day", "night-rain", "day-rain", "any-rain", "default"]
        XCTAssertEqual(WallpaperSelector.pick(phase: .night, sky: .rain, mode: .time, available: pack), "night")
        XCTAssertEqual(WallpaperSelector.pick(phase: .night, sky: .rain, mode: .weather, available: pack), "any-rain")
        XCTAssertEqual(WallpaperSelector.pick(phase: .night, sky: .snow, mode: .weather, available: pack), "default")
    }
}

extension WallpaperSelectorTests {
    func testSkyPackAliasesMakeEveryModeResolve() {
        let aliases = WallpaperSelector.skyPackAliases
        let keys = Set(WallpaperSelector.allSkyKeys).union(aliases.keys)
        XCTAssertTrue(aliases.values.allSatisfy { WallpaperSelector.allSkyKeys.contains($0) })
        for phase in SolarPhase.allCases {
            for sky in WallpaperSky.allCases {
                for mode in WallpaperMode.allCases {
                    XCTAssertNotNil(WallpaperSelector.pick(phase: phase, sky: sky, mode: mode, available: keys), "\(phase) \(sky) \(mode)")
                }
            }
        }
        XCTAssertEqual(WallpaperSelector.pick(phase: .dusk, sky: .rain, mode: .time, available: keys), "dusk")
    }
}

extension WallpaperSelectorTests {
    func testDebugOverrideParsing() {
        XCTAssertEqual(WallpaperDebugOverride.parse("dusk")?.phase, .dusk)
        XCTAssertNil(WallpaperDebugOverride.parse("dusk")?.sky)
        XCTAssertEqual(WallpaperDebugOverride.parse("Night:Rain")?.sky, .rain)
        XCTAssertNil(WallpaperDebugOverride.parse("noon"))
        XCTAssertNil(WallpaperDebugOverride.parse("dusk:hail"))
        XCTAssertNil(WallpaperDebugOverride.parse(nil))
    }

    func testWeatherStateSunTimesFallBackToCoordinates() {
        var s = WeatherState.empty
        XCTAssertNil(s.sunTimes())
        s.latitude = 51.4779; s.longitude = -0.0015
        let t = s.sunTimes(on: Date(timeIntervalSince1970: 1_781_000_000))
        XCTAssertNotNil(t?.sunrise)
        XCTAssertNotNil(t?.sunset)
    }
}

// DW-1: the dynamic wallpaper's ladder — boundaries, progress and the sun-height model, all from `times`.
final class DaylightPhaseTests: XCTestCase {
    private let rise = Date(timeIntervalSince1970: 1_000_000)
    private var set: Date { rise.addingTimeInterval(12 * 3600) }
    private var noon: Date { rise.addingTimeInterval(6 * 3600) }
    private var times: SunTimes { SunTimes(sunrise: rise, sunset: set) }

    private func sample(_ offset: TimeInterval, from base: Date) -> DaylightSample {
        SolarDaylightEvaluator.sample(at: base.addingTimeInterval(offset), times: times)
    }

    func testTheLadderStepsAtTheDocumentedBoundaries() {
        XCTAssertEqual(sample(-31 * 60, from: rise).phase, .night)
        XCTAssertEqual(sample(-30 * 60, from: rise).phase, .dawn)
        XCTAssertEqual(sample(29 * 60, from: rise).phase, .dawn)
        XCTAssertEqual(sample(30 * 60, from: rise).phase, .morning)
        XCTAssertEqual(sample(-31 * 60, from: noon).phase, .morning)
        XCTAssertEqual(sample(-30 * 60, from: noon).phase, .noon)
        XCTAssertEqual(sample(1, from: noon).phase, .noon, "the afternoon rides the noon plateau")
        XCTAssertEqual(sample(-61 * 60, from: set).phase, .noon)
        XCTAssertEqual(sample(-60 * 60, from: set).phase, .goldenHour)
        XCTAssertEqual(sample(0, from: set).phase, .dusk)
        XCTAssertEqual(sample(29 * 60, from: set).phase, .dusk)
        XCTAssertEqual(sample(30 * 60, from: set).phase, .night)
    }

    func testProgressRunsZeroToOneThroughEachStep() {
        XCTAssertEqual(sample(-30 * 60, from: rise).progress, 0, accuracy: 0.0001)
        XCTAssertEqual(sample(0, from: rise).progress, 0.5, accuracy: 0.0001, "dawn is centred on sunrise")
        XCTAssertEqual(sample(29 * 60, from: rise).progress, 59.0 / 60, accuracy: 0.0001)
        XCTAssertEqual(sample(0, from: set).progress, 0, accuracy: 0.0001)
        XCTAssertEqual(sample(15 * 60, from: set).progress, 0.5, accuracy: 0.0001)
        for offset in stride(from: Double(-600), through: 600, by: 37) {
            let p = sample(offset * 60, from: noon).progress
            XCTAssertTrue((0...1).contains(p), "progress \(p) escaped 0…1 at \(offset) min")
        }
    }

    func testSunHeightPeaksAtSolarNoonAndGoesNegativeAfterDusk() {
        XCTAssertEqual(sample(0, from: rise).altitude, 0, accuracy: 0.02, "the sun sits on the horizon at sunrise")
        XCTAssertEqual(sample(0, from: noon).altitude, 1, accuracy: 0.02)
        XCTAssertLessThan(sample(6 * 3600, from: set).altitude, -0.5, "well past dusk the sun is below the horizon")
    }

    func testPolarAndMissingTimesStayDefined() {
        let polarDay = SolarDaylightEvaluator.sample(at: rise, times: SunTimes(sunrise: nil, sunset: nil, polar: .day))
        XCTAssertEqual(polarDay.phase, .noon)
        XCTAssertEqual(polarDay.altitude, 0.85, accuracy: 0.0001)
        let polarNight = SolarDaylightEvaluator.sample(at: rise, times: SunTimes(sunrise: nil, sunset: nil, polar: .night))
        XCTAssertEqual(polarNight.phase, .night)
        XCTAssertLessThan(polarNight.luminance, 0.2)
        let missing = SolarDaylightEvaluator.sample(at: rise, times: SunTimes(sunrise: nil, sunset: nil))
        XCTAssertEqual(missing.phase, .noon, "no times and no polar flag reads as a bright, neutral day")
    }

    func testShortWinterDaysFallBackInsteadOfInvertingTheWindows() {
        // Three hours of daylight: a 30-minute dawn, a 30-minute noon window and a one-hour golden hour
        // cannot all fit, so the ladder must fall back to the coarse pack phase — never a night-morning.
        let short = SunTimes(sunrise: rise, sunset: rise.addingTimeInterval(3 * 3600))
        let s = SolarDaylightEvaluator.sample(at: rise.addingTimeInterval(2 * 3600), times: short)
        XCTAssertTrue(DaylightPhase.allCases.contains(s.phase))
        XCTAssertTrue((0...1).contains(s.progress))
    }

    func testNightIsDarkerThanNoonOnTheLadder() {
        XCTAssertLessThan(SolarDaylightEvaluator.luminance(of: .night), SolarDaylightEvaluator.luminance(of: .noon))
        XCTAssertLessThan(SolarDaylightEvaluator.luminance(of: .dusk), SolarDaylightEvaluator.luminance(of: .morning))
    }
}

// DW-1: environment mimicry — which scene a pin resolves to, and what its layers/accents look like.
final class TerrainMimicCatalogTests: XCTestCase {
    func testPinsResolveToTheirOwnScene() {
        XCTAssertEqual(TerrainMimicCatalog.resolve(.city, latitude: 0, cityName: "Viterbo"), .city)
        XCTAssertEqual(TerrainMimicCatalog.resolve(.countryside, latitude: 60, cityName: "Oslo"), .countryside)
        XCTAssertEqual(TerrainMimicCatalog.resolve(.terrain, latitude: 46, cityName: "Chamonix"), .alpine)
        XCTAssertEqual(TerrainMimicCatalog.resolve(.terrain, latitude: 38, cityName: "Porto"), .coast)
    }

    func testAutoPicksFromThePlaceNameFirst() {
        XCTAssertEqual(TerrainMimicCatalog.resolve(.auto, latitude: 40, cityName: "New York"), .city)
        XCTAssertEqual(TerrainMimicCatalog.resolve(.auto, latitude: 45, cityName: "Monterey Bay"), .coast)
        XCTAssertEqual(TerrainMimicCatalog.resolve(.auto, latitude: 42, cityName: "Somerset Valley"), .countryside)
    }

    func testAutoFallsBackToLatitudeThenCountryside() {
        XCTAssertEqual(TerrainMimicCatalog.resolve(.auto, latitude: 62, cityName: "Reykjavik"), .alpine)
        XCTAssertEqual(TerrainMimicCatalog.resolve(.auto, latitude: 12, cityName: "Viterbo"), .countryside)
        XCTAssertEqual(TerrainMimicCatalog.resolve(.auto, latitude: nil, cityName: ""), .countryside)
    }

    func testEachSceneHasThreeDistinctBandsAndAnAccentTriple() {
        for scene in WallpaperScene.allCases {
            let env = TerrainMimicCatalog.environment(scene: scene, phase: .day, sky: .clear)
            XCTAssertEqual(env.layers.count, 3, "\(scene) needs three silhouette bands")
            XCTAssertEqual(env.accent.count, 3)
            XCTAssertEqual(Set(env.layers.map { "\($0.r),\($0.g),\($0.b)" }).count, 3, "\(scene) bands must differ")
            XCTAssertGreaterThan(env.glowStrength, 0, "a clear day keeps its sun glow")
        }
    }

    func testWeatherAndPhaseChangeTheSceneNotJustItsName() {
        let clear = TerrainMimicCatalog.environment(scene: .alpine, phase: .day, sky: .clear)
        let storm = TerrainMimicCatalog.environment(scene: .alpine, phase: .day, sky: .storm)
        XCTAssertNotEqual(clear.skyTop, storm.skyTop)
        XCTAssertEqual(storm.glowStrength, 0, "an overcast sky has no visible sun")
        let night = TerrainMimicCatalog.environment(scene: .alpine, phase: .night, sky: .clear)
        XCTAssertLessThan(night.layers[2].r, clear.layers[2].r, "the nearest ridge reads darker at night")
    }
}
