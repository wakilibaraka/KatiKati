import Foundation

/// How the wallpaper reacts (Phase 10b-1).
enum WallpaperMode: String, CaseIterable, Sendable {
    case time, weather, both
}

/// The six sky families a wallpaper pack provides.
enum WallpaperSky: String, CaseIterable, Sendable {
    case clear, cloudy, rain, snow, storm, fog

    init(_ condition: WeatherCondition) {
        switch condition {
        case .clear: self = .clear
        case .partlyCloudy, .cloudy: self = .cloudy
        case .drizzle, .rain, .showers: self = .rain
        case .snow: self = .snow
        case .thunderstorm: self = .storm
        case .fog: self = .fog
        }
    }
}

enum WallpaperSelector {
    /// Every file key a complete pack provides: `<phase>-<sky>` (5 × 6 = 30).
    static let allSkyKeys: [String] = SolarPhase.allCases.flatMap { phase in
        WallpaperSky.allCases.map { "\(phase.rawValue)-\($0.rawValue)" }
    }

    /// Extra keys the built-in Sky pack answers so every mode finds a file: `<phase>` (time mode) maps to that
    /// phase under a clear sky, `any-<sky>` (weather mode) to that sky by day, `default` to day-clear.
    static let skyPackAliases: [String: String] = {
        var map: [String: String] = ["default": "day-clear"]
        for phase in SolarPhase.allCases { map[phase.rawValue] = "\(phase.rawValue)-clear" }
        for sky in WallpaperSky.allCases { map["any-\(sky.rawValue)"] = "day-\(sky.rawValue)" }
        return map
    }()

    /// Ordered candidates for a state; the first one the pack has wins (condition+phase → phase → default).
    static func candidates(phase: SolarPhase, sky: WallpaperSky, mode: WallpaperMode) -> [String] {
        switch mode {
        case .time: return [phase.rawValue, "default"]
        case .weather: return ["any-\(sky.rawValue)", "day-\(sky.rawValue)", "default"]
        case .both: return ["\(phase.rawValue)-\(sky.rawValue)", phase.rawValue, "any-\(sky.rawValue)", "default"]
        }
    }

    /// The pack key to show, or nil when the pack has none of the candidates (leave the wallpaper alone).
    static func pick(phase: SolarPhase, sky: WallpaperSky, mode: WallpaperMode, available: Set<String>) -> String? {
        candidates(phase: phase, sky: sky, mode: mode).first(where: available.contains)
    }
}

// MARK: - DW-6 · the weather mood (Auto vs a locked atmosphere)

/// What the picture's sky follows. `auto` uses the forecast the app already has; every other case pins both a sky
/// and a time of day, so a chosen atmosphere survives the next weather update until the user picks Auto again.
enum WallpaperMood: String, CaseIterable, Codable, Sendable {
    case auto
    case rainyEvening
    case goldenEvening
    case snowyDay
    case stormNight
    case clearNight

    /// The sky this mood paints, or nil for `auto` (follow the forecast).
    var lockedSky: WallpaperSky? {
        switch self {
        case .auto: return nil
        case .rainyEvening: return .rain
        case .goldenEvening: return .clear
        case .snowyDay: return .snow
        case .stormNight: return .storm
        case .clearNight: return .clear
        }
    }

    /// The time of day this mood paints, or nil for `auto` (follow the clock).
    var lockedSolarPhase: SolarPhase? {
        switch self {
        case .auto: return nil
        case .rainyEvening, .goldenEvening: return .golden
        case .snowyDay: return .day
        case .stormNight, .clearNight: return .night
        }
    }

    /// Resolve the picture's sky and phase. `auto` passes the live weather and clock through untouched; an override
    /// ignores both, which is the whole point of locking a mood.
    func resolve(weather: WallpaperSky, phase: SolarPhase) -> (sky: WallpaperSky, phase: SolarPhase) {
        guard let sky = lockedSky, let locked = lockedSolarPhase else { return (weather, phase) }
        return (sky, locked)
    }
}

// MARK: - DW-1 · environment mimicry (City · Countryside · Terrain)

/// What the user pinned. `auto` lets `TerrainMimicCatalog` pick from the weather location's own name and
/// latitude, so the wallpaper fits the place without another permission, network call or prompt.
enum WallpaperTerrain: String, CaseIterable, Codable, Sendable {
    case auto, city, countryside, terrain
}

