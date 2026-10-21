import Foundation

/// Phase 56: the weather widget's size ladder. Each size appends one band to an unchanged header, so
/// resizing reveals rather than reflows (`Docs/WEATHER_DESIGN_LANGUAGE.md`, adopted rule 2).
enum WeatherBand: Equatable, Sendable {
    case header, hourly, daily, details
}

enum WeatherLayoutSpec {
    /// S = header, M = + hourly strip, L = + 7-day range rows; the detail grid is a panel-only XL.
    static func bands(for size: WidgetSize, panel: Bool = false) -> [WeatherBand] {
        var bands: [WeatherBand] = [.header]
        if size >= .medium { bands.append(.hourly) }
        if size >= .large { bands.append(.daily) }
        if panel && size >= .large { bands.append(.details) }
        return bands
    }

    /// Effects sit behind the header from Medium up; at Small they would fight the 11 pt text.
    static func showsEffects(for size: WidgetSize) -> Bool { size >= .medium }
}

/// One day's low-high bar placed inside the week's overall range, as 0...1 fractions of the track.
struct TemperatureRange: Equatable, Sendable {
    let start: Double
    let end: Double

    init(low: Double, high: Double, weekLow: Double, weekHigh: Double) {
        let span = weekHigh - weekLow
        guard span > 0 else { start = 0; end = 1; return }
        let clamp = { (v: Double) in min(max((v - weekLow) / span, 0), 1) }
        start = clamp(min(low, high))
        end = max(clamp(max(low, high)), start)
    }

    /// Where the "now" dot sits on today's bar, kept inside the bar so it never floats off it.
    func marker(current: Double, low: Double, high: Double) -> Double {
        guard high > low else { return start }
        let t = min(max((current - low) / (high - low), 0), 1)
        return start + (end - start) * t
    }
}

/// How old a reading is, for the dimmed "Updated 3h ago" stamp and the stale dot.
enum WeatherStaleness: Equatable, Sendable {
    case fresh, stale, old

    static let freshWindow: TimeInterval = 45 * 60
    static let staleWindow: TimeInterval = 3 * 3600

    init(age: TimeInterval) {
        self = age <= Self.freshWindow ? .fresh : (age <= Self.staleWindow ? .stale : .old)
    }

    init(lastUpdated: Date, now: Date = Date()) { self.init(age: now.timeIntervalSince(lastUpdated)) }
}

/// What the panel says above the forecast: nothing while fresh, "offline" when the last refresh failed
/// (the numbers are the cached ones), otherwise just how old they are.
enum WeatherNotice: Equatable {
    case offline, stale

    init?(isLive: Bool, staleness: WeatherStaleness) {
        if !isLive { self = .offline } else if staleness != .fresh { self = .stale } else { return nil }
    }
}

/// One slot of the hourly strip: hour, glyph, temperature, and the rain chance only when it is worth a caption.
struct WeatherHourSlot: Equatable, Identifiable {
    let id: String
    let hour: String
    let symbolName: String
    let temperatureCelsius: Double
    let rainPercent: Int?
    let isNow: Bool

    /// The next `count` hours from the feed, richest source first (the 48-hour detail carries the rain
    /// chance and day/night art); the cached 3-day hourly list stands in. Never invents hours.
    static func slots(from state: WeatherState, count: Int) -> [WeatherHourSlot] {
        let points = state.detail?.hourly ?? []
        let made: [WeatherHourSlot]
        if !points.isEmpty {
            made = points.prefix(count).enumerated().map { i, p in
                let rain = Int(p.precipProbability.rounded())
                return WeatherHourSlot(id: p.time, hour: String(p.hourLabel.prefix(2)),
                                       symbolName: WeatherCondition(code: p.code).symbolName(isNight: !p.isDay),
                                       temperatureCelsius: p.temperature, rainPercent: rain > 0 ? rain : nil, isNow: i == 0)
            }
        } else {
            made = state.hourly.prefix(count).enumerated().map { i, h in
                WeatherHourSlot(id: h.id, hour: String(h.hour.prefix(2)), symbolName: h.symbolName,
                                temperatureCelsius: h.temperatureCelsius, rainPercent: nil, isNow: i == 0)
            }
        }
        return made
    }
}

