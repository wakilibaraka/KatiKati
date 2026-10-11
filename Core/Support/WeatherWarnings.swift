import Foundation

// Phase 5g-C — forecast-derived warnings. Open-Meteo carries no official alerts, so these are
// computed from the next 48h / 16 days against user thresholds and are always labelled
// "forecast-based". Pure and unit-tested.

public struct WeatherThresholds: Codable, Equatable, Sendable {
    public var heatFeelsLikeC = 35.0
    public var freezeC = 0.0
    public var heavyRainMmPerHour = 7.5
    public var snowCmPerDay = 5.0
    public var windKmh = 50.0
    public var gustKmh = 75.0
    public var uvIndex = 8.0

    public static let `default` = WeatherThresholds()
    public static let storageKey = "com.katikati.weather.thresholds"
    public init() {}
}

public enum WeatherWarningKind: String, CaseIterable, Codable, Sendable {
    case heat, freeze, heavyRain, snow, wind, thunderstorm, uv

    public var symbolName: String {
        switch self {
        case .heat: return "thermometer.sun.fill"
        case .freeze: return "thermometer.snowflake"
        case .heavyRain: return "cloud.heavyrain.fill"
        case .snow: return "snowflake"
        case .wind: return "wind"
        case .thunderstorm: return "cloud.bolt.rain.fill"
        case .uv: return "sun.max.trianglebadge.exclamationmark.fill"
        }
    }
}

public enum WeatherWarningSeverity: Int, Comparable, Codable, Sendable {
    case advisory = 0, warning = 1, severe = 2
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public struct WeatherWarning: Equatable, Identifiable, Sendable {
    public var id: String { kind.rawValue }
    public let kind: WeatherWarningKind
    public let severity: WeatherWarningSeverity
    /// Peak value that triggered it, in the kind's natural metric unit (°C, mm/h, cm, km/h, UV).
    public let peak: Double
    /// Location-local start of the first offending hour/day (`2026-10-11T14:00` or `2026-10-12`).
    public let start: String
}

public enum WeatherWarningEngine {
    /// Warnings for `detail`, most severe first. Hourly rules look at the 48h window, daily rules
    /// (snow, UV) at the first three days.
    public static func warnings(for detail: WeatherDetail, thresholds t: WeatherThresholds = .default) -> [WeatherWarning] {
        var out: [WeatherWarning] = []

        func firstPeak(_ hours: [WeatherHourPoint], value: (WeatherHourPoint) -> Double, over limit: Double, below: Bool = false) -> (Double, String)? {
            let hits = hours.filter { below ? value($0) <= limit : value($0) >= limit }
            guard let first = hits.first else { return nil }
            let peak = below ? hits.map(value).min()! : hits.map(value).max()!
            return (peak, first.time)
        }
        func grade(_ ratio: Double) -> WeatherWarningSeverity { ratio >= 1.4 ? .severe : (ratio >= 1.15 ? .warning : .advisory) }

        if let (peak, at) = firstPeak(detail.hourly, value: { $0.apparent }, over: t.heatFeelsLikeC) {
            out.append(.init(kind: .heat, severity: grade(peak / t.heatFeelsLikeC), peak: peak, start: at))
        }
        if let (peak, at) = firstPeak(detail.hourly, value: { $0.temperature }, over: t.freezeC, below: true) {
            // Colder than the threshold by 5°/10° escalates.
            let depth = t.freezeC - peak
            out.append(.init(kind: .freeze, severity: depth >= 10 ? .severe : (depth >= 5 ? .warning : .advisory), peak: peak, start: at))
        }
        if let (peak, at) = firstPeak(detail.hourly, value: { $0.precipitation }, over: t.heavyRainMmPerHour) {
            out.append(.init(kind: .heavyRain, severity: grade(peak / t.heavyRainMmPerHour), peak: peak, start: at))
        }
        if let (peak, at) = firstPeak(detail.hourly, value: { max($0.windSpeed / t.windKmh, $0.windGusts / t.gustKmh) }, over: 1) {
            let hour = detail.hourly.first { $0.time == at }
            out.append(.init(kind: .wind, severity: grade(peak), peak: max(hour?.windGusts ?? 0, hour?.windSpeed ?? 0), start: at))
        }
        if let storm = detail.hourly.first(where: { [95, 96, 99].contains($0.code) }) {
            let hail = detail.hourly.contains { [96, 99].contains($0.code) }
            out.append(.init(kind: .thunderstorm, severity: hail ? .severe : .warning, peak: storm.precipProbability, start: storm.time))
        }
        let nearDays = Array(detail.daily.prefix(3))
        if let day = nearDays.first(where: { $0.snowSum >= t.snowCmPerDay }) {
            let peak = nearDays.map(\.snowSum).max() ?? day.snowSum
            out.append(.init(kind: .snow, severity: grade(peak / t.snowCmPerDay), peak: peak, start: day.date))
        }
        if let day = nearDays.first(where: { $0.uvMax >= t.uvIndex }) {
            let peak = nearDays.map(\.uvMax).max() ?? day.uvMax
            out.append(.init(kind: .uv, severity: peak >= 11 ? .severe : .advisory, peak: peak, start: day.date))
        }
        return out.sorted { $0.severity != $1.severity ? $0.severity > $1.severity : $0.kind.rawValue < $1.kind.rawValue }
    }
}