/// A resolved scene. Terrain splits in two because "mountains" and "coast" are different pictures, and the
/// plan names both (`alpine`, `coast`); the pin stays the coarse three-way `WallpaperTerrain`.
enum WallpaperScene: String, CaseIterable, Sendable {
    case city, countryside, alpine, coast
}

/// Everything a renderer needs for one frame: the sky, the light, the layered silhouettes and the three
/// hues the dock accent is sampled from. Pure and comparable, so the scene is unit-tested, not eyeballed.
struct WallpaperEnvironment: Equatable, Sendable {
    var scene: WallpaperScene
    var skyTop: SkyRGB
    var skyBottom: SkyRGB
    /// Sun/moon glow tint and how strong it is (0…1) — 0 when the sky is overcast.
    var glow: SkyRGB
    var glowStrength: Double
    /// Silhouette colours, farthest (lightest) to nearest (darkest) — 3 for the land scenes, 3 skyline bands
    /// for the city.
    var layers: [SkyRGB]
    /// Three hues the dock accent samples: sky top, horizon, nearest silhouette.
    var accent: [SkyRGB]
}

enum TerrainMimicCatalog {
    /// Words in a place name that make a scene the obvious pick. Lowercased, substring-matched: the feed
    /// gives a city name, not coordinates, and inventing a coastline detector would be a guess.
    static let cityWords = ["city", "downtown", "midtown", "uptown", "metropolis", "new york", "tokyo",
                            "london", "paris", "berlin", "madrid", "rome", "milan", "barcelona", "amsterdam",
                            "shanghai", "beijing", "shenzhen", "singapore", "dubai", "seoul", "sydney",
                            "chicago", "toronto", "boston", "miami", "los angeles", "san francisco"]
    static let coastWords = ["coast", "coastal", "beach", "bay", "harbour", "harbor", "port", "island",
                             "sea", "seaside", "shore", "marina", "lido", "riviera"]
    static let countrysideWords = ["farm", "field", "meadow", "valley", "village", "rural", "country",
                                   "hill", "hills", "pasture", "prairie", "vineyard", "ridge"]

    /// The scene to draw for a pin, the weather location's latitude and its name.
    static func resolve(_ terrain: WallpaperTerrain, latitude: Double? = nil, cityName: String = "") -> WallpaperScene {
        let name = cityName.lowercased()
        func names(_ words: [String]) -> Bool { words.contains { name.contains($0) } }
        switch terrain {
        case .city: return .city
        case .countryside: return .countryside
        case .terrain: return names(coastWords) ? .coast : .alpine
        case .auto:
            if names(coastWords) { return .coast }
            if names(cityWords) { return .city }
            if names(countrysideWords) { return .countryside }
            // No word to go on: high latitudes read as mountain country, everything else as countryside.
            if let latitude, abs(latitude) >= 45 { return .alpine }
            return .countryside
        }
    }

    /// The scene for one phase and sky. The sky comes from the same `SkyPalette` the pack paints with, so the
    /// wallpaper, the glass tint and the dock accent always agree; the layers are derived and darkened from it.
    static func environment(scene: WallpaperScene, phase: SolarPhase, sky: WallpaperSky) -> WallpaperEnvironment {
        let stops = SkyPalette.stops(phase: phase, sky: sky)
        let dark = phase == .night || phase == .dusk
        let glow = dark ? SkyRGB(r: 0.82, g: 0.87, b: 1.0) : SkyRGB(r: 1.0, g: 0.93, b: 0.76)
        let overcast = sky != .clear && sky != .cloudy
        let glowStrength = overcast ? 0.0 : (sky == .cloudy ? 0.18 : (phase == .day || phase == .golden ? 0.45 : 0.3))
        return WallpaperEnvironment(
            scene: scene,
            skyTop: stops.top,
            skyBottom: stops.bottom,
            glow: glow,
            glowStrength: glowStrength,
            layers: layers(for: scene, sky: stops.bottom, dark: dark),
            accent: [stops.top, stops.bottom, layers(for: scene, sky: stops.bottom, dark: dark).last ?? stops.bottom]
        )
    }

