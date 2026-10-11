import Foundation
import CoreLocation
import os.log

@MainActor
public final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published public private(set) var currentState: WeatherState = .empty
    /// 5g-B: saved cities (≤5) and which place the panel/pill show. `.current` = device location.
    @Published public private(set) var savedCities: SavedCities
    @Published public private(set) var selection: WeatherLocationSelection
    /// True when there is no usable location at all (current denied/failed and no saved city):
    /// the tiles show the city search instead of a made-up default city.
    @Published public private(set) var needsLocation = false

    private let logger = Logger(subsystem: "com.katikati.app", category: "WeatherService")
    private var refreshTimer: Timer?
    private let cacheURL: URL?

    private let locationManager = CLLocationManager()
    private var geocoder = CLGeocoder()
    private var isFetchingLocation = false

    public var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: "com.katikati.weather.enabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "com.katikati.weather.enabled")
    }

    public init(cacheURL: URL? = nil) {
        self.cacheURL = cacheURL
        let defaults = UserDefaults.standard
        savedCities = defaults.data(forKey: SavedCities.storageKey)
            .flatMap { try? JSONDecoder().decode(SavedCities.self, from: $0) } ?? SavedCities()
        selection = WeatherLocationSelection(token: defaults.string(forKey: SavedCities.selectionKey))
        super.init()
        selection = savedCities.resolved(selection)

        if let cacheURL = cacheURL,
           let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode(WeatherState.self, from: data) {
            var staleState = cached
            staleState.isLive = false
            self.currentState = staleState
        }

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer

        if isEnabled {
            Task {
                await self.refresh()
            }
            startPeriodicUpdates()
        }
    }

    public func stopPeriodicUpdates() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    public func startPeriodicUpdates() {
        stopPeriodicUpdates()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 900.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    public func refresh() async {
        guard isEnabled else { return }

        switch savedCities.resolved(selection) {
        case .city(let id):
            guard let city = savedCities.city(id: id) else { return }
            needsLocation = false
            await fetchWeather(latitude: city.latitude, longitude: city.longitude, city: city.name)
        case .current:
            switch locationManager.authorizationStatus {
            case .authorizedAlways:
                needsLocation = false
                isFetchingLocation = true
                locationManager.requestLocation()
            case .notDetermined:
                locationManager.requestAlwaysAuthorization()
            default:
                fallBackFromCurrentLocation()
            }
        }
    }

    /// Current location is unavailable: use the first saved city, else ask the user to search.
    private func fallBackFromCurrentLocation() {
        if let first = savedCities.cities.first {
            select(.city(first.id))
        } else {
            needsLocation = true
        }
    }

    // MARK: Saved cities

    public func select(_ new: WeatherLocationSelection) {
        let resolved = savedCities.resolved(new)
        guard resolved != selection || needsLocation else { return }
        selection = resolved
        UserDefaults.standard.set(resolved.token, forKey: SavedCities.selectionKey)
        Task { await refresh() }
    }

    public func step(by delta: Int) { select(savedCities.step(from: selection, by: delta)) }

    @discardableResult
    public func addCity(_ city: SavedCity) -> Bool {
        var next = savedCities
        guard next.add(city) else { return false }
        savedCities = next
        persistCities()
        select(.city(city.id))
        return true
    }

    public func removeCity(id: Int) {
        var next = savedCities
        next.remove(id: id)
        savedCities = next
        persistCities()
        let resolved = next.resolved(selection)
        if resolved != selection { select(resolved) }
    }

    private func persistCities() {
        if let data = try? JSONEncoder().encode(savedCities) { UserDefaults.standard.set(data, forKey: SavedCities.storageKey) }
    }

    /// Open-Meteo geocoding search; empty on any failure or a too-short query.
    public func searchCities(_ query: String) async -> [SavedCity] {
        guard let url = WeatherGeocoding.searchURL(query: query, language: Locale.current.languageCode ?? "en") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try WeatherGeocoding.parse(data)
        } catch {
            logger.warning("City search failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self, self.selection == .current else { return }
            await self.refresh()
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard isFetchingLocation, let location = locations.last else { return }
            isFetchingLocation = false

            let lat = location.coordinate.latitude
            let lon = location.coordinate.longitude

            geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
                let city = placemarks?.first?.locality ?? "Local"
                Task { @MainActor [weak self] in
                    await self?.fetchWeather(latitude: lat, longitude: lon, city: city)
                }
            }
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isFetchingLocation = false
            self.logger.warning("Location manager failed: \(error.localizedDescription, privacy: .public)")
            self.fallBackFromCurrentLocation()
        }
    }

    private func fetchWeather(latitude: Double, longitude: Double, city: String) async {
        let urlString = WeatherRequest.forecastURL(latitude: latitude, longitude: longitude)
        guard let url = URL(string: urlString) else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                logger.error("Weather request failed: \(response, privacy: .public)")
                return
            }

            let newState = try WeatherResponseParsing.parse(data: data, cityName: city, previousHourly: currentState.hourly)
            self.currentState = newState

            if let cacheURL = cacheURL {
                if let encoded = try? JSONEncoder().encode(newState) {
                    try? encoded.write(to: cacheURL, options: .atomic)
                }
            }
        } catch {
            logger.warning("Weather refresh failed: \(error.localizedDescription, privacy: .public)")
            // Offline = last cached + stale marker
            var staleState = currentState
            staleState.isLive = false
            self.currentState = staleState
        }
    }
}
