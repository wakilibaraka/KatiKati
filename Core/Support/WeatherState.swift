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

extension DailyForecast {
    /// The API's `date` is a calendar day (`"2026-10-15"`), never a label to print: the medium and large
    /// weather widgets printed it verbatim at 9 pt, so three columns in a 230 pt chip truncated it to
    /// `"2026-…"` (Phase 40a). Anything that is not that shape — the `"Today"` / `"Tomorrow"` / `"Later"`
    /// fallbacks the chip builds when live data is missing — passes through unchanged.
    ///
    /// The stored field is deliberately left alone: it is cached, and a cache written before this change
    /// must still decode.
    func weekdayLabel(locale: Locale = .current, calendar: Calendar = .current) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.calendar = calendar
        parser.timeZone = calendar.timeZone
        parser.dateFormat = "yyyy-MM-dd"
        guard let day = parser.date(from: date) else { return date }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: day)
    }
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
    /// 5g: rich payload for the weather tiles; nil for caches written before 5g.
    public var detail: WeatherDetail?
    /// 10: where the forecast is for, so sun times can be computed when the feed has none. Nil for older caches.
    public var latitude: Double?
    public var longitude: Double?

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
        isDay: Bool? = nil,
        detail: WeatherDetail? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
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
        self.detail = detail
        self.latitude = latitude
        self.longitude = longitude
    }

    public static let defaultRome = WeatherState(
        cityName: "Rome",
        temperatureCelsius: 26,
        conditionText: "Clear",
        symbolName: "sun.max.fill",
        highCelsius: 30,
        lowCelsius: 18,
        hourly: [],
        daily: [
            DailyForecast(date: "Thu", highCelsius: 30, lowCelsius: 20, symbolName: "cloud.rain.fill"),
            DailyForecast(date: "Fri", highCelsius: 30, lowCelsius: 21, symbolName: "cloud.rain.fill"),
            DailyForecast(date: "Sat", highCelsius: 30, lowCelsius: 19, symbolName: "cloud.rain.fill")
        ],
        isLive: false,
        lastUpdated: Date(),
        condition: .clear,
        isDay: true,
        latitude: 41.8933,
        longitude: 12.4829
    )

    public var threeDayForecast: [DailyForecast] {
        if daily.count >= 3 {
            return Array(daily.prefix(3))
        }
        return Self.defaultRome.daily
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
