import Foundation

/// Phase 10b-2 — colours of the built-in procedural "Sky" wallpaper pack. Pure, so the 30 looks are tested
/// and frozen; the CoreGraphics renderer lives in the app layer.
struct SkyRGB: Equatable, Sendable {
    var r: Double, g: Double, b: Double

    func mixed(with other: SkyRGB, _ t: Double) -> SkyRGB {
        SkyRGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }
}

enum SkyPalette {
    /// (top, bottom) gradient stops for a phase × sky pair.
    static func stops(phase: SolarPhase, sky: WallpaperSky) -> (top: SkyRGB, bottom: SkyRGB) {
        let base = baseStops(phase)
        let (target, amount) = weatherShift(sky, phase: phase)
        return (base.top.mixed(with: target, amount), base.bottom.mixed(with: target, amount))
    }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> SkyRGB {
        SkyRGB(r: Double(r) / 255, g: Double(g) / 255, b: Double(b) / 255)
    }

    private static func baseStops(_ phase: SolarPhase) -> (top: SkyRGB, bottom: SkyRGB) {
        switch phase {
        case .night: return (rgb(10, 16, 44), rgb(44, 40, 96))
        case .dawn: return (rgb(88, 92, 168), rgb(250, 168, 124))
        case .day: return (rgb(48, 140, 236), rgb(168, 214, 250))
        case .golden: return (rgb(92, 140, 214), rgb(255, 190, 110))
        case .dusk: return (rgb(54, 40, 112), rgb(232, 98, 108))
        }
    }

    /// Weather pulls the base toward a grey (or white for snow) by an amount; clear leaves it alone.
    private static func weatherShift(_ sky: WallpaperSky, phase: SolarPhase) -> (SkyRGB, Double) {
        let dark = phase == .night || phase == .dusk
        switch sky {
        case .clear: return (rgb(128, 128, 128), 0)
        case .cloudy: return (dark ? rgb(60, 64, 82) : rgb(150, 158, 172), 0.45)
        case .rain: return (dark ? rgb(38, 46, 62) : rgb(96, 110, 128), 0.6)
        case .storm: return (dark ? rgb(24, 26, 40) : rgb(58, 64, 82), 0.72)
        case .snow: return (dark ? rgb(120, 132, 156) : rgb(232, 240, 250), 0.55)
        case .fog: return (dark ? rgb(84, 90, 104) : rgb(200, 206, 214), 0.65)
        }
    }
}

extension SunTimes {
    /// Parses Open-Meteo's `yyyy-MM-dd'T'HH:mm` strings (the feed's local time) in `calendar`'s time zone.
    /// Nil when either string is missing or malformed.
    static func parse(sunrise: String?, sunset: String?, calendar: Calendar = .current) -> SunTimes? {
        func date(_ s: String?) -> Date? {
            guard let s, s.count >= 16 else { return nil }
            let p = s.split(whereSeparator: { "-T:".contains($0) }).compactMap { Int($0) }
            guard p.count >= 5 else { return nil }
            return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: p[3], minute: p[4]))
        }
        guard let rise = date(sunrise), let set = date(sunset) else { return nil }
        return SunTimes(sunrise: rise, sunset: set)
    }
}
