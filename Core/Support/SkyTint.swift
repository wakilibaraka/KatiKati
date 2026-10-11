import Foundation

// Phase 5i-A — the live "sky" colour of the weather pane. One gradient per condition (and night);
// the glance layout slices it into tiles so the whole pane reads as one sky, and the mountain hero
// uses the layered ridge colours. Pure and unit-tested; the views only turn these into `Color`s.

public enum WeatherHeroStyle: String, CaseIterable, Codable, Sendable {
    /// Layered mountain/horizon scene (default).
    case scene
    /// The earlier gradient + cloud-icon hero, kept as a preset.
    case classic
    public static let storageKey = "com.katikati.weather.heroStyle"
}

public enum WeatherLayoutPreset: String, CaseIterable, Codable, Sendable {
    /// One non-scrolling page: hero + hour strip + Hourly | Daily | Details panel (default).
    case glance
    /// The earlier stacked tiles (Mac / iPad / Tall compositions), kept as a preset.
    case classic
    public static let storageKey = "com.katikati.weather.layout"
}

public struct SkyTint: Equatable, Sendable {
    public let top: TileRGB
    public let bottom: TileRGB
    /// Mountain ridge colours, farthest (lightest) to nearest (darkest).
    public let ridges: [TileRGB]

    /// Perceived brightness of the sky 0…1 (Rec. 601).
    public var luminance: Double {
        let m = mix(0.5)
        return 0.299 * m.r + 0.587 * m.g + 0.114 * m.b
    }

    /// Bright skies (snow, fog, clear day) need dark text; the rest take white.
    public var prefersDarkText: Bool { luminance > 0.66 }

    /// Colour `t` of the way down the sky (0 = top, 1 = bottom).
    public func mix(_ t: Double) -> TileRGB {
        let k = Swift.min(Swift.max(t, 0), 1)
        return TileRGB(r: top.r + (bottom.r - top.r) * k, g: top.g + (bottom.g - top.g) * k, b: top.b + (bottom.b - top.b) * k)
    }

    public static func tint(condition: WeatherCondition, isNight: Bool) -> SkyTint {
        func c(_ r: Double, _ g: Double, _ b: Double) -> TileRGB { TileRGB(r: r, g: g, b: b) }
        if isNight {
            switch condition {
            case .rain, .showers, .drizzle:
                return SkyTint(top: c(0.16, 0.14, 0.34), bottom: c(0.46, 0.32, 0.58), ridges: [c(0.34, 0.27, 0.48), c(0.24, 0.19, 0.38), c(0.15, 0.12, 0.26)])
            case .thunderstorm:
                return SkyTint(top: c(0.10, 0.08, 0.20), bottom: c(0.30, 0.20, 0.40), ridges: [c(0.25, 0.19, 0.35), c(0.17, 0.13, 0.26), c(0.10, 0.08, 0.18)])
            case .snow:
                return SkyTint(top: c(0.18, 0.22, 0.42), bottom: c(0.45, 0.55, 0.75), ridges: [c(0.40, 0.46, 0.64), c(0.28, 0.33, 0.50), c(0.17, 0.20, 0.34)])
            case .fog:
                return SkyTint(top: c(0.22, 0.25, 0.34), bottom: c(0.42, 0.46, 0.54), ridges: [c(0.38, 0.41, 0.50), c(0.28, 0.31, 0.40), c(0.19, 0.21, 0.29)])
            case .cloudy, .partlyCloudy:
                return SkyTint(top: c(0.14, 0.15, 0.32), bottom: c(0.34, 0.38, 0.58), ridges: [c(0.32, 0.34, 0.52), c(0.22, 0.24, 0.40), c(0.14, 0.15, 0.27)])
            case .clear:
                return SkyTint(top: c(0.09, 0.07, 0.26), bottom: c(0.26, 0.22, 0.54), ridges: [c(0.30, 0.25, 0.48), c(0.20, 0.16, 0.36), c(0.12, 0.10, 0.24)])
            }
        }
        switch condition {
        case .clear:
            return SkyTint(top: c(0.33, 0.74, 0.85), bottom: c(0.97, 0.80, 0.55), ridges: [c(0.95, 0.70, 0.45), c(0.88, 0.58, 0.36), c(0.62, 0.40, 0.36)])
        case .partlyCloudy:
            return SkyTint(top: c(0.36, 0.66, 0.86), bottom: c(0.90, 0.82, 0.70), ridges: [c(0.78, 0.66, 0.58), c(0.62, 0.52, 0.50), c(0.40, 0.34, 0.40)])
        case .cloudy:
            return SkyTint(top: c(0.40, 0.55, 0.72), bottom: c(0.74, 0.79, 0.86), ridges: [c(0.62, 0.68, 0.78), c(0.46, 0.52, 0.64), c(0.30, 0.35, 0.47)])
        case .drizzle, .rain, .showers:
            return SkyTint(top: c(0.45, 0.38, 0.58), bottom: c(0.90, 0.56, 0.66), ridges: [c(0.76, 0.52, 0.62), c(0.52, 0.38, 0.54), c(0.32, 0.25, 0.42)])
        case .thunderstorm:
            return SkyTint(top: c(0.20, 0.16, 0.32), bottom: c(0.52, 0.34, 0.52), ridges: [c(0.42, 0.30, 0.46), c(0.28, 0.20, 0.34), c(0.17, 0.12, 0.24)])
        case .snow:
            return SkyTint(top: c(0.58, 0.76, 0.93), bottom: c(0.90, 0.95, 0.99), ridges: [c(0.78, 0.86, 0.95), c(0.58, 0.68, 0.82), c(0.38, 0.48, 0.64)])
        case .fog:
            return SkyTint(top: c(0.58, 0.63, 0.71), bottom: c(0.84, 0.87, 0.90), ridges: [c(0.74, 0.78, 0.83), c(0.60, 0.64, 0.71), c(0.46, 0.50, 0.58)])
        }
    }
}

public enum SceneGeometry {
    /// Ridge height (0…1 of the scene's mountain band) at normalised x: layered sines plus one main
    /// peak at `peakX`. Deterministic so the scene never shimmers between frames.
    public static func ridge(x: Double, layer: Int, peakX: Double = 0.5) -> Double {
        let f1 = 5.0 + Double(layer) * 2.3, f2 = 11.0 + Double(layer) * 3.1
        let ph = Double(layer) * 1.7
        let waves = 0.18 * sin(x * f1 + ph) + 0.08 * sin(x * f2 + ph * 2)
        let d = (x - peakX) * (layer == 0 ? 1.6 : 2.2)
        let main = (layer == 2 ? 0.55 : 0.35) * exp(-d * d * 9)
        return Swift.min(Swift.max(0.30 + waves + main, 0.05), 1)
    }
}
