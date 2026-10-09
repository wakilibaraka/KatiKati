import Foundation

/// 4d: the condition *family* behind a WMO weather code — what picks the widget's gradient and
/// illustration. Separate from the localized `conditionText` (that stays the translated label).
public enum WeatherCondition: String, Codable, Sendable, CaseIterable {
    case clear
    case partlyCloudy
    case cloudy
    case fog
    case drizzle
    case rain
    case snow
    case showers
    case thunderstorm

    public init(code: Int) {
        switch code {
        case 0, 1: self = .clear
        case 2: self = .partlyCloudy
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 51, 53, 55: self = .drizzle
        case 61, 63, 65: self = .rain
        case 71, 73, 75: self = .snow
        case 80, 81, 82: self = .showers
        case 95, 96, 99: self = .thunderstorm
        default: self = .cloudy
        }
    }

    /// Legacy cached states predate the stored `condition`; recover the family from the SF Symbol
    /// the old payload carries, so an old cache still themes correctly instead of falling apart.
    public init(symbolName: String) {
        switch symbolName {
        case "sun.max.fill": self = .clear
        case "cloud.sun.fill": self = .partlyCloudy
        case "cloud.fog.fill": self = .fog
        case "cloud.drizzle.fill": self = .drizzle
        case "cloud.rain.fill": self = .rain
        case "cloud.snow.fill": self = .snow
        case "cloud.heavyrain.fill": self = .showers
        case "cloud.bolt.rain.fill": self = .thunderstorm
        default: self = .cloudy
        }
    }
}

public struct HourlyForecast: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let hour: String // e.g. "14:00"
    public let temperatureCelsius: Double
    public let symbolName: String
}

public struct DailyForecast: Codable, Equatable, Sendable, Identifiable {
    public var id: String { date }
    public let date: String // e.g. "2026-10-08"
    public let highCelsius: Double
    public let lowCelsius: Double
    public let symbolName: String
}

public struct WeatherState: Codable, Equatable, Sendable {
    public var cityName: String
    public var temperatureCelsius: Double
    public var conditionText: String
    public var symbolName: String
    public var highCelsius: Double
    public var lowCelsius: Double
    public var hourly: [HourlyForecast]
    public var daily: [DailyForecast]
    public var isLive: Bool
    public var lastUpdated: Date
    /// 4d: condition family + day/night, both optional so a cache written before 4d still decodes
    /// (the computed fallbacks below recover them from `symbolName`).
    public var condition: WeatherCondition?
    public var isDay: Bool?

    /// Always resolves: stored value, else inferred from the legacy symbol, else `.cloudy`.
    public var conditionFamily: WeatherCondition {
        condition ?? WeatherCondition(symbolName: symbolName)
    }
    /// Unknown day/night reads as day (the pre-4d payload only ever drew day symbols).
    public var isNight: Bool { isDay == false }

    public init(
        cityName: String,
        temperatureCelsius: Double,
        conditionText: String,
        symbolName: String,
        highCelsius: Double,
        lowCelsius: Double,
        hourly: [HourlyForecast],
        daily: [DailyForecast],
        isLive: Bool,
        lastUpdated: Date,
        condition: WeatherCondition? = nil,
        isDay: Bool? = nil
    ) {
        self.cityName = cityName
        self.temperatureCelsius = temperatureCelsius
        self.conditionText = conditionText
        self.symbolName = symbolName
        self.highCelsius = highCelsius
        self.lowCelsius = lowCelsius
        self.hourly = hourly
        self.daily = daily
        self.isLive = isLive
        self.lastUpdated = lastUpdated
        self.condition = condition
        self.isDay = isDay
    }

    public static let empty = WeatherState(
        cityName: "Loading...",
        temperatureCelsius: 0,
        conditionText: "...",
        symbolName: "cloud.fill",
        highCelsius: 0,
        lowCelsius: 0,
        hourly: [],
        daily: [],
        isLive: false,
        lastUpdated: Date()
    )
}
