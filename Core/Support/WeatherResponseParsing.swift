import Foundation

public struct OpenMeteoResponse: Decodable {
    public let current_weather: CurrentWeather?
    public let daily: Daily?
    public let hourly: Hourly?
    public let current: Current?
    public let latitude: Double?
    public let longitude: Double?

    /// 5g: the richer `current` block (all optional — absent on legacy/cached payloads).
    public struct Current: Decodable {
        public let time: String?
        public let temperature_2m: Double?
        public let weather_code: Int?
        public let is_day: Int?
        public let relative_humidity_2m: Double?
        public let apparent_temperature: Double?
        public let precipitation: Double?
        public let cloud_cover: Double?
        public let pressure_msl: Double?
        public let wind_speed_10m: Double?
        public let wind_direction_10m: Double?
        public let wind_gusts_10m: Double?
    }

    public struct CurrentWeather: Decodable {
        public let temperature: Double
        public let weathercode: Int
        public let time: String
        /// 1 = day, 0 = night. Optional: absent on older/cached payloads.
        public let is_day: Int?
    }
    public struct Daily: Decodable {
        public let time: [String]?
        /// The API returns `null` for the last (partial) forecast day, so the day values are optional and incomplete days are skipped.
        public let weathercode: [Int?]?
        public let temperature_2m_max: [Double?]
        public let temperature_2m_min: [Double?]
        public let precipitation_sum: [Double?]?
        public let snowfall_sum: [Double?]?
        public let precipitation_probability_max: [Double?]?
        public let uv_index_max: [Double?]?
        public let wind_speed_10m_max: [Double?]?
        public let wind_gusts_10m_max: [Double?]?
        public let sunrise: [String?]?
        public let sunset: [String?]?
    }
    public struct Hourly: Decodable {
        public let time: [String]
        public let temperature_2m: [Double]
        public let weathercode: [Int]
        public let apparent_temperature: [Double?]?
        public let precipitation_probability: [Double?]?
        public let precipitation: [Double?]?
        public let snowfall: [Double?]?
        public let relative_humidity_2m: [Double?]?
        public let wind_speed_10m: [Double?]?
        public let wind_gusts_10m: [Double?]?
        public let cloud_cover: [Double?]?
        public let visibility: [Double?]?
        public let uv_index: [Double?]?
        public let is_day: [Int?]?
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
        // Open-Meteo drops the `current` block when `current_weather=true` is also sent, so the live
        // request uses `current=` only; the legacy block is still accepted (old payloads, fixtures).
        let synthesized: OpenMeteoResponse.CurrentWeather? = decoded.current.flatMap { c in
            guard let t = c.temperature_2m, let code = c.weather_code, let time = c.time else { return nil }
            return OpenMeteoResponse.CurrentWeather(temperature: t, weathercode: code, time: time, is_day: c.is_day)
        }
        guard let current = decoded.current_weather ?? synthesized else {
            throw NSError(domain: "WeatherResponseParsing", code: 1, userInfo: [NSLocalizedDescriptionKey: "No current_weather in response"])
        }

