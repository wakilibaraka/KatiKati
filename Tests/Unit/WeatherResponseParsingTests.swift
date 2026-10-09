import XCTest
@testable import KatiKati

final class WeatherResponseParsingTests: XCTestCase {
    func testMapWeatherCode() {
        let clear = WeatherResponseParsing.mapWeatherCode(code: 0)
        XCTAssertEqual(clear.text, "Clear sky")
        XCTAssertEqual(clear.symbol, "sun.max.fill")

        let rain = WeatherResponseParsing.mapWeatherCode(code: 61)
        XCTAssertEqual(rain.text, "Rain")
        XCTAssertEqual(rain.symbol, "cloud.rain.fill")
    }

    func testParseValidJSON() throws {
        let json = """
        {
            "current_weather": {
                "temperature": 15.5,
                "weathercode": 3,
                "time": "2026-10-08T10:00"
            },
            "daily": {
                "time": ["2026-10-08", "2026-10-09"],
                "weathercode": [3, 61],
                "temperature_2m_max": [18.0, 16.0],
                "temperature_2m_min": [10.0, 12.0]
            },
            "hourly": {
                "time": ["2026-10-08T10:00", "2026-10-08T11:00"],
                "temperature_2m": [15.5, 16.0],
                "weathercode": [3, 3]
            }
        }
        """.data(using: .utf8)!

        let state = try WeatherResponseParsing.parse(data: json, cityName: "London", previousHourly: [])
        XCTAssertEqual(state.cityName, "London")
        XCTAssertEqual(state.temperatureCelsius, 15.5)
        XCTAssertEqual(state.conditionText, "Overcast")
        XCTAssertEqual(state.symbolName, "cloud.fill")
        XCTAssertEqual(state.highCelsius, 18.0)
        XCTAssertEqual(state.lowCelsius, 10.0)

        XCTAssertEqual(state.hourly.count, 2)
        XCTAssertEqual(state.hourly[0].hour, "10:00")
        XCTAssertEqual(state.hourly[0].temperatureCelsius, 15.5)

        XCTAssertEqual(state.daily.count, 2)
        XCTAssertEqual(state.daily[1].date, "2026-10-09")
        XCTAssertEqual(state.daily[1].highCelsius, 16.0)
        XCTAssertEqual(state.daily[1].symbolName, "cloud.rain.fill")
    }

    // MARK: - 4d: condition family + day/night

    func testConditionFamilyMapping() {
        XCTAssertEqual(WeatherCondition(code: 0), .clear)
        XCTAssertEqual(WeatherCondition(code: 1), .clear)
        XCTAssertEqual(WeatherCondition(code: 2), .partlyCloudy)
        XCTAssertEqual(WeatherCondition(code: 3), .cloudy)
        XCTAssertEqual(WeatherCondition(code: 45), .fog)
        XCTAssertEqual(WeatherCondition(code: 48), .fog)
        XCTAssertEqual(WeatherCondition(code: 53), .drizzle)
        XCTAssertEqual(WeatherCondition(code: 63), .rain)
        XCTAssertEqual(WeatherCondition(code: 73), .snow)
        XCTAssertEqual(WeatherCondition(code: 81), .showers)
        XCTAssertEqual(WeatherCondition(code: 95), .thunderstorm)
        XCTAssertEqual(WeatherCondition(code: 999), .cloudy, "unknown code must not crash the widget")

        // Legacy payloads carry only the SF Symbol: the family has to come back from it.
        XCTAssertEqual(WeatherCondition(symbolName: "sun.max.fill"), .clear)
        XCTAssertEqual(WeatherCondition(symbolName: "cloud.sun.fill"), .partlyCloudy)
        XCTAssertEqual(WeatherCondition(symbolName: "cloud.bolt.rain.fill"), .thunderstorm)
        XCTAssertEqual(WeatherCondition(symbolName: "anything.else"), .cloudy)
    }

    func testParseCapturesNightAndLabelsIt() throws {
        let json = """
        {
            "current_weather": {
                "temperature": 22.0,
                "weathercode": 3,
                "time": "2026-09-22T23:00",
                "is_day": 0
            }
        }
        """.data(using: .utf8)!

        let state = try WeatherResponseParsing.parse(data: json, cityName: "Paris", previousHourly: [])
        XCTAssertEqual(state.condition, .cloudy)
        XCTAssertEqual(state.isDay, false)
        XCTAssertTrue(state.isNight)
        XCTAssertEqual(state.conditionFamily, .cloudy)
        XCTAssertEqual(state.conditionText, "Cloudy Night")
    }

    func testParseDayKeepsThePlainConditionLabel() throws {
        let json = """
        {
            "current_weather": {
                "temperature": 25.0,
                "weathercode": 0,
                "time": "2026-09-21T14:00",
                "is_day": 1
            }
        }
        """.data(using: .utf8)!

        let state = try WeatherResponseParsing.parse(data: json, cityName: "San Francisco", previousHourly: [])
        XCTAssertEqual(state.condition, .clear)
        XCTAssertEqual(state.isDay, true)
        XCTAssertFalse(state.isNight)
        XCTAssertEqual(state.conditionText, "Clear sky")
    }

    /// The disk cache survives the 4d shape change: a payload written before `condition`/`isDay`
    /// existed still decodes, and the family is recovered from the old symbol instead of
    /// dropping the whole cached reading.
    func testLegacyCacheWithoutConditionStillDecodes() throws {
        let current = WeatherState(cityName: "Istanbul", temperatureCelsius: 21.0,
                                   conditionText: "Partly cloudy", symbolName: "cloud.sun.fill",
                                   highCelsius: 24.0, lowCelsius: 17.0,
                                   hourly: [], daily: [], isLive: true, lastUpdated: Date(),
                                   condition: .partlyCloudy, isDay: true)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as! [String: Any]
        object.removeValue(forKey: "condition")
        object.removeValue(forKey: "isDay")

        let legacy = try JSONDecoder().decode(WeatherState.self,
                                              from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.condition)
        XCTAssertNil(legacy.isDay)
        XCTAssertEqual(legacy.conditionFamily, .partlyCloudy, "recovered from cloud.sun.fill")
        XCTAssertFalse(legacy.isNight, "a pre-4d payload only ever drew day art")
        XCTAssertEqual(legacy.cityName, "Istanbul")
    }
}
