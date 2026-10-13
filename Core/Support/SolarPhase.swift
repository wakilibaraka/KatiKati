import Foundation

/// Phase 10b-1 — where the sun is, as five steps. Pure (no clock reads, no AppKit): the caller passes `now`
/// and the day's sun times, so every boundary is unit-tested.
enum SolarPhase: String, CaseIterable, Sendable {
    case night, dawn, day, golden, dusk
}

/// One local day's sunrise/sunset, or the polar case where the sun doesn't cross the horizon.
struct SunTimes: Equatable, Sendable {
    enum Polar: Sendable { case day, night }
    var sunrise: Date?
    var sunset: Date?
    var polar: Polar?

    init(sunrise: Date?, sunset: Date?, polar: Polar? = nil) {
        self.sunrise = sunrise
        self.sunset = sunset
        self.polar = polar
    }
}

enum SolarPhaseResolver {
    static let dawnHalfWindow: TimeInterval = 30 * 60
    static let goldenLead: TimeInterval = 60 * 60
    static let duskLength: TimeInterval = 30 * 60

    /// Dawn = sunrise ±30 min · day · golden = last hour before sunset · dusk = 30 min after sunset · night.
    /// Missing times (and no polar flag) read as day by clock-free default only when `fallbackHourly` can't help,
    /// so callers should use `SunCalculator` to fill them in first.
    static func phase(at now: Date, times: SunTimes) -> SolarPhase {
        if let polar = times.polar { return polar == .day ? .day : .night }
        guard let rise = times.sunrise, let set = times.sunset, rise < set else { return .day }
        if now >= rise - dawnHalfWindow && now < rise + dawnHalfWindow { return .dawn }
        if now >= rise + dawnHalfWindow && now < set - goldenLead { return .day }
        if now >= set - goldenLead && now < set { return .golden }
        if now >= set && now < set + duskLength { return .dusk }
        return .night
    }

    /// The next instant the phase can change after `now` (for arming a single timer); the start of the next
    /// local day when none of today's boundaries is left, or at most a day away for polar cases.
    static func nextBoundary(after now: Date, times: SunTimes, calendar: Calendar = .current) -> Date {
        let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        guard times.polar == nil, let rise = times.sunrise, let set = times.sunset else { return nextDay }
        let edges = [rise - dawnHalfWindow, rise + dawnHalfWindow, set - goldenLead, set, set + duskLength]
        return edges.filter { $0 > now }.min().map { min($0, nextDay) } ?? nextDay
    }
}

/// NOAA / Wikipedia "sunrise equation" fallback when the weather feed has no sun times.
enum SunCalculator {
    /// Sunrise/sunset for the local day containing `date` at (`latitude`, `longitude` east-positive).
    static func times(on date: Date, latitude: Double, longitude: Double, calendar: Calendar = .current) -> SunTimes {
        let noon = calendar.startOfDay(for: date).addingTimeInterval(12 * 3600)
        let julian = noon.timeIntervalSince1970 / 86_400 + 2_440_587.5
        // Local noon → nearest whole day since J2000 noon (ceil would tip a noon reference into the next day).
        let n = (julian - 2_451_545.0).rounded()
        let meanSolarTime = n - longitude / 360
        let m = radians((357.5291 + 0.98560028 * meanSolarTime).truncatingRemainder(dividingBy: 360))
        let c = 1.9148 * sin(m) + 0.02 * sin(2 * m) + 0.0003 * sin(3 * m)
        let lambda = radians((degrees(m) + c + 180 + 102.9372).truncatingRemainder(dividingBy: 360))
        let transit = 2_451_545.0 + meanSolarTime + 0.0053 * sin(m) - 0.0069 * sin(2 * lambda)
        let sinDelta = sin(lambda) * sin(radians(23.4397))
        let cosDelta = cos(asin(sinDelta))
        let phi = radians(latitude)
        let cosOmega = (sin(radians(-0.833)) - sin(phi) * sinDelta) / (cos(phi) * cosDelta)
        if cosOmega > 1 { return SunTimes(sunrise: nil, sunset: nil, polar: .night) }
        if cosOmega < -1 { return SunTimes(sunrise: nil, sunset: nil, polar: .day) }
        let omega = degrees(acos(cosOmega))
        func fromJulian(_ jd: Double) -> Date { Date(timeIntervalSince1970: (jd - 2_440_587.5) * 86_400) }
        return SunTimes(sunrise: fromJulian(transit - omega / 360), sunset: fromJulian(transit + omega / 360))
    }

    private static func radians(_ d: Double) -> Double { d * .pi / 180 }
    private static func degrees(_ r: Double) -> Double { r * 180 / .pi }
}

extension WeatherState {
    /// Today's sun times: the feed's own sunrise/sunset, else the sunrise equation from the stored coordinates.
    func sunTimes(on date: Date = Date(), calendar: Calendar = .current) -> SunTimes? {
        if let parsed = SunTimes.parse(sunrise: detail?.sunrise, sunset: detail?.sunset, calendar: calendar) { return parsed }
        guard let latitude, let longitude else { return nil }
        return SunCalculator.times(on: date, latitude: latitude, longitude: longitude, calendar: calendar)
    }
}