    /// Three silhouette bands. The city's are near-black skyline bands; the land scenes step down from the
    /// horizon colour so the nearest ridge reads heaviest.
    static func layers(for scene: WallpaperScene, sky: SkyRGB, dark: Bool) -> [SkyRGB] {
        let shade: SkyRGB = dark ? SkyRGB(r: 0.05, g: 0.06, b: 0.12) : SkyRGB(r: 0.16, g: 0.15, b: 0.22)
        switch scene {
        case .city:
            return [sky.mixed(with: shade, 0.55), sky.mixed(with: shade, 0.75), sky.mixed(with: shade, 0.9)]
        case .countryside:
            return [sky.mixed(with: shade, 0.30), sky.mixed(with: shade, 0.50), sky.mixed(with: shade, 0.70)]
        case .alpine:
            // Snow on the far ridge: it stays lighter than the sky's own horizon in daylight.
            let snow = dark ? sky.mixed(with: SkyRGB(r: 0.55, g: 0.6, b: 0.75), 0.25) : sky.mixed(with: SkyRGB(r: 1, g: 1, b: 1), 0.22)
            return [snow, sky.mixed(with: shade, 0.55), sky.mixed(with: shade, 0.8)]
        case .coast:
            let water = sky.mixed(with: SkyRGB(r: 0.04, g: 0.18, b: 0.32), dark ? 0.6 : 0.45)
            return [sky.mixed(with: shade, 0.35), sky.mixed(with: shade, 0.6), water]
        }
    }
}

/// `DOCK_WALLPAPER_PHASE` parsing: `dusk` or `dusk:rain`. Unknown words → nil (override ignored).
enum WallpaperDebugOverride {
    static func parse(_ raw: String?) -> (phase: SolarPhase, sky: WallpaperSky?)? {
        guard let raw, !raw.isEmpty else { return nil }
        let parts = raw.lowercased().split(separator: ":").map(String.init)
        guard let phase = SolarPhase(rawValue: parts[0]) else { return nil }
        if parts.count > 1 {
            guard let sky = WallpaperSky(rawValue: parts[1]) else { return nil }
            return (phase, sky)
        }
        return (phase, nil)
    }
}

/// DW-7 — every path the generated frames may use, and the only files pruning is allowed to remove.
///
/// The dynamic wallpaper is additive: it writes into its own cache and may only delete files it named itself.
/// The built-in Sky pack (`Wallpapers/sky`, the pre-DW simple wallpapers), a custom folder and the owner's
/// captured original are never listed, moved or removed from here.
enum WallpaperCache {
    static let generatedPath = "KatiKati/DynamicWallpapers/Generated"
    static let legacyPath = "KatiKati/Wallpapers/terrain"
    static let skyPackPath = "KatiKati/Wallpapers/sky"

    static func generatedDirectory(in base: URL) -> URL { base.appendingPathComponent(generatedPath, isDirectory: true) }
    static func legacyDirectory(in base: URL) -> URL { base.appendingPathComponent(legacyPath, isDirectory: true) }
    static func skyPackDirectory(in base: URL) -> URL { base.appendingPathComponent(skyPackPath, isDirectory: true) }

