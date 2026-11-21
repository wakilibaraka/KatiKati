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

// DW-6: the weather mood — Auto follows the forecast, an override ignores it and survives the next update.
final class WallpaperMoodTests: XCTestCase {
    func testAutoPassesTheLiveWeatherAndClockThrough() {
        for weather in WallpaperSky.allCases {
            for phase in SolarPhase.allCases {
                let resolved = WallpaperMood.auto.resolve(weather: weather, phase: phase)
                XCTAssertEqual(resolved.sky, weather)
                XCTAssertEqual(resolved.phase, phase)
            }
        }
        XCTAssertNil(WallpaperMood.auto.lockedSky)
        XCTAssertNil(WallpaperMood.auto.lockedSolarPhase)
    }

    func testEachOverrideLocksBothItsSkyAndItsPhase() {
        let expected: [WallpaperMood: (WallpaperSky, SolarPhase)] = [
            .rainyEvening: (.rain, .golden),
            .goldenEvening: (.clear, .golden),
            .snowyDay: (.snow, .day),
            .stormNight: (.storm, .night),
            .clearNight: (.clear, .night)
        ]
        for (mood, pair) in expected {
            XCTAssertEqual(mood.lockedSky, pair.0, "\(mood.rawValue) sky")
            XCTAssertEqual(mood.lockedSolarPhase, pair.1, "\(mood.rawValue) phase")
            // The override must survive every possible forecast, not just the one that was live when it was picked.
            for weather in WallpaperSky.allCases {
                for phase in SolarPhase.allCases {
                    let resolved = mood.resolve(weather: weather, phase: phase)
                    XCTAssertEqual(resolved.sky, pair.0)
                    XCTAssertEqual(resolved.phase, pair.1)
                }
            }
        }
        XCTAssertEqual(WallpaperMood.allCases.count, expected.count + 1, "only Auto is not an override")
    }

