import XCTest
@testable import KatiKati

final class WeatherLayoutSpecTests: XCTestCase {
    func testEachSizeAppendsOneBand() {
        XCTAssertEqual(WeatherLayoutSpec.bands(for: .small), [.header])
        XCTAssertEqual(WeatherLayoutSpec.bands(for: .medium), [.header, .hourly])
        XCTAssertEqual(WeatherLayoutSpec.bands(for: .large), [.header, .hourly, .daily])
        XCTAssertEqual(WeatherLayoutSpec.bands(for: .large, panel: true), [.header, .hourly, .daily, .details])
        XCTAssertEqual(WeatherLayoutSpec.bands(for: .small, panel: true), [.header])
    }

    func testEffectsOffAtSmall() {
        XCTAssertFalse(WeatherLayoutSpec.showsEffects(for: .small))
        XCTAssertTrue(WeatherLayoutSpec.showsEffects(for: .medium))
    }

    func testRangeBarFractions() {
        let r = TemperatureRange(low: 5, high: 15, weekLow: 0, weekHigh: 20)
        XCTAssertEqual(r.start, 0.25, accuracy: 1e-9)
        XCTAssertEqual(r.end, 0.75, accuracy: 1e-9)
        let flat = TemperatureRange(low: 10, high: 10, weekLow: 10, weekHigh: 10)
        XCTAssertEqual([flat.start, flat.end], [0, 1])
        let out = TemperatureRange(low: -50, high: 90, weekLow: 0, weekHigh: 20)
        XCTAssertEqual([out.start, out.end], [0, 1])
    }

    func testMarkerStaysOnBar() {
        let r = TemperatureRange(low: 5, high: 15, weekLow: 0, weekHigh: 20)
        XCTAssertEqual(r.marker(current: 10, low: 5, high: 15), 0.5, accuracy: 1e-9)
        XCTAssertEqual(r.marker(current: 99, low: 5, high: 15), r.end, accuracy: 1e-9)
        XCTAssertEqual(r.marker(current: -9, low: 5, high: 15), r.start, accuracy: 1e-9)
    }

    func testNotice() {
        XCTAssertNil(WeatherNotice(isLive: true, staleness: .fresh))
        XCTAssertEqual(WeatherNotice(isLive: true, staleness: .stale), .stale)
        XCTAssertEqual(WeatherNotice(isLive: false, staleness: .fresh), .offline)
    }

    func testModernSpec() {
        XCTAssertEqual(WeatherModernSpec.fractions([10, 20, 15]), [0, 1, 0.5])
        XCTAssertEqual(WeatherModernSpec.fractions([7, 7]), [0.5, 0.5])
        XCTAssertTrue(WeatherModernSpec.fractions([]).isEmpty)
        XCTAssertNotEqual(WeatherModernSpec.accent(condition: .clear, isNight: false), WeatherModernSpec.accent(condition: .clear, isNight: true))
    }

    func testStaleness() {
        XCTAssertEqual(WeatherStaleness(age: 60), .fresh)
        XCTAssertEqual(WeatherStaleness(age: 2 * 3600), .stale)
        XCTAssertEqual(WeatherStaleness(age: 5 * 3600), .old)
    }

    func testHourSlotsPreferDetailAndNeverInvent() {
        func state(hourly: [HourlyForecast], detail: WeatherDetail?) -> WeatherState {
            WeatherState(cityName: "X", temperatureCelsius: 10, conditionText: "", symbolName: "sun.max.fill", highCelsius: 12, lowCelsius: 4,
                         hourly: hourly, daily: [], isLive: true, lastUpdated: Date(), detail: detail)
        }
        let cached = (0..<4).map { HourlyForecast(id: "h\($0)", hour: "\(14 + $0):00", temperatureCelsius: Double($0), symbolName: "cloud.fill") }
        let slots = WeatherHourSlot.slots(from: state(hourly: cached, detail: nil), count: 3)
        XCTAssertEqual(slots.map(\.hour), ["14", "15", "16"])
        XCTAssertEqual(slots.map(\.isNow), [true, false, false])
        XCTAssertNil(slots[0].rainPercent)
        XCTAssertTrue(WeatherHourSlot.slots(from: state(hourly: [], detail: nil), count: 5).isEmpty)
    }

    func testDetailBands() {
        XCTAssertEqual([0.0, 2.9, 3, 6, 8, 11].map { UVLevel(index: $0) }, [.low, .low, .moderate, .high, .veryHigh, .extreme])
        XCTAssertEqual(UVLevel.fraction(index: 22), 1)
        XCTAssertEqual(WeatherDetailBands.minutes("2026-10-11T06:41"), 401)
        XCTAssertNil(WeatherDetailBands.minutes("nope"))
        XCTAssertEqual(WeatherDetailBands.sunFraction(sunrise: "2026-10-11T06:00", sunset: "2026-10-11T18:00", nowMinutes: 12 * 60), 0.5)
        XCTAssertEqual(WeatherDetailBands.sunFraction(sunrise: "06:00", sunset: "18:00", nowMinutes: 23 * 60), 1)
        XCTAssertNil(WeatherDetailBands.sunFraction(sunrise: nil, sunset: "18:00", nowMinutes: 0))
        XCTAssertEqual([180, 300, 600].map { WeatherDetailBands.columns(forWidth: Double($0)) }, [1, 2, 3])
    }

    func testGlanceColumnsAndPalette() {
        XCTAssertEqual([1440, 1200, 900, 800, 700].map { WeatherGlanceSpec.columns(forWidth: $0) }, [3, 3, 2, 2, 1])
        let day = WeatherGlanceSpec.palette(condition: .clear, isNight: false)
        XCTAssertNotEqual(day, WeatherGlanceSpec.palette(condition: .clear, isNight: true))
        XCTAssertEqual(day.hills.count, 3)
        XCTAssertEqual(WeatherGlanceSpec.palette(condition: .rain, isNight: true), WeatherGlanceSpec.palette(condition: .showers, isNight: false))
    }

    func testFullScreenLayoutNamesAndMigration() {
        XCTAssertEqual(WeatherLayoutPreset.allCases.map(\.title), ["Overview", "Glance", "Classic"])
        XCTAssertEqual(WeatherLayoutPreset(rawValue: "glance"), .glance)
        let d = UserDefaults(suiteName: "weather-glance-migration-\(UUID().uuidString)")!
        d.set("classic", forKey: WeatherLayoutPreset.storageKey)
        WeatherLayoutPreset.migrateToFullScreenIfNeeded(defaults: d)
        XCTAssertEqual(d.string(forKey: WeatherLayoutPreset.storageKey), "fullScreen")
        d.set("classic", forKey: WeatherLayoutPreset.storageKey)
        WeatherLayoutPreset.migrateToFullScreenIfNeeded(defaults: d)
        XCTAssertEqual(d.string(forKey: WeatherLayoutPreset.storageKey), "classic")
        let fresh = UserDefaults(suiteName: "weather-glance-migration-\(UUID().uuidString)")!
        WeatherLayoutPreset.migrateToFullScreenIfNeeded(defaults: fresh)
        XCTAssertNil(fresh.string(forKey: WeatherLayoutPreset.storageKey))
    }
}
