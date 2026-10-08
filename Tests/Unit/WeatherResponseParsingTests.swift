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
}