    func testMoodRawValuesStayStableForPersistence() {
        // The value is stored in `com.katikati.wallpaper.mood`; a rename would silently reset a user's lock to Auto.
        XCTAssertEqual(WallpaperMood.allCases.map(\.rawValue),
                       ["auto", "rainyEvening", "goldenEvening", "snowyDay", "stormNight", "clearNight"])
        let data = try? JSONEncoder().encode(WallpaperMood.rainyEvening)
        XCTAssertEqual(data.flatMap { try? JSONDecoder().decode(WallpaperMood.self, from: $0) }, .rainyEvening)
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

// MARK: - DW-7 · generated frames live in their own cache, and pruning only touches KatiKati's own renders

final class WallpaperCacheTests: XCTestCase {
    private var base: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        base = fileManager.temporaryDirectory
            .appendingPathComponent("WallpaperCacheTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: base)
    }

    private func write(_ name: String, in directory: URL, age: TimeInterval = 0) throws -> URL {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data("frame".utf8).write(to: url)
        if age != 0 {
            try fileManager.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
        }
        return url
    }

    private func own(_ scene: String = "countryside", _ phase: String = "night", _ sky: String = "clear",
                     size: String = "3420x2224", digest: String = "d600c2af", generation: Int? = nil) -> String {
        "terrain-\(scene)-\(phase)-\(sky)-\(size)-\(digest)" + (generation.map { "-g\($0)" } ?? "") + ".png"
    }

    func testGeneratedFramesLiveInTheirOwnCache() {
        let generated = WallpaperCache.generatedDirectory(in: base)
        XCTAssertTrue(generated.path.hasSuffix("/KatiKati/DynamicWallpapers/Generated"), generated.path)
        XCTAssertNotEqual(generated, WallpaperCache.legacyDirectory(in: base))
        XCTAssertNotEqual(generated, WallpaperCache.skyPackDirectory(in: base))
        XCTAssertTrue(WallpaperCache.skyPackDirectory(in: base).path.hasSuffix("/KatiKati/Wallpapers/sky"))
        XCTAssertTrue(WallpaperCache.legacyDirectory(in: base).path.hasSuffix("/KatiKati/Wallpapers/terrain"))
    }

    func testOnlyTheRenderersOwnNamesCount() {
        for name in [own(), own(generation: 3),
                     own("alpine", "golden", "rain", size: "5120x2880", digest: "0f3a91")] {
            XCTAssertTrue(WallpaperCache.isOwnRender(named: name), name)
        }
        for name in ["default.heic", "dusk-rain.png", "terrain-note.txt",
                     "terrain-countryside-night-clear-3420x2224.png",
                     "terrain-countryside-night-clear-3420x2224-d600c2af.jpg",
                     "terrain-Countryside-night-clear-3420x2224-d600c2af.png",
                     "terrain-countryside-night-clear-3420-2224-d600c2af.png",
                     "terrain-countryside-night-clear-3420x2224-d600c2af-gX.png",
                     "terrain-countryside-night-clear-3420x2224-d600c2af-g.png"] {
            XCTAssertFalse(WallpaperCache.isOwnRender(named: name), name)
        }
    }

    func testGenerationCopiesShareOneBaseName() {
        XCTAssertEqual(WallpaperCache.baseName(of: own(generation: 7)), WallpaperCache.baseName(of: own()))
        XCTAssertEqual(WallpaperCache.baseName(of: own(generation: 7)), own().replacingOccurrences(of: ".png", with: ""))
        XCTAssertNil(WallpaperCache.baseName(of: "default.heic"))
    }

    func testPruneDeletesOnlyOurOwnStaleFrames() throws {
        let directory = WallpaperCache.generatedDirectory(in: base)
        let stale = try write(own("city", "dusk", "rain"), in: directory, age: 20 * 86_400)
        let fresh = try write(own(), in: directory)
        let foreign = [try write("default.heic", in: directory),
                       try write("dusk-rain.png", in: directory),
                       try write("terrain-note.txt", in: directory),
                       try write("holiday.png", in: directory)]
        let removed = WallpaperCache.prune(in: directory)
        XCTAssertEqual(Set(removed.map(\.lastPathComponent)), Set([stale.lastPathComponent]))
        for url in [fresh] + foreign {
            XCTAssertTrue(fileManager.fileExists(atPath: url.path), url.lastPathComponent)
        }
    }

    func testPruneKeepsTheTwoNewestGenerationsPerPicture() throws {
        let directory = WallpaperCache.generatedDirectory(in: base)
        let original = try write(own(), in: directory, age: 300)
        let first = try write(own(generation: 1), in: directory, age: 200)
        let second = try write(own(generation: 2), in: directory, age: 100)
        let third = try write(own(generation: 3), in: directory, age: 50)
        XCTAssertEqual(WallpaperCache.prune(in: directory).count, 2)
        XCTAssertFalse(fileManager.fileExists(atPath: original.path))
        XCTAssertFalse(fileManager.fileExists(atPath: first.path))
        XCTAssertTrue(fileManager.fileExists(atPath: second.path))
        XCTAssertTrue(fileManager.fileExists(atPath: third.path))
    }

    func testLegacyCleanupNeverTouchesTheSkyPackOrForeignFiles() throws {
        let legacy = WallpaperCache.legacyDirectory(in: base)
        let leftover = try write(own(generation: 2), in: legacy)
        let note = try write("terrain-note.txt", in: legacy)
        let sky = try write("dusk-rain.png", in: WallpaperCache.skyPackDirectory(in: base))
        let removed = WallpaperCache.removeLegacyRenders(in: legacy)
        XCTAssertEqual(Set(removed.map(\.lastPathComponent)), Set([leftover.lastPathComponent]))
        XCTAssertTrue(fileManager.fileExists(atPath: note.path))
        XCTAssertTrue(fileManager.fileExists(atPath: sky.path))
    }

    func testLegacyCleanupAlsoRetiresTheOlderRenderNames() throws {
        let legacy = WallpaperCache.legacyDirectory(in: base)
        let older = try write("night-clear-3420x2224-d600c2af.png", in: legacy)
        let olderGeneration = try write("night-clear-3420x2224-d600c2af-g2.png", in: legacy)
        let foreign = try write("holiday-2026-3420x2224-d600c2af.png", in: legacy)
        XCTAssertTrue(WallpaperCache.isLegacyRender(named: "night-clear-3420x2224-d600c2af.png"))
        XCTAssertFalse(WallpaperCache.isLegacyRender(named: "dusk-rain.png"))
        XCTAssertFalse(WallpaperCache.isLegacyRender(named: "holiday-2026-3420x2224-d600c2af.png"))
        let removed = WallpaperCache.removeLegacyRenders(in: legacy)
        XCTAssertEqual(Set(removed.map(\.lastPathComponent)),
                       Set([older.lastPathComponent, olderGeneration.lastPathComponent]))
        XCTAssertTrue(fileManager.fileExists(atPath: foreign.path))
    }

    func testPruningTheGeneratedCacheLeavesTheSkyPackAlone() throws {
        let sky = try write("dawn-rain.png", in: WallpaperCache.skyPackDirectory(in: base))
        _ = try write(own(), in: WallpaperCache.generatedDirectory(in: base))
        WallpaperCache.prune(in: WallpaperCache.generatedDirectory(in: base))
        XCTAssertTrue(fileManager.fileExists(atPath: sky.path))
    }

    func testMissingFoldersAreNotAnError() {
        XCTAssertEqual(WallpaperCache.prune(in: base.appendingPathComponent("missing")), [])
        XCTAssertEqual(WallpaperCache.removeLegacyRenders(in: base.appendingPathComponent("missing")), [])
    }
}

final class CelestialModelTests: XCTestCase {
    /// Fixed UTC instants, written the way the plan states them: every case here is time-zone-free by construction.
    private let at: (String) -> Date = { ISO8601DateFormatter().date(from: $0 + "Z")! }
    private func sky(_ date: Date) -> CelestialPosition { SolarPosition.at(date, latitude: 51.5, longitude: 0) }
    private func circularDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 1)
        return min(d, 1 - d)
    }

