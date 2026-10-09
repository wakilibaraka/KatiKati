import Foundation

public struct OpenMeteoResponse: Decodable {
    public let current_weather: CurrentWeather?
    public let daily: Daily?
    public let hourly: Hourly?

    public struct CurrentWeather: Decodable {
        public let temperature: Double
        public let weathercode: Int
        public let time: String
        /// 1 = day, 0 = night. Optional: absent on older/cached payloads.
        public let is_day: Int?
    }
    public struct Daily: Decodable {
        public let time: [String]?
        public let weathercode: [Int]?
        public let temperature_2m_max: [Double]
        public let temperature_2m_min: [Double]
    }
    public struct Hourly: Decodable {
        public let time: [String]
        public let temperature_2m: [Double]
        public let weathercode: [Int]
    }
}

public enum WeatherResponseParsing {
    public static func mapWeatherCode(code: Int) -> (text: String, symbol: String) {
        switch code {
        case 0:
            return (String(localized: "Clear sky"), "sun.max.fill")
        case 1:
            return (String(localized: "Mainly clear"), "sun.max.fill")
        case 2:
            return (String(localized: "Partly cloudy"), "cloud.sun.fill")
        case 3:
            return (String(localized: "Overcast"), "cloud.fill")
        case 45, 48:
            return (String(localized: "Fog"), "cloud.fog.fill")
        case 51, 53, 55:
            return (String(localized: "Drizzle"), "cloud.drizzle.fill")
        case 61, 63, 65:
            return (String(localized: "Rain"), "cloud.rain.fill")
        case 71, 73, 75:
            return (String(localized: "Snow"), "cloud.snow.fill")
        case 80, 81, 82:
            return (String(localized: "Showers"), "cloud.heavyrain.fill")
        case 95, 96, 99:
            return (String(localized: "Thunderstorm"), "cloud.bolt.rain.fill")
        default:
            return (String(localized: "Cloudy"), "cloud.fill")
        }
    }

    public static func parse(data: Data, cityName: String, previousHourly: [HourlyForecast]) throws -> WeatherState {
        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        guard let current = decoded.current_weather else {
            throw NSError(domain: "WeatherResponseParsing", code: 1, userInfo: [NSLocalizedDescriptionKey: "No current_weather in response"])
        }

        let condition = mapWeatherCode(code: current.weathercode)
        let family = WeatherCondition(code: current.weathercode)
        let isDay = current.is_day.map { $0 == 1 }
        // The sample label for a cloudy night (owner reference, 4d): night keeps the plain
        // condition text for everything else — one extra key to translate, not ten.
        let nightCloudy = isDay == false && (family == .partlyCloudy || family == .cloudy)
        let labelText = nightCloudy ? String(localized: "Cloudy Night") : condition.text
        let high = decoded.daily?.temperature_2m_max.first ?? (current.temperature + 3.0)
        let low = decoded.daily?.temperature_2m_min.first ?? (current.temperature - 4.0)

        var hourlyList: [HourlyForecast] = []
        if let hourly = decoded.hourly {
            let availableCount = min(hourly.time.count, hourly.temperature_2m.count)
            let currentHourPrefix = String(current.time.prefix(13))
            let startIndex = hourly.time.prefix(availableCount).firstIndex { $0 >= currentHourPrefix } ?? 0
            let endIndex = min(startIndex + 6, availableCount)
            for i in startIndex..<endIndex {
                let fullTime = hourly.time[i]
                let hourString = fullTime.components(separatedBy: "T").last ?? fullTime
                let code = hourly.weathercode.indices.contains(i) ? hourly.weathercode[i] : current.weathercode
                let symbol = mapWeatherCode(code: code).symbol
                hourlyList.append(
                    HourlyForecast(
                        id: "hourly_\(i)_\(hourString)",
                        hour: hourString,
                        temperatureCelsius: hourly.temperature_2m[i],
                        symbolName: symbol
                    )
                )
            }
        }

        let forecasts = buildDailyForecasts(from: decoded.daily)

        return WeatherState(
            cityName: cityName,
            temperatureCelsius: current.temperature,
            conditionText: labelText,
            symbolName: condition.symbol,
            highCelsius: high,
            lowCelsius: low,
            hourly: hourlyList.isEmpty ? previousHourly : hourlyList,
            daily: forecasts,
            isLive: true,
            lastUpdated: Date(),
            condition: family,
            isDay: isDay
        )
    }

    private static func buildDailyForecasts(from daily: OpenMeteoResponse.Daily?) -> [DailyForecast] {
        guard let daily = daily else { return [] }
        let count = min(daily.temperature_2m_max.count, min(daily.temperature_2m_min.count, 14))
        var forecasts: [DailyForecast] = []
        for index in 0..<count {
            let code = daily.weathercode?.indices.contains(index) == true ? daily.weathercode![index] : 2
            let date = daily.time?.indices.contains(index) == true ? daily.time![index] : "day-\(index)"
            forecasts.append(
                DailyForecast(
                    date: date,
                    highCelsius: daily.temperature_2m_max[index],
                    lowCelsius: daily.temperature_2m_min[index],
                    symbolName: mapWeatherCode(code: code).symbol
                )
            )
        }
        return forecasts
    }
}