        let condition = mapWeatherCode(code: current.weathercode)
        let family = WeatherCondition(code: current.weathercode)
        let isDay = current.is_day.map { $0 == 1 }
        // The sample label for a cloudy night (owner reference, 4d): night keeps the plain
        // condition text for everything else — one extra key to translate, not ten.
        let nightCloudy = isDay == false && (family == .partlyCloudy || family == .cloudy)
        let labelText = nightCloudy ? String(localized: "Cloudy Night") : condition.text
        let high = decoded.daily?.temperature_2m_max.first.flatMap { $0 } ?? (current.temperature + 3.0)
        let low = decoded.daily?.temperature_2m_min.first.flatMap { $0 } ?? (current.temperature - 4.0)

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
            isDay: isDay,
            detail: buildDetail(from: decoded, current: current)
        )
    }

    /// Builds the 5g tile payload; nil when the response carries none of the extended fields.
    static func buildDetail(from r: OpenMeteoResponse, current: OpenMeteoResponse.CurrentWeather) -> WeatherDetail? {
        guard let hourly = r.hourly, !hourly.time.isEmpty, r.current != nil || hourly.apparent_temperature != nil else { return nil }
        func at(_ a: [Double?]?, _ i: Int) -> Double { (a?.indices.contains(i) == true ? a?[i] : nil) ?? 0 }
        let prefix = String(current.time.prefix(13))
        let start = hourly.time.firstIndex { $0 >= prefix } ?? 0
        let end = min(start + 48, hourly.time.count)
        guard start < end else { return nil }
        let points: [WeatherHourPoint] = (start..<end).map { i in
            WeatherHourPoint(
                time: hourly.time[i],
                temperature: hourly.temperature_2m.indices.contains(i) ? hourly.temperature_2m[i] : 0,
                apparent: at(hourly.apparent_temperature, i),
                precipProbability: at(hourly.precipitation_probability, i),
                precipitation: at(hourly.precipitation, i),
                snowfall: at(hourly.snowfall, i),
                humidity: at(hourly.relative_humidity_2m, i),
                windSpeed: at(hourly.wind_speed_10m, i),
                windGusts: at(hourly.wind_gusts_10m, i),
                cloudCover: at(hourly.cloud_cover, i),
                code: hourly.weathercode.indices.contains(i) ? hourly.weathercode[i] : 0,
                isDay: (hourly.is_day?.indices.contains(i) == true ? hourly.is_day?[i] : nil).map { $0 == 1 } ?? true
            )
        }
        var days: [WeatherDayPoint] = []
        if let d = r.daily {
            let n = min(d.temperature_2m_max.count, d.temperature_2m_min.count, 16)
            for i in 0..<n {
                guard let high = d.temperature_2m_max[i], let low = d.temperature_2m_min[i] else { continue }   // incomplete day
                days.append(WeatherDayPoint(
                    date: d.time?.indices.contains(i) == true ? d.time![i] : "day-\(i)",
                    code: (d.weathercode?.indices.contains(i) == true ? d.weathercode![i] : nil) ?? 2,
                    high: high, low: low,
                    precipSum: at(d.precipitation_sum, i), snowSum: at(d.snowfall_sum, i),
                    precipProbabilityMax: at(d.precipitation_probability_max, i),
                    uvMax: at(d.uv_index_max, i), windMax: at(d.wind_speed_10m_max, i), gustMax: at(d.wind_gusts_10m_max, i),
                    sunrise: d.sunrise?.indices.contains(i) == true ? d.sunrise![i] : nil,
                    sunset: d.sunset?.indices.contains(i) == true ? d.sunset![i] : nil
                ))
            }
        }
        let now = points[0]
        let c = r.current
        let humidity = c?.relative_humidity_2m ?? now.humidity
        return WeatherDetail(
            latitude: r.latitude ?? 0, longitude: r.longitude ?? 0,
            apparent: c?.apparent_temperature ?? now.apparent,
            humidity: humidity,
            pressure: c?.pressure_msl ?? 0,
            windSpeed: c?.wind_speed_10m ?? now.windSpeed,
            windGusts: c?.wind_gusts_10m ?? now.windGusts,
            windDirection: c?.wind_direction_10m ?? 0,
            cloudCover: c?.cloud_cover ?? now.cloudCover,
            visibilityMeters: at(hourly.visibility, start),
            uvIndex: at(hourly.uv_index, start),
            precipitation: c?.precipitation ?? now.precipitation,
            dewPoint: WeatherUnits.dewPoint(temperature: current.temperature, humidity: humidity),
            hourly: points, daily: days
        )
    }

    private static func buildDailyForecasts(from daily: OpenMeteoResponse.Daily?) -> [DailyForecast] {
        guard let daily = daily else { return [] }
        let count = min(daily.temperature_2m_max.count, min(daily.temperature_2m_min.count, 14))
        var forecasts: [DailyForecast] = []
        for index in 0..<count {
            guard let high = daily.temperature_2m_max[index], let low = daily.temperature_2m_min[index] else { continue }
            let code = (daily.weathercode?.indices.contains(index) == true ? daily.weathercode![index] : nil) ?? 2
            let date = daily.time?.indices.contains(index) == true ? daily.time![index] : "day-\(index)"
            forecasts.append(
                DailyForecast(
                    date: date,
                    highCelsius: high,
                    lowCelsius: low,
                    symbolName: mapWeatherCode(code: code).symbol
                )
            )
        }
        return forecasts
    }
}
