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

    func testStaleness() {
        XCTAssertEqual(WeatherStaleness(age: 60), .fresh)
        XCTAssertEqual(WeatherStaleness(age: 2 * 3600), .stale)
        XCTAssertEqual(WeatherStaleness(age: 5 * 3600), .old)
    }
}