    func testSunAtSummerSolsticeNoonInGreenwich() {
        // 2024-06-20, sunset-side solstice: noon altitude 61.96°, azimuth 179.2° (≈ due south).
        let sun = SolarPosition.at(at("2024-06-20T12:00:00"), latitude: 51.4779, longitude: -0.0015)
        XCTAssertEqual(sun.altitude, 61.96, accuracy: 1)
        XCTAssertEqual(sun.azimuth, 179.2, accuracy: 4)
    }

    func testSunAtEquinoxNoonOnTheEquator() {
        XCTAssertEqual(SolarPosition.at(at("2024-03-20T12:07:00"), latitude: 0, longitude: 0).altitude, 89.8, accuracy: 1.5)
    }

    func testSunAtMidnightIsBelowTheHorizon() {
        let sun = sky(at("2024-06-20T00:00:00"))
        XCTAssertLessThan(sun.altitude, -10, "the sun must be well below the horizon at midnight")
        XCTAssertLessThan(min(sun.azimuth, 360 - sun.azimuth), 10, "and roughly due north (359.6°)")
    }

    func testSunOverThePolesHasNoDailyCycle() {
        let midnightSun = SolarPosition.at(at("2024-06-21T00:00:00"), latitude: 78.2, longitude: 15.6)
        let polarNight = SolarPosition.at(at("2024-12-21T12:00:00"), latitude: 78.2, longitude: 15.6)
        XCTAssertGreaterThan(midnightSun.altitude, 0)
        XCTAssertLessThan(polarNight.altitude, 0)
    }

