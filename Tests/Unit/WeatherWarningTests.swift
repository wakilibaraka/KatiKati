import XCTest
@testable import KatiKati

final class WeatherWarningTests: XCTestCase {
    private func hour(_ i: Int, temp: Double = 15, apparent: Double? = nil, rain: Double = 0, wind: Double = 10,
                      gust: Double = 15, code: Int = 1, prob: Double = 0) -> WeatherHourPoint {
        WeatherHourPoint(time: "2026-10-11T\(String(format: "%02d", i)):00", temperature: temp, apparent: apparent ?? temp,
                         precipProbability: prob, precipitation: rain, snowfall: 0, humidity: 50, windSpeed: wind,
                         windGusts: gust, cloudCover: 10, code: code, isDay: true)
    }
    private func day(_ d: Int, snow: Double = 0, uv: Double = 3) -> WeatherDayPoint {
        WeatherDayPoint(date: "2026-10-\(11 + d)", code: 1, high: 20, low: 10, precipSum: 0, snowSum: snow,
                        precipProbabilityMax: 0, uvMax: uv, windMax: 10, gustMax: 15, sunrise: nil, sunset: nil)
    }
    private func detail(hours: [WeatherHourPoint] = [], days: [WeatherDayPoint] = []) -> WeatherDetail {
        WeatherDetail(latitude: 0, longitude: 0, apparent: 15, humidity: 50, pressure: 1010, windSpeed: 10, windGusts: 15,
                      windDirection: 0, cloudCover: 10, visibilityMeters: 10000, uvIndex: 3, precipitation: 0, dewPoint: 5,
                      hourly: hours, daily: days)
    }

    func testCalmWeatherHasNoWarnings() {
        XCTAssertTrue(WeatherWarningEngine.warnings(for: detail(hours: (0..<24).map { hour($0) }, days: [day(0), day(1)])).isEmpty)
    }

    func testHeatUsesFeelsLikeAndGrades() {
        let w = WeatherWarningEngine.warnings(for: detail(hours: [hour(12, temp: 33, apparent: 36), hour(13, temp: 34, apparent: 40)]))
        XCTAssertEqual(w.count, 1)
        XCTAssertEqual(w[0].kind, .heat)
        XCTAssertEqual(w[0].peak, 40)
        XCTAssertEqual(w[0].start, "2026-10-11T12:00")
        XCTAssertEqual(w[0].severity, .advisory) // 40/35 = 1.14 < 1.15
        XCTAssertEqual(WeatherWarningEngine.warnings(for: detail(hours: [hour(12, apparent: 42)])).first?.severity, .warning)
        XCTAssertEqual(WeatherWarningEngine.warnings(for: detail(hours: [hour(12, apparent: 50)])).first?.severity, .severe)
    }

    func testHeatBoundaryIsInclusiveAndAdvisoryJustAbove() {
        let at = WeatherWarningEngine.warnings(for: detail(hours: [hour(12, apparent: 35)]))
        XCTAssertEqual(at.first?.kind, .heat)
        XCTAssertEqual(at.first?.severity, .advisory)
        XCTAssertTrue(WeatherWarningEngine.warnings(for: detail(hours: [hour(12, apparent: 34.9)])).isEmpty)
    }

    func testFreezeEscalatesWithDepth() {
        XCTAssertEqual(WeatherWarningEngine.warnings(for: detail(hours: [hour(3, temp: -1)])).first?.severity, .advisory)
        XCTAssertEqual(WeatherWarningEngine.warnings(for: detail(hours: [hour(3, temp: -6)])).first?.severity, .warning)
        XCTAssertEqual(WeatherWarningEngine.warnings(for: detail(hours: [hour(3, temp: -12)])).first?.severity, .severe)
        XCTAssertTrue(WeatherWarningEngine.warnings(for: detail(hours: [hour(3, temp: 0.5)])).isEmpty)
    }

    func testHeavyRainWindAndThunderstorm() {
        let rain = WeatherWarningEngine.warnings(for: detail(hours: [hour(5, rain: 8)]))
        XCTAssertEqual(rain.map(\.kind), [.heavyRain])
        let wind = WeatherWarningEngine.warnings(for: detail(hours: [hour(5, wind: 20, gust: 90)]))
        XCTAssertEqual(wind.first?.kind, .wind)
        XCTAssertEqual(wind.first?.peak, 90)
        let storm = WeatherWarningEngine.warnings(for: detail(hours: [hour(5), hour(6, code: 95, prob: 60), hour(7, code: 99)]))
        XCTAssertEqual(storm.first?.kind, .thunderstorm)
        XCTAssertEqual(storm.first?.severity, .severe, "hail codes escalate")
        XCTAssertEqual(storm.first?.start, "2026-10-11T06:00")
    }

    func testSnowAndUVLookOnlyAtTheFirstThreeDays() {
        let w = WeatherWarningEngine.warnings(for: detail(days: [day(0), day(1, snow: 6), day(2, uv: 9), day(3, snow: 30, uv: 12)]))
        XCTAssertEqual(Set(w.map(\.kind)), [.snow, .uv])
        XCTAssertEqual(w.first { $0.kind == .snow }?.peak, 6)
        XCTAssertEqual(w.first { $0.kind == .uv }?.peak, 9)
    }

    func testCustomThresholdsAndOrdering() {
        var t = WeatherThresholds(); t.windKmh = 20
        let w = WeatherWarningEngine.warnings(for: detail(hours: [hour(1, temp: -12, wind: 25), hour(2, wind: 25)]), thresholds: t)
        XCTAssertEqual(w.map(\.kind), [.freeze, .wind], "severe freeze sorts before advisory wind")
        XCTAssertEqual(WeatherWarningKind.allCases.count, Set(WeatherWarningKind.allCases.map(\.symbolName)).count)
    }
}
