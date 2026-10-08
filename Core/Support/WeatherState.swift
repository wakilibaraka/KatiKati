import Foundation

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
        lastUpdated: Date
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
