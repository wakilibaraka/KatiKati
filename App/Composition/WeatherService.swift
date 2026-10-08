import Foundation
import CoreLocation
import os.log

@MainActor
public final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published public private(set) var currentState: WeatherState = .empty

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
        super.init()

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

        let authStatus = locationManager.authorizationStatus
        if authStatus == .authorizedAlways  {
            isFetchingLocation = true
            locationManager.requestLocation()
        } else {
            await fetchWeather(latitude: 41.0082, longitude: 28.9784, city: "Istanbul")
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
            await self.fetchWeather(latitude: 41.0082, longitude: 28.9784, city: "Istanbul")
        }
    }

    private func fetchWeather(latitude: Double, longitude: Double, city: String) async {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current_weather=true&daily=temperature_2m_max,temperature_2m_min,weathercode&forecast_days=14&hourly=temperature_2m,weathercode&timezone=auto"
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
