import Foundation

// Phase 5g-B — saved cities, the current-location selection and the Open-Meteo geocoding client's
// pure request/response layer. Persistence and networking live in `WeatherService`.

public struct SavedCity: Codable, Equatable, Identifiable, Sendable {
    public let id: Int          // Open-Meteo geoname id
    public let name: String
    public let admin: String?
    public let country: String?
    public let latitude: Double
    public let longitude: Double

    public var subtitle: String { [admin, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ") }
}

public enum WeatherLocationSelection: Equatable, Sendable {
    case current
    case city(Int)

    public var token: String {
        switch self { case .current: return "current"; case .city(let id): return "city:\(id)" }
    }
    public init(token: String?) {
        if let t = token, t.hasPrefix("city:"), let id = Int(t.dropFirst(5)) { self = .city(id) } else { self = .current }
    }
}

public struct SavedCities: Codable, Equatable, Sendable {
    public static let limit = 5
    public static let storageKey = "com.katikati.weather.cities"
    public static let selectionKey = "com.katikati.weather.selection"

    public private(set) var cities: [SavedCity] = []
    public init(cities: [SavedCity] = []) { self.cities = Array(cities.prefix(Self.limit)) }

    /// Adds `city` unless it is a duplicate (same id, or within ~1 km) or the list is full.
    @discardableResult
    public mutating func add(_ city: SavedCity) -> Bool {
        guard cities.count < Self.limit else { return false }
        let near = cities.contains {
            $0.id == city.id || (abs($0.latitude - city.latitude) < 0.01 && abs($0.longitude - city.longitude) < 0.01)
        }
        guard !near else { return false }
        cities.append(city)
        return true
    }

    public mutating func remove(id: Int) { cities.removeAll { $0.id == id } }

    public func city(id: Int) -> SavedCity? { cities.first { $0.id == id } }

    /// A selection that still points somewhere: a removed city falls back to the first remaining
    /// city, else to current location.
    public func resolved(_ selection: WeatherLocationSelection) -> WeatherLocationSelection {
        guard case .city(let id) = selection, city(id: id) == nil else { return selection }
        return cities.first.map { .city($0.id) } ?? .current
    }

    /// The next selection when stepping through "current location, city 1, city 2, …" with wrap-around.
    public func step(from selection: WeatherLocationSelection, by delta: Int) -> WeatherLocationSelection {
        let all: [WeatherLocationSelection] = [.current] + cities.map { .city($0.id) }
        let i = all.firstIndex(of: resolved(selection)) ?? 0
        return all[((i + delta) % all.count + all.count) % all.count]
    }
}

public enum WeatherGeocoding {
    public static func searchURL(query: String, language: String = "en", count: Int = 8) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        c?.queryItems = [
            .init(name: "name", value: trimmed), .init(name: "count", value: String(count)),
            .init(name: "language", value: language), .init(name: "format", value: "json"),
        ]
        return c?.url
    }

    private struct Response: Decodable {
        struct Result: Decodable {
            let id: Int; let name: String; let latitude: Double; let longitude: Double
            let country: String?; let admin1: String?
        }
        let results: [Result]?
    }

    public static func parse(_ data: Data) throws -> [SavedCity] {
        try JSONDecoder().decode(Response.self, from: data).results?.map {
            SavedCity(id: $0.id, name: $0.name, admin: $0.admin1, country: $0.country, latitude: $0.latitude, longitude: $0.longitude)
        } ?? []
    }
}
