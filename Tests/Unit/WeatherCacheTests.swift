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

    func testAsyncCacheAndRefreshPolicyAndWeekdayFormatting() async {
        let cache = makeCache()
        let now = Date()
        cache.saveAsync(state(city: "Kampala", updated: now), token: "city:9")
        var loaded: WeatherState?
        for _ in 0..<20 {
            loaded = await cache.loadAsync(token: "city:9", now: now)
            if loaded != nil { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(loaded?.cityName, "Kampala")

        XCTAssertTrue(WeatherRefreshPolicy.shouldCommitForecast(requestedToken: "city:9", activeToken: "city:9"))
        XCTAssertFalse(WeatherRefreshPolicy.shouldCommitForecast(requestedToken: "current", activeToken: "city:9"))

        XCTAssertNil(WeatherRefreshPolicy.scrubHourIndex(x: 0, width: 240, count: 24))
        XCTAssertEqual(WeatherRefreshPolicy.scrubHourIndex(x: 240, width: 240, count: 24), 23)
        XCTAssertNil(WeatherRefreshPolicy.scrubHourIndex(x: 50, width: 240, count: 1))

        let daily = DailyForecast(date: "2026-10-15", highCelsius: 25, lowCelsius: 15, symbolName: "sun.max.fill")
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let first = daily.weekdayLabel(locale: Locale(identifier: "en_US_POSIX"), calendar: utc)
        let second = daily.weekdayLabel(locale: Locale(identifier: "en_US_POSIX"), calendar: utc)
        XCTAssertEqual(first, "Thu")
        XCTAssertEqual(second, "Thu")
        XCTAssertEqual(WeatherRefreshPolicy.utcWeekday(from: "2026-10-15"), "Thu")
    }
}
