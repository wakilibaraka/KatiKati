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