    /// The renderer's own file-name shape: `terrain-<scene>-<phase>-<sky>-<WxH>-<digest>[-gN].png`.
    /// Anything else — a user's `default.heic`, a Sky-pack copy, a note — is not ours to delete.
    static func isOwnRender(named name: String) -> Bool {
        guard name.hasSuffix(".png") else { return false }
        let parts = name.dropLast(4).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 6 || parts.count == 7, parts[0] == "terrain" else { return false }
        guard parts[1...3].allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isLowercase) }) else { return false }
        let size = parts[4].split(separator: "x", omittingEmptySubsequences: false)
        guard size.count == 2, size.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return false }
        guard !parts[5].isEmpty, parts[5].allSatisfy(\.isHexDigit) else { return false }
        if parts.count == 7 {
            guard parts[6].first == "g", parts[6].count > 1, parts[6].dropFirst().allSatisfy(\.isNumber) else { return false }
        }
        return true
    }

    /// The pre-DW-2 render names — `night-clear-3420x2224-d600c2af[-gN].png`, phase and sky spelled out
    /// without the `terrain-` prefix. Also ours, and only ever cleaned from the legacy folder: the generated
    /// cache itself is judged by `isOwnRender` alone, so a copy there is never swept up by the older rule.
    static func isLegacyRender(named name: String) -> Bool {
        guard name.hasSuffix(".png") else { return false }
        let parts = name.dropLast(4).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 4 || parts.count == 5,
              SolarPhase(rawValue: String(parts[0])) != nil,
              WallpaperSky(rawValue: String(parts[1])) != nil else { return false }
        let size = parts[2].split(separator: "x", omittingEmptySubsequences: false)
        guard size.count == 2, size.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return false }
        guard !parts[3].isEmpty, parts[3].allSatisfy(\.isHexDigit) else { return false }
        if parts.count == 5 {
            guard parts[4].first == "g", parts[4].count > 1, parts[4].dropFirst().allSatisfy(\.isNumber) else { return false }
        }
        return true
    }

    /// The picture a file belongs to, generation copies and the base frame sharing one name.
    static func baseName(of name: String) -> String? {
        guard isOwnRender(named: name) else { return nil }
        let stem = String(name.dropLast(4))
        guard let range = stem.range(of: "-g", options: .backwards),
              !stem[range.upperBound...].isEmpty,
              stem[range.upperBound...].allSatisfy(\.isNumber) else { return stem }
        return String(stem[..<range.lowerBound])
    }

    /// Drops expired renders and keeps at most `keepGenerations` files per picture, touching only our own.
    @discardableResult
    static func prune(in directory: URL, now: Date = Date(), maximumAge: TimeInterval = 14 * 86_400,
                      keepGenerations: Int = 2, fileManager: FileManager = .default) -> [URL] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return [] }
        var removed: [URL] = []
        var generations: [String: [(url: URL, date: Date)]] = [:]
        for name in names where isOwnRender(named: name) {
            let url = directory.appendingPathComponent(name)
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if now.timeIntervalSince(date) > maximumAge {
                if (try? fileManager.removeItem(at: url)) != nil { removed.append(url) }
                continue
            }
            generations[baseName(of: name) ?? name, default: []].append((url, date))
        }
        for list in generations.values where list.count > keepGenerations {
            for stale in list.sorted(by: { $0.date > $1.date }).dropFirst(keepGenerations) {
                if (try? fileManager.removeItem(at: stale.url)) != nil { removed.append(stale.url) }
            }
        }
        return removed
    }

    /// Deletes only the renderer's own leftovers from the pre-DW-7 folder — both the current name shape and
    /// the older phase-sky shape. Its Sky-pack sibling, custom files and anything else there are left alone.
    @discardableResult
    static func removeLegacyRenders(in legacyDirectory: URL, fileManager: FileManager = .default) -> [URL] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: legacyDirectory.path) else { return [] }
        var removed: [URL] = []
        for name in names where isOwnRender(named: name) || isLegacyRender(named: name) {
            let url = legacyDirectory.appendingPathComponent(name)
            if (try? fileManager.removeItem(at: url)) != nil { removed.append(url) }
        }
        return removed
    }
}

// MARK: - DW-10 · whether the cloud overlay may exist

/// One decision, five inputs, no clock and no window: may the Small Animation overlay be on screen right now?
/// Off stays off; Reduce Motion is an accessibility contract, not a preference; Low Power Mode, a locked or sleeping
/// screen and a desktop covered by another app's window all hide it. Battery power alone does not pause it: the
/// overlay measured at 0.03 % of one core, and silently stopping a feature the user just enabled would look broken.
enum WallpaperMotionGuard {
    /// A window counts as covering the desktop at this fraction of the screen's area.
    static let coveredFraction = 0.98

    static func isActive(isEnabled: Bool, reduceMotion: Bool, lowPower: Bool,
                         screenLocked: Bool, desktopCovered: Bool) -> Bool {
        guard isEnabled, !reduceMotion, !lowPower, !screenLocked, !desktopCovered else { return false }
        return true
    }

    static func isMusicSwapAllowed(isEnabled: Bool, isAnimated: Bool, isPlaying: Bool,
                                   screenLocked: Bool, isAsleep: Bool, desktopCovered: Bool) -> Bool {
        isEnabled && isAnimated && isPlaying && !screenLocked && !isAsleep && !desktopCovered
    }
}

enum WallpaperRefreshPolicy {
    static func shouldRefresh(forWake: Bool, isSleep: Bool) -> Bool {
        forWake && !isSleep
    }

    static func nextGeneration(current: Int, force: Bool, keyAlreadyApplied: Bool, lowPower: Bool) -> Int {
        guard force, keyAlreadyApplied else { return 0 }
        return lowPower ? current : current &+ 1
    }
}

