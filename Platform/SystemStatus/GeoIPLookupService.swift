import Foundation

struct GeoIPLocation: Equatable, Sendable {
    var city: String?
    var countryCode: String?
    var ip: String?

    var formattedPlace: String? {
        switch (city?.trimmingCharacters(in: .whitespacesAndNewlines), countryCode?.trimmingCharacters(in: .whitespacesAndNewlines)) {
        case let (c?, cc?) where !c.isEmpty && !cc.isEmpty:
            return "\(c), \(cc)"
        case let (c?, _) where !c.isEmpty:
            return c
        case let (_, cc?) where !cc.isEmpty:
            return cc
        default:
            return nil
        }
    }

    var flagEmoji: String? {
        guard let code = countryCode?.uppercased(), code.count == 2 else { return nil }
        let base: UInt32 = 127397
        var scalars = String.UnicodeScalarView()
        for scalar in code.unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90, let regional = UnicodeScalar(base + scalar.value) else {
                return nil
            }
            scalars.append(regional)
        }
        return String(scalars)
    }
}

/// Opt-in public IP geolocation lookup for the Dock II VPN card. Never runs unless explicitly enabled
/// and only called on VPN connection state transitions (debounced, never polled continuously).
enum GeoIPLookupService {
    private static let endpoint = URL(string: "https://ipapi.co/json/")!

    static func fetchCurrentLocation() async -> GeoIPLocation? {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 5
        request.setValue("KatiKati/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return GeoIPLocation(
            city: json["city"] as? String,
            countryCode: json["country_code"] as? String,
            ip: json["ip"] as? String
        )
    }
}