    func testTheSameInstantIsTheSameSkyAcrossADSTBoundary() {
        // 2024-03-31 02:30 Europe/London is the first 02:30 of BST, i.e. 01:30Z: the position must not care.
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        let viaLondon = london.date(from: DateComponents(year: 2024, month: 3, day: 31, hour: 2, minute: 30))!
        let inUTC = at("2024-03-31T01:30:00")
        XCTAssertEqual(viaLondon.timeIntervalSince1970, inUTC.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(sky(viaLondon), sky(inUTC))
        // The autumn fall-back, when 01:30 occurs twice: Calendar returns the first one, still BST (00:30Z).
        let firstFallBack = london.date(from: DateComponents(year: 2024, month: 10, day: 27, hour: 1, minute: 30))!
        XCTAssertEqual(firstFallBack.timeIntervalSince1970, at("2024-10-27T00:30:00").timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(sky(firstFallBack), sky(at("2024-10-27T00:30:00")))
        // The repeated hour is a real hour of sky: 01:30Z is a different instant and a different altitude.
        XCTAssertNotEqual(sky(firstFallBack), sky(at("2024-10-27T01:30:00")))
    }

    func testLightingPhaseNamesMatchTheTerrainRenderer() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let noon = at("2024-06-20T12:00:00")
        let times = SunCalculator.times(on: noon, latitude: 51.4779, longitude: -0.0015, calendar: utc)
        func sample(_ date: Date) -> DaylightPhase { SolarDaylightEvaluator.sample(at: date, times: times).phase }
        XCTAssertEqual(sample(noon), .noon)
        XCTAssertEqual(sample(noon).solarPhase, .day)
        XCTAssertEqual(sample(at("2024-06-20T00:30:00")).solarPhase, .night)
    }

    func testMoonPhaseAtKnownNewAndFullMoons() {
        let eclipse = at("2024-04-08T18:21:00") // total solar eclipse → new moon
        let full = at("2024-03-25T07:00:00") // March full moon
        XCTAssertLessThan(circularDistance(MoonPhase.fraction(at: eclipse), 0), 0.02)
        XCTAssertLessThan(MoonPhase.illumination(at: eclipse), 0.02)
        XCTAssertEqual(MoonPhase.symbolName(at: eclipse), "moonphase.new.moon")
        XCTAssertLessThan(circularDistance(MoonPhase.fraction(at: full), 0.5), 0.02)
        XCTAssertGreaterThan(MoonPhase.illumination(at: full), 0.98)
        XCTAssertEqual(MoonPhase.symbolName(at: full), "moonphase.full.moon")
    }

    func testMoonPhaseProgressesAcrossALunation() {
        var previous = MoonPhase.fraction(at: at("2024-04-02T00:00:00"))
        for day in stride(from: 4, through: 22, by: 2) {
            let date = at("2024-04-\(String(format: "%02d", day))T00:00:00")
            let phase = MoonPhase.fraction(at: date)
            let advance = (phase - previous + 1).truncatingRemainder(dividingBy: 1)
            XCTAssertEqual(advance, 2 / 29.530588853, accuracy: 0.01, "two days of synodic month")
            XCTAssertEqual(MoonPhase.illumination(at: date), (1 - cos(phase * 2 * .pi)) / 2, accuracy: 0.001)
            previous = phase
        }
        XCTAssertTrue(previous < 0.5, "the sampled fortnight stays in the waxing half")
    }

    func testMoonPositionStaysInRangeAndIsDeterministic() {
        for day in stride(from: 1, through: 28, by: 9) {
            let date = at("2024-02-\(String(format: "%02d", day))T03:00:00")
            let moon = LunarPosition.at(date, latitude: 35.7, longitude: 139.7)
            XCTAssertEqual(moon, LunarPosition.at(date, latitude: 35.7, longitude: 139.7))
            XCTAssertTrue((-90...90).contains(moon.altitude))
            XCTAssertTrue((0..<360).contains(moon.azimuth))
        }
    }
}

final class SkyAtmosphereTests: XCTestCase {
    private let night = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01 00:00 UTC

    private func plan(_ phase: SolarPhase, _ sky: WallpaperSky, seed: UInt64 = 7,
                      date: Date? = nil, location: Bool = false) -> SkyAtmosphere {
        SkyAtmosphere.plan(phase: phase, sky: sky, date: date ?? night, seed: seed,
                           latitude: location ? 51.5 : nil, longitude: location ? -0.1 : nil)
    }

    func testNoonClearHasNoStars() {
        let noon = plan(.day, .clear)
        XCTAssertEqual(noon.starOpacity, 0)
        XCTAssertEqual(noon.starCount, 0)
        XCTAssertEqual(noon.meteor, .none)
    }

    func testStarsRiseThroughDuskAndAreCutByWeather() {
        let nightStars = plan(.night, .clear).starOpacity
        XCTAssertGreaterThan(nightStars, plan(.dusk, .clear).starOpacity)
        XCTAssertGreaterThan(plan(.dusk, .clear).starOpacity, plan(.golden, .clear).starOpacity)
        XCTAssertGreaterThan(plan(.golden, .clear).starOpacity, plan(.day, .clear).starOpacity)
        XCTAssertGreaterThan(nightStars, plan(.night, .cloudy).starOpacity)
        XCTAssertGreaterThan(plan(.night, .cloudy).starOpacity, plan(.night, .fog).starOpacity)
        XCTAssertLessThanOrEqual(plan(.night, .storm).starOpacity, 0.05)
    }

    func testCloudCoverageOrdersByWeatherAndFogStaysFaint() {
        func coverage(_ sky: WallpaperSky) -> Double { plan(.dusk, sky).clouds.map(\.coverage).max() ?? 0 }
        XCTAssertLessThan(coverage(.clear), coverage(.cloudy))
        XCTAssertLessThan(coverage(.cloudy), coverage(.rain))
        XCTAssertLessThan(coverage(.rain), coverage(.storm))
        XCTAssertLessThanOrEqual(plan(.dusk, .fog).clouds.map(\.opacity).max() ?? 1, 0.25)
        XCTAssertGreaterThan(plan(.dusk, .storm).clouds.count, plan(.dusk, .rain).clouds.count)
    }