/// Phase 56 W8, the Modern style: one accent per reading (the only colour on a flat graphite card)
/// and the hourly line as 0...1 heights, so the view draws a path and nothing else.
enum WeatherModernSpec {
    static func accent(condition: WeatherCondition, isNight: Bool) -> TileRGB {
        switch condition {
        case .clear, .partlyCloudy: return isNight ? TileRGB(r: 0.60, g: 0.65, b: 1.00) : TileRGB(r: 0.95, g: 0.72, b: 0.29)
        case .cloudy, .fog: return TileRGB(r: 0.70, g: 0.74, b: 0.79)
        case .drizzle, .rain, .showers: return TileRGB(r: 0.37, g: 0.66, b: 1.00)
        case .snow: return TileRGB(r: 0.78, g: 0.90, b: 1.00)
        case .thunderstorm: return TileRGB(r: 0.76, g: 0.55, b: 1.00)
        }
    }

    /// 0 = the coldest hour, 1 = the warmest; a flat run sits mid-height instead of dividing by zero.
    static func fractions(_ values: [Double]) -> [Double] {
        guard let lo = values.min(), let hi = values.max(), hi > lo else { return values.map { _ in 0.5 } }
        return values.map { ($0 - lo) / (hi - lo) }
    }
}

/// Phase 56 W10: the full-screen Glance page. Pure: how many columns the window gets, and the vibrant
/// flat-vector palette per sky. The view only turns these into `Color`s.
enum WeatherGlanceSpec {
    /// 3 = hero | 24h + days | (tiles below); 2 = hero over 24h, days beside; 1 = one stacked column.
    static func columns(forWidth width: Double) -> Int { width >= 1200 ? 3 : width >= 800 ? 2 : 1 }

    struct Palette: Equatable {
        let skyTop: TileRGB, skyBottom: TileRGB
        let hills: [TileRGB]   // farthest to nearest
        let accent: TileRGB
    }

    static func palette(condition: WeatherCondition, isNight: Bool) -> Palette {
        func c(_ hex: Int) -> TileRGB { TileRGB(r: Double(hex >> 16 & 255) / 255, g: Double(hex >> 8 & 255) / 255, b: Double(hex & 255) / 255) }
        if isNight && [.clear, .partlyCloudy].contains(condition) {
            return Palette(skyTop: c(0x10124A), skyBottom: c(0x3A2C8F), hills: [c(0x1B1B6B), c(0x14124F), c(0x0B0A33)], accent: c(0xE8E6FF))
        }
        switch condition {
        case .clear, .partlyCloudy:
            return Palette(skyTop: c(0xFF9F43), skyBottom: c(0xFFD166), hills: [c(0xB5179E), c(0x7209B7), c(0x4361EE)], accent: c(0xFFF3B0))
        case .cloudy, .fog:
            return Palette(skyTop: c(0x9AA5B1), skyBottom: c(0xCBD2D9), hills: [c(0x7B8794), c(0x616E7C), c(0x52606D)], accent: c(0xF5F7FA))
        case .drizzle, .rain, .showers:
            return Palette(skyTop: c(0x2B6CB0), skyBottom: c(0x63B3ED), hills: [c(0x1A4E8A), c(0x12396B), c(0x0C2A52)], accent: c(0xBEE3F8))
        case .snow:
            return Palette(skyTop: c(0x8FB8DE), skyBottom: c(0xE6F1FB), hills: [c(0xFFFFFF), c(0xCFE3F5), c(0xA9C9E6)], accent: c(0xFFFFFF))
        case .thunderstorm:
            return Palette(skyTop: c(0x2D1B69), skyBottom: c(0x6B3FA0), hills: [c(0x1E1250), c(0x150C3A), c(0x0D0827)], accent: c(0xFFE66D))
        }
    }
}
