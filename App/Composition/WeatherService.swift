import AppKit
import Foundation
import CoreLocation
import os.log

@MainActor
public final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @MainActor public static let shared = WeatherService()
    @Published public private(set) var currentState: WeatherState = .empty
    /// 5g-B: saved cities (≤5) and which place the panel/pill show. `.current` = device location.
    @Published public private(set) var savedCities: SavedCities
    @Published public private(set) var selection: WeatherLocationSelection
    @Published public private(set) var carouselConfig: WeatherCarouselConfig
    @Published public private(set) var cachedStatesByToken: [String: WeatherState] = [:]
    /// True when there is no usable location at all (current denied/failed and no saved city):
    /// the tiles show the city search instead of a made-up default city.
    @Published public private(set) var needsLocation = false

    private let logger = Logger(subsystem: "com.katikati.app", category: "WeatherService")
    private var refreshTimer: Timer?
    private var configObserver: NSObjectProtocol?
    private let cache: WeatherCache?
    /// Where the app stands on Location Services, so the panel can offer the right button.
    @Published public private(set) var locationStatus: CLAuthorizationStatus = .notDetermined

    private let locationManager = CLLocationManager()
    private var geocoder = CLGeocoder()
    private var isFetchingLocation = false

    public var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: "com.katikati.weather.enabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "com.katikati.weather.enabled")
    }

    public init(cache: WeatherCache? = .standard) {
        self.cache = cache
        let defaults = UserDefaults.standard
        savedCities = defaults.data(forKey: SavedCities.storageKey)
            .flatMap { try? JSONDecoder().decode(SavedCities.self, from: $0) } ?? SavedCities()
        selection = WeatherLocationSelection(token: defaults.string(forKey: SavedCities.selectionKey))
        carouselConfig = WeatherCarouselConfig.decode(defaults.data(forKey: WeatherCarouselConfig.defaultsKey)) ?? .default
        super.init()
        selection = savedCities.resolved(selection)
        seedCachedStates()
        configObserver = NotificationCenter.default.addObserver(
            forName: .weatherCarouselConfigDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reloadCarouselFromDefaults() }
        }

        // Offline from the first frame: show the last forecast for this place until a fresh one arrives.
        // With no cache the state stays empty (the chips draw their "add a city" state) — a made-up
        // city's numbers are never shown as the user's weather.
        if let cached = cache?.load(token: selection.token) {
            self.currentState = cached
        } else {
            self.currentState = .empty
        }
        locationStatus = locationManager.authorizationStatus

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
            default:
                // Defer prompting off launch/periodic background refreshes; user-initiated Weather
                // actions trigger `requestLocationAccess()` explicitly.
                fallBackFromCurrentLocation()
            }
        }
        await prefetchPinnedCities()
    }

    public func reloadCarouselFromDefaults() {
        let d = UserDefaults.standard
        savedCities = d.data(forKey: SavedCities.storageKey)
            .flatMap { try? JSONDecoder().decode(SavedCities.self, from: $0) } ?? savedCities
        carouselConfig = WeatherCarouselConfig.decode(d.data(forKey: WeatherCarouselConfig.defaultsKey)) ?? .default
        seedCachedStates()
        Task { await prefetchPinnedCities() }
    }

    private func seedCachedStates() {
        var map: [String: WeatherState] = [:]
        if let cur = cache?.load(token: WeatherLocationSelection.current.token) {
            map[WeatherLocationSelection.current.token] = cur
        }
        for city in savedCities.cities {
            let token = WeatherLocationSelection.city(city.id).token
            if let st = cache?.load(token: token) { map[token] = st }
        }
        cachedStatesByToken = map
    }

    private func prefetchPinnedCities() async {
        let activeToken = savedCities.resolved(selection).token
        let pinnedTokens = carouselConfig.pinnedLocationTokens.isEmpty
            ? savedCities.cities.prefix(WeatherCarouselConfig.maxPinnedLocations).map { WeatherLocationSelection.city($0.id).token }
            : carouselConfig.pinnedLocationTokens
        for token in pinnedTokens where token != activeToken {
            if let existing = cachedStatesByToken[token], Date().timeIntervalSince(existing.lastUpdated) < 900 {
                continue
            }
            if case .city(let cid) = WeatherLocationSelection(token: token), let city = savedCities.city(id: cid) {
                guard let url = URL(string: WeatherRequest.forecastURL(latitude: city.latitude, longitude: city.longitude)) else { continue }
                if let (data, resp) = try? await URLSession.shared.data(from: url),
                   (resp as? HTTPURLResponse)?.statusCode == 200,
                   var parsed = try? WeatherResponseParsing.parse(data: data, cityName: city.name, previousHourly: cachedStatesByToken[token]?.hourly ?? []) {
                    parsed.latitude = city.latitude
                    parsed.longitude = city.longitude
                    cachedStatesByToken[token] = parsed
                    cache?.save(parsed, token: token)
                }
            }
        }
    }

    /// Asks macOS for Location Services access (the system prompt), or — if it was already refused — opens the Privacy pane,
    /// because a refused request cannot be asked again.
    public func requestLocationAccess() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            NSApp.activate(ignoringOtherApps: true)   // an accessory app's prompt can stay hidden behind other windows
            locationManager.requestAlwaysAuthorization()
        case .denied, .restricted:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                NSWorkspace.shared.open(url)
            }
        default:
            Task { await refresh() }
        }
    }

    /// Current location is unavailable: use the first saved city; with none, ask for a place instead of
    /// fetching a forecast for a city the user never chose.
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
        if let cached = cache?.load(token: resolved.token) { currentState = cached }   // usable at once, even offline
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
            guard let self else { return }
            self.locationStatus = manager.authorizationStatus
            guard self.selection == .current else { return }
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
                showCachedForecast()
                return
            }

            var newState = try WeatherResponseParsing.parse(data: data, cityName: city, previousHourly: currentState.hourly)
            newState.latitude = latitude
            newState.longitude = longitude
            let activeToken = savedCities.resolved(selection).token
            self.currentState = newState
            self.cachedStatesByToken[activeToken] = newState
            cache?.save(newState, token: activeToken)
        } catch {
            logger.warning("Weather refresh failed: \(error.localizedDescription, privacy: .public)")
            showCachedForecast()
        }
    }

    /// Offline or the request failed: keep showing the newest forecast we have for this place, marked not live.
    private func showCachedForecast() {
        let cached = cache?.load(token: savedCities.resolved(selection).token)
        if let cached, currentState.detail == nil || cached.lastUpdated >= currentState.lastUpdated {
            currentState = cached
        } else {
            var stale = currentState
            stale.isLive = false
            currentState = stale
        }
    }
}
