import Foundation

/// Pure maths behind the panel's detail bands (UV pill, sun arc, rain chart, reflow columns).
enum UVLevel: Equatable {
    case low, moderate, high, veryHigh, extreme

    init(index: Double) {
        switch index {
        case ..<3: self = .low
        case ..<6: self = .moderate
        case ..<8: self = .high
        case ..<11: self = .veryHigh
        default: self = .extreme
        }
    }

    /// Marker position on the 0...11+ track.
    static func fraction(index: Double) -> Double { min(max(index / 11, 0), 1) }
}

enum WeatherDetailBands {
    /// Minutes since midnight of an Open-Meteo local time ("2026-10-11T06:41" or "06:41").
    static func minutes(_ iso: String?) -> Int? {
        guard let clock = iso?.split(separator: "T").last else { return nil }
        let parts = clock.split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }

    /// Sun position along the day: 0 at sunrise, 1 at sunset, clamped (the dot rests on the horizon at night).
    static func sunFraction(sunrise: String?, sunset: String?, nowMinutes: Int) -> Double? {
        guard let rise = minutes(sunrise), let set = minutes(sunset), set > rise else { return nil }
        return min(max(Double(nowMinutes - rise) / Double(set - rise), 0), 1)
    }

    /// 1 column on a narrow panel, 2 by default, 3 on a wide one.
    static func columns(forWidth width: Double) -> Int { width < 220 ? 1 : (width < 420 ? 2 : 3) }
}
