import Foundation

// Phase 5g-A — the rich Open-Meteo payload behind the weather tiles. Stored in metric units
// (°C, km/h, mm, cm, hPa, m); `WeatherUnits` converts for display. Everything is optional-safe
// so a cache written before 5g still decodes (`WeatherState.detail` is optional).

public struct WeatherHourPoint: Codable, Equatable, Sendable, Identifiable {
    public var id: String { time }
    public let time: String            // "2026-10-11T14:00" (location-local)
    public let temperature: Double
    public let apparent: Double
    public let precipProbability: Double
    public let precipitation: Double   // mm
    public let snowfall: Double        // cm
    public let humidity: Double
    public let windSpeed: Double       // km/h
    public let windGusts: Double
    public let cloudCover: Double
    public let code: Int
    public let isDay: Bool

    public var hourLabel: String { String(time.split(separator: "T").last ?? "") }
}

public struct WeatherDayPoint: Codable, Equatable, Sendable, Identifiable {
    public var id: String { date }
    public let date: String            // "2026-10-11"
    public let code: Int
    public let high: Double
    public let low: Double
    public let precipSum: Double
    public let snowSum: Double
    public let precipProbabilityMax: Double
    public let uvMax: Double
    public let windMax: Double
    public let gustMax: Double
    public let sunrise: String?        // "2026-10-11T06:41"
    public let sunset: String?
}

public struct WeatherDetail: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var apparent: Double
    public var humidity: Double
    public var pressure: Double
    public var windSpeed: Double
    public var windGusts: Double
    public var windDirection: Double
    public var cloudCover: Double
    public var visibilityMeters: Double
    public var uvIndex: Double
    public var precipitation: Double
    public var dewPoint: Double
    public var hourly: [WeatherHourPoint]   // up to 48, starting at the current hour
    public var daily: [WeatherDayPoint]     // up to 16, starting today

    public var sunrise: String? { daily.first?.sunrise }
    public var sunset: String? { daily.first?.sunset }
}

// MARK: - Units

public enum TemperatureUnit: String, CaseIterable, Codable, Sendable {
    case celsius, fahrenheit
    public func convert(_ celsius: Double) -> Double { self == .celsius ? celsius : celsius * 9 / 5 + 32 }
    public var symbol: String { self == .celsius ? "°C" : "°F" }
}

public enum WindSpeedUnit: String, CaseIterable, Codable, Sendable {
    case kmh, mph, ms
    public func convert(kmh: Double) -> Double {
        switch self {
        case .kmh: return kmh
        case .mph: return kmh * 0.621371
        case .ms: return kmh / 3.6
        }
    }
    public var symbol: String {
        switch self { case .kmh: return "km/h"; case .mph: return "mph"; case .ms: return "m/s" }
    }
}

public enum WeatherUnits {
    public static let temperatureKey = "com.katikati.weather.temperatureUnit"
    public static let windKey = "com.katikati.weather.windUnit"

    /// `22°` / `72°` — whole degrees, unit symbol omitted (the tiles show the scale once).
    public static func degrees(_ celsius: Double, _ unit: TemperatureUnit) -> String {
        "\(Int(unit.convert(celsius).rounded()))°"
    }

    public static func wind(_ kmh: Double, _ unit: WindSpeedUnit) -> String {
        "\(Int(unit.convert(kmh: kmh).rounded())) \(unit.symbol)"
    }

    /// Eight-point compass label for a "direction the wind comes from" in degrees.
    public static func compass(_ degrees: Double) -> String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return names[Int((normalized + 22.5) / 45) % 8]
    }

    /// Magnus-formula dew point (°C) from temperature (°C) and relative humidity (%).
    public static func dewPoint(temperature t: Double, humidity rh: Double) -> Double {
        let a = 17.62, b = 243.12
        let gamma = log(max(rh, 1) / 100) + a * t / (b + t)
        return b * gamma / (a - gamma)
    }
}

// MARK: - Moon

public enum MoonPhase {
    /// Fraction of the synodic cycle: 0 = new moon, 0.5 = full, back to 1 = new.
    public static func fraction(at date: Date) -> Double {
        let synodic = 29.530588853
        let knownNew = 947_182_440.0 // 2000-01-06 18:14 UTC
        let days = (date.timeIntervalSince1970 - knownNew) / 86_400
        let f = (days / synodic).truncatingRemainder(dividingBy: 1)
        return f < 0 ? f + 1 : f
    }

    /// 0…1 lit fraction of the disc.
    public static func illumination(at date: Date) -> Double {
        (1 - cos(fraction(at: date) * 2 * .pi)) / 2
    }

    public static func symbolName(at date: Date) -> String {
        switch Int((fraction(at: date) * 8).rounded()) % 8 {
        case 0: return "moonphase.new.moon"
        case 1: return "moonphase.waxing.crescent"
        case 2: return "moonphase.first.quarter"
        case 3: return "moonphase.waxing.gibbous"
        case 4: return "moonphase.full.moon"
        case 5: return "moonphase.waning.gibbous"
        case 6: return "moonphase.last.quarter"
        default: return "moonphase.waning.crescent"
        }
    }
}

// MARK: - Request

public enum WeatherRequest {
    /// Forecast URL with every field the tiles need (one call: current, 48h hourly, 16-day daily).
    public static func forecastURL(latitude: Double, longitude: Double) -> String {
        let current = "temperature_2m,weather_code,is_day,relative_humidity_2m,apparent_temperature,precipitation,cloud_cover,pressure_msl,wind_speed_10m,wind_direction_10m,wind_gusts_10m"
        let hourly = "temperature_2m,weathercode,apparent_temperature,precipitation_probability,precipitation,snowfall,relative_humidity_2m,wind_speed_10m,wind_gusts_10m,cloud_cover,visibility,uv_index,is_day"
        let daily = "weathercode,temperature_2m_max,temperature_2m_min,precipitation_sum,snowfall_sum,precipitation_probability_max,uv_index_max,wind_speed_10m_max,wind_gusts_10m_max,sunrise,sunset"
        return "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current=\(current)&hourly=\(hourly)&daily=\(daily)&forecast_days=16&forecast_hours=48&timezone=auto"
    }
}
