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
