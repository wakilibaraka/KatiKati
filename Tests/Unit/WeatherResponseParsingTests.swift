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

// MARK: - 5g-A extended payload

final class WeatherDetailTests: XCTestCase {
    private let fixture = """
    {
      "latitude": 40.99, "longitude": 28.97,
      "current_weather": {"temperature": 20.0, "weathercode": 61, "time": "2026-10-11T14:00", "is_day": 1},
      "current": {"relative_humidity_2m": 60, "apparent_temperature": 19.0, "precipitation": 0.4, "cloud_cover": 80,
                  "pressure_msl": 1012.5, "wind_speed_10m": 18, "wind_direction_10m": 200, "wind_gusts_10m": 35},
      "hourly": {
        "time": ["2026-10-11T13:00", "2026-10-11T14:00", "2026-10-11T15:00"],
        "temperature_2m": [19.0, 20.0, 21.0], "weathercode": [3, 61, 63],
        "apparent_temperature": [18.0, 19.0, 20.0], "precipitation_probability": [10, 55, 70],
        "precipitation": [0, 0.4, 1.2], "snowfall": [0, 0, 0], "relative_humidity_2m": [58, 60, 65],
        "wind_speed_10m": [15, 18, 20], "wind_gusts_10m": [30, 35, 40], "cloud_cover": [70, 80, 90],
        "visibility": [24000, 20000, 15000], "uv_index": [3, 2.5, 2], "is_day": [1, 1, 1]
      },
      "daily": {
        "time": ["2026-10-11", "2026-10-12"], "weathercode": [61, 3],
        "temperature_2m_max": [22, 20], "temperature_2m_min": [14, 13],
        "precipitation_sum": [3.5, 0], "snowfall_sum": [0, 0], "precipitation_probability_max": [70, 10],
        "uv_index_max": [4, 3], "wind_speed_10m_max": [25, 18], "wind_gusts_10m_max": [45, 30],
        "sunrise": ["2026-10-11T07:12", "2026-10-12T07:13"], "sunset": ["2026-10-11T18:22", "2026-10-12T18:20"]
      }
    }
    """.data(using: .utf8)!

    func testExtendedParseStartsAtTheCurrentHour() throws {
        let state = try WeatherResponseParsing.parse(data: fixture, cityName: "Istanbul", previousHourly: [])
        let d = try XCTUnwrap(state.detail)
        XCTAssertEqual(d.hourly.count, 2, "13:00 is before the current hour")
        XCTAssertEqual(d.hourly[0].time, "2026-10-11T14:00")
        XCTAssertEqual(d.hourly[0].hourLabel, "14:00")
        XCTAssertEqual(d.hourly[1].precipProbability, 70)
        XCTAssertEqual(d.apparent, 19.0)
        XCTAssertEqual(d.pressure, 1012.5)
        XCTAssertEqual(d.windDirection, 200)
        XCTAssertEqual(d.visibilityMeters, 20000)
        XCTAssertEqual(d.uvIndex, 2.5)
        XCTAssertEqual(d.daily.count, 2)
        XCTAssertEqual(d.sunrise, "2026-10-11T07:12")
        XCTAssertEqual(d.daily[0].gustMax, 45)
        XCTAssertEqual(d.latitude, 40.99)
    }

    func testNullDaysAtTheEndOfTheForecastDoNotBreakParsing() throws {
        // Open-Meteo returns null for the last, partial day; one null used to fail the whole forecast ("data is missing").
        let json = """
        {"latitude": 1, "longitude": 2,
         "current": {"time": "2026-10-11T14:15", "temperature_2m": 12.5, "weather_code": 3, "is_day": 1},
         "hourly": {"time": ["2026-10-11T14:00"], "temperature_2m": [12.5], "weathercode": [3]},
         "daily": {"time": ["2026-10-11", "2026-10-12", "2026-10-13"], "weathercode": [3, 61, null],
                   "temperature_2m_max": [15, 14, null], "temperature_2m_min": [8, 7, null],
                   "precipitation_sum": [0, 2, null], "uv_index_max": [3, 2, null]}}
        """.data(using: .utf8)!
        let state = try WeatherResponseParsing.parse(data: json, cityName: "Nairobi", previousHourly: [])
        XCTAssertEqual(state.detail?.daily.count, 2, "the incomplete day is dropped, the rest survive")
        XCTAssertEqual(state.daily.count, 2)
        XCTAssertEqual(state.highCelsius, 15)
    }

