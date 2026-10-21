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