// MARK: - DW-8 · celestial + atmospheric model

/// Where a body sits, in degrees: altitude −90…90 (negative = below the horizon), azimuth 0…<360 from north.
struct CelestialPosition: Equatable, Sendable {
    var altitude: Double
    var azimuth: Double
}

/// Shared astronomy maths: absolute instants and an east-positive longitude only, so no calendar, time zone or
/// DST value can enter and the same `Date` gives the same sky wherever the Mac thinks it is.
enum CelestialMath {
    static let day = 86_400.0

    static func julianDay(_ date: Date) -> Double { date.timeIntervalSince1970 / day + 2_440_587.5 }
    static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
    static func normalizedDegrees(_ degrees: Double) -> Double {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// Right ascension / declination → altitude / azimuth (standard equatorial-to-horizontal transform).
    static func horizontal(rightAscension: Double, declination: Double, date: Date,
                           latitude: Double, longitude: Double) -> CelestialPosition {
        let daysSinceJ2000 = julianDay(date) - 2_451_545.0
        let greenwich = normalizedDegrees(280.460_618_37 + 360.985_647_366_29 * daysSinceJ2000)
        let hourAngle = radians(greenwich + longitude) - rightAscension
        let phi = radians(latitude)
        let altitude = asin(sin(phi) * sin(declination) + cos(phi) * cos(declination) * cos(hourAngle))
        let azimuth = atan2(sin(hourAngle), cos(hourAngle) * sin(phi) - tan(declination) * cos(phi)) + .pi
        return CelestialPosition(altitude: degrees(altitude), azimuth: normalizedDegrees(degrees(azimuth)))
    }
}

/// The sun's place for an instant and a location (low-precision solar ephemeris; good to ~0.01° for a century).
enum SolarPosition {
    static func at(_ date: Date, latitude: Double, longitude: Double) -> CelestialPosition {
        let n = CelestialMath.julianDay(date) - 2_451_545.0
        let meanLongitude = CelestialMath.normalizedDegrees(280.460 + 0.985_647_4 * n)
        let meanAnomaly = CelestialMath.radians(CelestialMath.normalizedDegrees(357.528 + 0.985_600_3 * n))
        let ecliptic = CelestialMath.radians(meanLongitude + 1.915 * sin(meanAnomaly) + 0.020 * sin(2 * meanAnomaly))
        let obliquity = CelestialMath.radians(23.439 - 0.000_000_4 * n)
        let rightAscension = atan2(cos(obliquity) * sin(ecliptic), cos(ecliptic))
        let declination = asin(sin(obliquity) * sin(ecliptic))
        return CelestialMath.horizontal(rightAscension: rightAscension, declination: declination,
                                        date: date, latitude: latitude, longitude: longitude)
    }

}

struct SolarGlowPosition: Equatable, Sendable {
    var x: Double
    var y: Double

    static func at(_ date: Date, latitude: Double?, longitude: Double?, fallbackX: Double = 0.72, fallbackY: Double = 0.66) -> SolarGlowPosition {
        guard let latitude, let longitude else {
            return SolarGlowPosition(x: fallbackX, y: fallbackY)
        }
        let position = SolarPosition.at(date, latitude: latitude, longitude: longitude)
        let x = 0.5 + sin(CelestialMath.radians(position.azimuth)) * 0.42
        let y = 0.18 + min(max((position.altitude + 10) / 80, 0), 1) * 0.54
        return SolarGlowPosition(x: min(max(x, 0), 1), y: min(max(y, 0.18), 0.72))
    }
}

/// The moon's place for an instant and a location (abbreviated lunar ephemeris: mean longitude, anomaly and
/// argument of latitude, plus the main 6.3° evection term). Phase and illumination come from the existing
/// `MoonPhase` the weather panel already uses, so the wallpaper and the panel can never disagree.
enum LunarPosition {
    static func at(_ date: Date, latitude: Double, longitude: Double) -> CelestialPosition {
        let n = CelestialMath.julianDay(date) - 2_451_545.0
        let meanLongitude = CelestialMath.radians(CelestialMath.normalizedDegrees(218.316 + 13.176_396 * n))
        let meanAnomaly = CelestialMath.radians(CelestialMath.normalizedDegrees(134.963 + 13.064_993 * n))
        let argumentOfLatitude = CelestialMath.radians(CelestialMath.normalizedDegrees(93.272 + 13.229_350 * n))
        let ecliptic = meanLongitude + CelestialMath.radians(6.289) * sin(meanAnomaly)
        let latitudeEcliptic = CelestialMath.radians(5.128) * sin(argumentOfLatitude)
        let obliquity = CelestialMath.radians(23.439)
        let rightAscension = atan2(sin(ecliptic) * cos(obliquity) - tan(latitudeEcliptic) * sin(obliquity), cos(ecliptic))
        let declination = asin(sin(latitudeEcliptic) * cos(obliquity)
                               + cos(latitudeEcliptic) * sin(obliquity) * sin(ecliptic))
        return CelestialMath.horizontal(rightAscension: rightAscension, declination: declination,
                                        date: date, latitude: latitude, longitude: longitude)
    }
}

/// DW-9 — the cache key: a short, stable digest of everything that changes the pixels (the colours, the
/// atmosphere's numbers) plus the renderer version, so a palette, weather or code change is a new file instead of
/// macOS re-showing the old one. Pure and in Core, so the signature itself is unit-tested.
enum WallpaperFrameSignature {
    /// Bump when the drawing code changes; `version` is part of the digest and its own file-name prefix.
    static let version = 2