    func testMoonVisibilityOrdersAndHazeFadesIt() {
        XCTAssertLessThan(plan(.golden, .clear).moon.visibility, plan(.dusk, .clear).moon.visibility)
        XCTAssertLessThan(plan(.dusk, .clear).moon.visibility, plan(.night, .clear).moon.visibility)
        XCTAssertGreaterThan(plan(.night, .clear).moon.visibility, plan(.night, .storm).moon.visibility)
        XCTAssertGreaterThan(plan(.night, .storm).moon.haze, plan(.night, .clear).moon.haze)
        XCTAssertEqual(plan(.day, .clear).moon.visibility, 0)
    }

    func testSeedOnlyMovesTheMeteorAndThePlanIsDeterministic() {
        let a = plan(.night, .clear, seed: 3)
        let b = plan(.night, .clear, seed: 11)
        XCTAssertEqual(a.starCount, b.starCount)
        XCTAssertEqual(a.starOpacity, b.starOpacity)
        XCTAssertEqual(a, plan(.night, .clear, seed: 3))
        XCTAssertEqual(plan(.day, .clear, seed: 3).meteor, .none)
    }

    func testPlanUsesTheRealMoonWhenGivenALocation() {
        let withLocation = plan(.night, .clear, location: true)
        let moon = LunarPosition.at(night, latitude: 51.5, longitude: -0.1)
        XCTAssertEqual(withLocation.moon.altitude, moon.altitude, accuracy: 0.001)
        XCTAssertEqual(withLocation.moon.azimuth, moon.azimuth, accuracy: 0.001)
        XCTAssertEqual(withLocation.moon.fraction, MoonPhase.fraction(at: night), accuracy: 0.0001)
        XCTAssertEqual(withLocation.moon.waxing, MoonPhase.fraction(at: night) < 0.5)
    }
}

final class SignatureTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_735_689_600)

    private func signature(_ phase: SolarPhase = .night, _ sky: WallpaperSky = .clear,
                           version: Int = WallpaperFrameSignature.version) -> String {
        let environment = TerrainMimicCatalog.environment(scene: .alpine, phase: phase, sky: sky)
        let atmosphere = SkyAtmosphere.plan(phase: phase, sky: sky, date: day, seed: 42,
                                            latitude: 51.5, longitude: -0.1)
        return WallpaperFrameSignature.of(environment, atmosphere, version: version)
    }

    func testSignatureIsStableForTheSameEnvironmentAndAtmosphere() {
        XCTAssertEqual(signature(), signature())
        XCTAssertTrue(signature().hasPrefix("\(WallpaperFrameSignature.version)"))
    }

    func testASkyOrPhaseChangeIsANewFile() {
        XCTAssertNotEqual(signature(.night, .clear), signature(.night, .storm))
        XCTAssertNotEqual(signature(.night, .clear), signature(.day, .clear))
        XCTAssertNotEqual(signature(.dusk, .rain), signature(.night, .rain))
    }

    func testARendererVersionBumpIsANewFile() {
        let current = WallpaperFrameSignature.version
        XCTAssertNotEqual(signature(version: current), signature(version: current + 1))
        XCTAssertTrue(signature(version: current + 1).hasPrefix("\(current + 1)"))
    }
}

final class WallpaperMotionGuardTests: XCTestCase {
    private func active(enabled: Bool = true, reduceMotion: Bool = false, lowPower: Bool = false,
                        locked: Bool = false, covered: Bool = false) -> Bool {
        WallpaperMotionGuard.isActive(isEnabled: enabled, reduceMotion: reduceMotion, lowPower: lowPower,
                                      screenLocked: locked, desktopCovered: covered)
    }

    func testOffIsOffAndClearIsOn() {
        XCTAssertFalse(active(enabled: false))
        XCTAssertTrue(active())
    }

    func testEachGuardPausesOnItsOwn() {
        XCTAssertFalse(active(reduceMotion: true))
        XCTAssertFalse(active(lowPower: true))
        XCTAssertFalse(active(locked: true))
        XCTAssertFalse(active(covered: true))
    }

    func testReduceMotionBeatsTheToggleAndGuardsStack() {
        XCTAssertFalse(active(enabled: true, reduceMotion: true))
        XCTAssertFalse(active(enabled: true, reduceMotion: true, lowPower: true))
        XCTAssertFalse(active(enabled: true, lowPower: true, locked: true))
        XCTAssertEqual(WallpaperMotionGuard.coveredFraction, 0.98)
    }
}