    func testNewStyleCurrentBlockAloneIsEnough() throws {
        let json = """
        {"latitude": 1, "longitude": 2,
         "current": {"time": "2026-10-11T14:15", "temperature_2m": 12.5, "weather_code": 71, "is_day": 0,
                     "relative_humidity_2m": 80, "apparent_temperature": 10},
         "hourly": {"time": ["2026-10-11T14:00"], "temperature_2m": [12.5], "weathercode": [71]}}
        """.data(using: .utf8)!
        let state = try WeatherResponseParsing.parse(data: json, cityName: "Oslo", previousHourly: [])
        XCTAssertEqual(state.temperatureCelsius, 12.5)
        XCTAssertEqual(state.conditionFamily, .snow)
        XCTAssertTrue(state.isNight)
        XCTAssertEqual(state.detail?.humidity, 80)
    }

    func testLegacyPayloadHasNoDetailAndOldCacheStillDecodes() throws {
        let legacy = """
        {"current_weather": {"temperature": 15.5, "weathercode": 3, "time": "2026-10-08T10:00"},
         "hourly": {"time": ["2026-10-08T10:00"], "temperature_2m": [15.5], "weathercode": [3]}}
        """.data(using: .utf8)!
        XCTAssertNil(try WeatherResponseParsing.parse(data: legacy, cityName: "X", previousHourly: []).detail)

        let oldCache = """
        {"cityName":"Old","temperatureCelsius":10,"conditionText":"Rain","symbolName":"cloud.rain.fill",
         "highCelsius":12,"lowCelsius":6,"hourly":[],"daily":[],"isLive":false,"lastUpdated":0}
        """.data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(WeatherState.self, from: oldCache).detail)
    }

    func testStateWithDetailRoundTripsThroughTheCache() throws {
        let state = try WeatherResponseParsing.parse(data: fixture, cityName: "Istanbul", previousHourly: [])
        let back = try JSONDecoder().decode(WeatherState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(back.detail, state.detail)
    }

    func testForecastURLAsksForEverythingTheTilesNeed() {
        let url = WeatherRequest.forecastURL(latitude: 1, longitude: 2)
        for key in ["apparent_temperature", "precipitation_probability", "snowfall", "uv_index", "visibility",
                    "wind_gusts_10m", "current=temperature_2m,weather_code,is_day", "sunrise", "sunset", "forecast_days=16", "forecast_hours=48", "timezone=auto"] {
            XCTAssertTrue(url.contains(key), key)
        }
        XCTAssertFalse(url.contains("current_weather"), "current_weather=true suppresses the `current` block")
        XCTAssertNotNil(URL(string: url))
    }

    func testUnitConversions() {
        XCTAssertEqual(TemperatureUnit.fahrenheit.convert(100), 212, accuracy: 0.001)
        XCTAssertEqual(WeatherUnits.degrees(-0.4, .celsius), "0°")
        XCTAssertEqual(WeatherUnits.degrees(21.6, .fahrenheit), "71°")
        XCTAssertEqual(WindSpeedUnit.mph.convert(kmh: 100), 62.1371, accuracy: 0.001)
        XCTAssertEqual(WindSpeedUnit.ms.convert(kmh: 36), 10, accuracy: 0.001)
        XCTAssertEqual(WeatherUnits.wind(36, .ms), "10 m/s")
    }

    func testCompassAndDewPoint() {
        XCTAssertEqual(WeatherUnits.compass(0), "N")
        XCTAssertEqual(WeatherUnits.compass(359), "N")
        XCTAssertEqual(WeatherUnits.compass(200), "S")
        XCTAssertEqual(WeatherUnits.compass(-90), "W")
        XCTAssertEqual(WeatherUnits.dewPoint(temperature: 20, humidity: 100), 20, accuracy: 0.05)
        XCTAssertEqual(WeatherUnits.dewPoint(temperature: 20, humidity: 50), 9.3, accuracy: 0.2)
    }

    func testMoonPhaseAnchors() {
        let newMoon = Date(timeIntervalSince1970: 947_182_440)
        XCTAssertEqual(MoonPhase.fraction(at: newMoon), 0, accuracy: 0.001)
        XCTAssertEqual(MoonPhase.illumination(at: newMoon), 0, accuracy: 0.001)
        let full = newMoon.addingTimeInterval(14.765 * 86_400)
        XCTAssertEqual(MoonPhase.illumination(at: full), 1, accuracy: 0.01)
        XCTAssertEqual(MoonPhase.symbolName(at: full), "moonphase.full.moon")
        XCTAssertEqual(MoonPhase.symbolName(at: newMoon), "moonphase.new.moon")
    }
}