    static func of(_ environment: WallpaperEnvironment, _ atmosphere: SkyAtmosphere,
                   version: Int = version) -> String {
        func part(_ c: SkyRGB) -> String { "\(Int((c.r * 255).rounded()))-\(Int((c.g * 255).rounded()))-\(Int((c.b * 255).rounded()))" }
        func q(_ v: Double) -> String { String(Int((v * 1_000).rounded())) }
        var parts = ["\(version)", environment.scene.rawValue, String(environment.layers.count), q(environment.glowStrength),
                     q(atmosphere.starOpacity), String(atmosphere.starCount), q(atmosphere.twinkleDepth),
                     atmosphere.meteor.rawValue, q(atmosphere.horizonGlow), q(atmosphere.moon.visibility),
                     q(atmosphere.moon.halo), q(atmosphere.moon.haze), q(atmosphere.moon.illumination),
                     atmosphere.moon.waxing ? "w" : "n", q(atmosphere.moon.altitude), q(atmosphere.moon.azimuth)]
        parts += [environment.skyTop, environment.skyBottom, environment.glow].map(part) + environment.layers.map(part)
        for band in atmosphere.clouds {
            parts += [band.family.rawValue, q(band.coverage), q(band.opacity), q(band.thickness), q(band.drift), q(band.speed)]
        }
        var value: UInt32 = 2_166_136_261
        for character in parts.joined(separator: "|").unicodeScalars { value = (value ^ character.value) &* 16_777_619 }
        return "\(version)" + String(value, radix: 16)
    }
}

enum CloudFamily: String, CaseIterable, Sendable { case cirrus, wisp, bank }

struct CloudBand: Equatable, Sendable {
    var family: CloudFamily
    var coverage: Double
    var opacity: Double
    var thickness: Double
    var drift: Double
    var speed: Double
}

enum Meteor: String, CaseIterable, Sendable { case none, faint, bright }

struct MoonAppearance: Equatable, Sendable {
    var visibility: Double
    var halo: Double
    var haze: Double
    /// 0 = new … 0.5 = full: which terminator the renderer draws.
    var fraction: Double
    var illumination: Double
    var waxing: Bool
    var altitude: Double
    var azimuth: Double
}

/// Everything DW-9's renderer needs to paint a sky, decided once and purely. `plan` reads no clock and touches
/// no files: the phase, the weather, the instant and the seed are all inputs.
struct SkyAtmosphere: Equatable, Sendable {
    var starOpacity: Double
    var starCount: Int
    var twinkleDepth: Double
    var meteor: Meteor
    var moon: MoonAppearance
    var clouds: [CloudBand]
    var horizonGlow: Double
}

extension SkyAtmosphere {
    private static let starBase: [SolarPhase: Double] = [.night: 1, .dusk: 0.55, .golden: 0.15, .dawn: 0.1, .day: 0]
    private static let skyStarCut: [WallpaperSky: Double] = [.clear: 1, .cloudy: 0.7, .fog: 0.4, .snow: 0.35, .rain: 0.2, .storm: 0.05]
    private static let moonBase: [SolarPhase: Double] = [.night: 1, .dusk: 0.55, .golden: 0.25, .dawn: 0.2, .day: 0]
    private static let skyHaze: [WallpaperSky: Double] = [.clear: 0.05, .cloudy: 0.35, .snow: 0.4, .rain: 0.6, .fog: 0.8, .storm: 0.9]
    private static let glowBase: [SolarPhase: Double] = [.night: 0.05, .dawn: 0.7, .day: 0.35, .golden: 0.9, .dusk: 0.5]
    private static let glowDim: [WallpaperSky: Double] = [.clear: 1, .cloudy: 0.7, .snow: 0.5, .fog: 0.6, .rain: 0.35, .storm: 0.15]

