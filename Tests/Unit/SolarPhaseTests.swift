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
