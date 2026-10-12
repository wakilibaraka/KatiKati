import Foundation

/// The last forecast for each place, kept on disk so weather still shows when the Mac is offline. Each file holds the full
/// response the tiles use (current, 48 hours, 16 days), so a week-old cache still has seven days of forecast to show.
/// A cache older than `maxAge` is treated as missing; one that is shown while offline is marked not live.
public struct WeatherCache {
    public static let maxAge: TimeInterval = 7 * 24 * 3600

    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public static var standard: WeatherCache {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return WeatherCache(directory: base.appendingPathComponent("KatiKati/Weather", isDirectory: true))
    }

    /// `current` or `city:123` -> a safe file name.
    static func fileName(forToken token: String) -> String {
        let safe = token.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }
        return String(safe) + ".json"
    }

    private func url(_ token: String) -> URL { directory.appendingPathComponent(Self.fileName(forToken: token)) }

    public func save(_ state: WeatherState, token: String) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url(token), options: .atomic)
    }

    /// The cached forecast for `token`, marked not live; nil if there is none, it is unreadable, or it is older than `maxAge`.
    public func load(token: String, now: Date = Date()) -> WeatherState? {
        guard let data = try? Data(contentsOf: url(token)),
              var state = try? JSONDecoder().decode(WeatherState.self, from: data),
              now.timeIntervalSince(state.lastUpdated) <= Self.maxAge else { return nil }
        state.isLive = false
        return state
    }
}
