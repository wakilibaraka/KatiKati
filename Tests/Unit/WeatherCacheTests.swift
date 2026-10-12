import XCTest
@testable import KatiKati

final class WeatherCacheTests: XCTestCase {
    private func makeCache() -> WeatherCache {
        WeatherCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent("wc-\(UUID().uuidString)"))
    }

    private func state(city: String, updated: Date) -> WeatherState {
        var s = WeatherState.empty
        s.cityName = city
        s.lastUpdated = updated
        s.isLive = true
        return s
    }

    func testSaveThenLoadReturnsTheForecastMarkedNotLive() {
        let cache = makeCache()
        let now = Date()
        cache.save(state(city: "Nairobi", updated: now), token: "current")
        let loaded = cache.load(token: "current", now: now)
        XCTAssertEqual(loaded?.cityName, "Nairobi")
        XCTAssertEqual(loaded?.isLive, false, "a cached forecast is never presented as live")
    }

    func testEachPlaceHasItsOwnCache() {
        let cache = makeCache()
        let now = Date()
        cache.save(state(city: "A", updated: now), token: "current")
        cache.save(state(city: "B", updated: now), token: "city:42")
        XCTAssertEqual(cache.load(token: "current", now: now)?.cityName, "A")
        XCTAssertEqual(cache.load(token: "city:42", now: now)?.cityName, "B")
        XCTAssertNil(cache.load(token: "city:7", now: now))
    }

    func testCacheExpiresAfterSevenDays() {
        let cache = makeCache()
        let saved = Date(timeIntervalSince1970: 1_800_000_000)
        cache.save(state(city: "A", updated: saved), token: "current")
        XCTAssertNotNil(cache.load(token: "current", now: saved.addingTimeInterval(6.9 * 86_400)))
        XCTAssertNil(cache.load(token: "current", now: saved.addingTimeInterval(7.1 * 86_400)))
    }

    func testCorruptFileIsIgnoredAndFileNamesAreSafe() throws {
        let cache = makeCache()
        try FileManager.default.createDirectory(at: cache.directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: cache.directory.appendingPathComponent(WeatherCache.fileName(forToken: "current")))
        XCTAssertNil(cache.load(token: "current"))
        XCTAssertEqual(WeatherCache.fileName(forToken: "city:42"), "city_42.json")
        XCTAssertEqual(WeatherCache.fileName(forToken: "../x"), "___x.json")
    }
}
