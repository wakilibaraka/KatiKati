import XCTest
@testable import KatiKati

final class WeatherLocationsTests: XCTestCase {
    private func city(_ id: Int, lat: Double = 0, lon: Double = 0) -> SavedCity {
        SavedCity(id: id, name: "C\(id)", admin: "A", country: "K", latitude: lat + Double(id), longitude: lon + Double(id))
    }

    func testAddRespectsLimitAndDuplicates() {
        var s = SavedCities()
        for i in 1...5 { XCTAssertTrue(s.add(city(i))) }
        XCTAssertFalse(s.add(city(6)), "max \(SavedCities.limit)")
        s.remove(id: 3)
        XCTAssertFalse(s.add(city(1)), "same id")
        XCTAssertFalse(s.add(SavedCity(id: 99, name: "Near", admin: nil, country: nil, latitude: 1.001, longitude: 1.001)), "within ~1km of city 1")
        XCTAssertTrue(s.add(city(7)))
        XCTAssertEqual(s.cities.map(\.id), [1, 2, 4, 5, 7])
    }

    func testSelectionTokensAndResolution() {
        XCTAssertEqual(WeatherLocationSelection(token: nil), .current)
        XCTAssertEqual(WeatherLocationSelection(token: "city:42"), .city(42))
        XCTAssertEqual(WeatherLocationSelection(token: "city:x"), .current)
        XCTAssertEqual(WeatherLocationSelection.city(42).token, "city:42")
        var s = SavedCities(cities: [city(1), city(2)])
        XCTAssertEqual(s.resolved(.city(2)), .city(2))
        s.remove(id: 2)
        XCTAssertEqual(s.resolved(.city(2)), .city(1), "falls back to the first remaining city")
        s.remove(id: 1)
        XCTAssertEqual(s.resolved(.city(1)), .current)
    }

    func testSteppingWrapsThroughCurrentAndCities() {
        let s = SavedCities(cities: [city(1), city(2)])
        XCTAssertEqual(s.step(from: .current, by: 1), .city(1))
        XCTAssertEqual(s.step(from: .city(2), by: 1), .current)
        XCTAssertEqual(s.step(from: .current, by: -1), .city(2))
        XCTAssertEqual(SavedCities().step(from: .current, by: 1), .current)
    }

    func testGeocodingURLAndParse() throws {
        XCTAssertNil(WeatherGeocoding.searchURL(query: " a "))
        let url = try XCTUnwrap(WeatherGeocoding.searchURL(query: "New York"))
        XCTAssertTrue(url.absoluteString.contains("name=New%20York"))
        let json = """
        {"results":[{"id":5128581,"name":"New York","latitude":40.71,"longitude":-74.0,"country":"United States","admin1":"New York"},
                    {"id":1,"name":"Nowhere","latitude":1,"longitude":2}]}
        """.data(using: .utf8)!
        let cities = try WeatherGeocoding.parse(json)
        XCTAssertEqual(cities.count, 2)
        XCTAssertEqual(cities[0].subtitle, "New York, United States")
        XCTAssertEqual(cities[1].subtitle, "")
        XCTAssertEqual(try WeatherGeocoding.parse("{}".data(using: .utf8)!), [], "no results key = empty")
    }
}