    /// `latitude`/`longitude` are optional only so the stage preview (which has no weather location) can still ask
    /// for a plan; with them the moon's altitude and azimuth are real, without them they are a plainer ladder value.
    static func plan(phase: SolarPhase, sky: WallpaperSky, date: Date, seed: UInt64,
                     latitude: Double? = nil, longitude: Double? = nil) -> SkyAtmosphere {
        let clamp: (Double) -> Double = { min(max($0, 0), 1) }
        let stars = clamp((starBase[phase] ?? 0) * (skyStarCut[sky] ?? 1))
        let haze = skyHaze[sky] ?? 0
        let moonVisibility = clamp((moonBase[phase] ?? 0) * (1 - haze * 0.7))
        let lunar: CelestialPosition? = if let latitude, let longitude {
            LunarPosition.at(date, latitude: latitude, longitude: longitude)
        } else {
            nil
        }
        let fraction = MoonPhase.fraction(at: date)
        let roll = Int((seed &+ UInt64(abs(Int(date.timeIntervalSince1970 / CelestialMath.day)))) % 8)
        let meteor: Meteor = stars >= 0.5 && (sky == .clear || sky == .cloudy || sky == .snow)
            ? (roll == 0 ? .bright : (roll < 3 ? .faint : .none)) : .none
        return SkyAtmosphere(
            starOpacity: stars,
            starCount: Int((stars * 120).rounded()),
            twinkleDepth: stars * 0.25,
            meteor: meteor,
            moon: MoonAppearance(visibility: moonVisibility,
                                 halo: moonVisibility * (1 - haze),
                                 haze: haze,
                                 fraction: fraction,
                                 illumination: MoonPhase.illumination(at: date),
                                 waxing: fraction < 0.5,
                                 altitude: lunar?.altitude ?? (moonVisibility * 45),
                                 azimuth: lunar?.azimuth ?? 0),
            clouds: cloudBands(for: sky),
            horizonGlow: clamp((glowBase[phase] ?? 0) * (glowDim[sky] ?? 1))
        )
    }

    /// family, coverage, opacity, thickness, drift, speed — one row per weather the wallpaper already draws.
    private static func cloudBands(for sky: WallpaperSky) -> [CloudBand] {
        let table: [WallpaperSky: [(CloudFamily, Double, Double, Double, Double, Double)]] = [
            .clear: [(.wisp, 0.12, 0.25, 0.18, 0.10, 0.20)],
            .cloudy: [(.cirrus, 0.35, 0.40, 0.16, 0.25, 0.30), (.wisp, 0.50, 0.35, 0.28, 0.30, 0.35)],
            .rain: [(.bank, 0.75, 0.60, 0.42, 0.55, 0.45), (.bank, 0.65, 0.50, 0.34, 0.65, 0.50), (.wisp, 0.50, 0.40, 0.22, 0.80, 0.60)],
            .storm: [(.bank, 0.90, 0.80, 0.50, 0.95, 0.80), (.bank, 0.85, 0.70, 0.44, 1.10, 0.85), (.bank, 0.80, 0.60, 0.36, 1.25, 0.90), (.cirrus, 0.60, 0.50, 0.20, 1.40, 1.00)],
            .snow: [(.wisp, 0.45, 0.35, 0.26, 0.30, 0.25), (.bank, 0.40, 0.30, 0.30, 0.40, 0.30)],
            .fog: [(.bank, 0.70, 0.20, 0.10, 0.20, 0.10), (.bank, 0.60, 0.15, 0.08, 0.30, 0.12)],
        ]
        return (table[sky] ?? []).map { CloudBand(family: $0.0, coverage: $0.1, opacity: $0.2,
                                                  thickness: $0.3, drift: $0.4, speed: $0.5) }
    }
}
