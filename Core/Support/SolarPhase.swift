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

// MARK: - DW-1 · the six-step daylight ladder a dynamic wallpaper paints

/// The dynamic wallpaper's own ladder — finer than `SolarPhase`, which only picks a pack file. It splits
/// the day into a dawn ramp, a morning ramp, a noon plateau (the whole afternoon), the golden hour, dusk
/// and night, so a renderer can blend *through* a phase instead of snapping at each pack boundary.
enum DaylightPhase: String, CaseIterable, Sendable {
    case night, dawn, morning, noon, goldenHour, dusk

    /// The built-in pack face this ladder step draws from (the pack predates the ladder).
    var solarPhase: SolarPhase {
        switch self {
        case .night: return .night
        case .dawn: return .dawn
        case .morning, .noon: return .day
        case .goldenHour: return .golden
        case .dusk: return .dusk
        }
    }
}

/// One instant's place on the ladder: which step, how far through it (`0…1`, for blending), where the sun
/// is (`-1` nadir … `1` zenith) and how bright the sky reads (`0…1`). Pure — every boundary is `times`.
struct DaylightSample: Equatable, Sendable {
    var phase: DaylightPhase
    var progress: Double
    var altitude: Double
    var luminance: Double
}

enum SolarDaylightEvaluator {
    static let dawnHalfWindow: TimeInterval = 30 * 60
    static let noonHalfWindow: TimeInterval = 30 * 60
    static let goldenLead: TimeInterval = 60 * 60
    static let duskLength: TimeInterval = 30 * 60

    /// Dawn ±30 min around sunrise · morning until 30 min before solar noon · a noon plateau through the
    /// afternoon · the last hour before sunset · dusk for 30 min · night. A day too short for those windows
    /// (high winter latitudes) falls back to the coarse pack ladder rather than producing an inverted one.
    static func sample(at now: Date, times: SunTimes) -> DaylightSample {
        if let polar = times.polar {
            let phase: DaylightPhase = polar == .day ? .noon : .night
            return DaylightSample(phase: phase, progress: 0, altitude: polar == .day ? 0.85 : -0.85,
                                  luminance: luminance(of: phase))
        }
        guard let rise = times.sunrise, let sunset = times.sunset, sunset > rise else {
            return DaylightSample(phase: .noon, progress: 0, altitude: 0.5, luminance: luminance(of: .noon))
        }
        let dayLength = sunset.timeIntervalSince(rise)
        let noon = rise.addingTimeInterval(dayLength / 2)
        let morningStart = rise.addingTimeInterval(dawnHalfWindow)
        let noonStart = noon.addingTimeInterval(-noonHalfWindow)
        let goldenStart = sunset.addingTimeInterval(-goldenLead)
        guard noonStart > morningStart, goldenStart > noonStart else {
            let coarse: DaylightPhase
            switch SolarPhaseResolver.phase(at: now, times: times) {
            case .night: coarse = .night
            case .dawn: coarse = .dawn
            case .day: coarse = noon >= now ? .morning : .noon
            case .golden: coarse = .goldenHour
            case .dusk: coarse = .dusk
            }
            return DaylightSample(phase: coarse, progress: 0, altitude: altitude(at: now, rise: rise, dayLength: dayLength),
                                  luminance: luminance(of: coarse))
        }
        let phase: DaylightPhase
        var progress = 0.0
        if now < rise.addingTimeInterval(-dawnHalfWindow) {
            phase = .night
        } else if now < morningStart {
            phase = .dawn
            progress = fraction(now, from: rise.addingTimeInterval(-dawnHalfWindow), to: morningStart)
        } else if now < noonStart {
            phase = .morning
            progress = fraction(now, from: morningStart, to: noonStart)
        } else if now < goldenStart {
            phase = .noon
            progress = fraction(now, from: noonStart, to: goldenStart)
        } else if now < sunset {
            phase = .goldenHour
            progress = fraction(now, from: goldenStart, to: sunset)
        } else if now < sunset.addingTimeInterval(duskLength) {
            phase = .dusk
            progress = fraction(now, from: sunset, to: sunset.addingTimeInterval(duskLength))
        } else {
            phase = .night
        }
        return DaylightSample(phase: phase, progress: progress,
                              altitude: altitude(at: now, rise: rise, dayLength: dayLength),
                              luminance: luminance(of: phase))
    }

    /// The step's own sky brightness, from the clear-sky palette the wallpaper already paints with.
    static func luminance(of phase: DaylightPhase) -> Double {
        let stops = SkyPalette.stops(phase: phase.solarPhase, sky: .clear)
        let mid = stops.top.mixed(with: stops.bottom, 0.5)
        return 0.299 * mid.r + 0.587 * mid.g + 0.114 * mid.b
    }

    private static func fraction(_ now: Date, from start: Date, to end: Date) -> Double {
        guard end > start else { return 0 }
        return min(max(now.timeIntervalSince(start) / end.timeIntervalSince(start), 0), 1)
    }

    /// A sinusoid between sunrise and sunset, negative outside that span so a renderer knows the sun is down.
    private static func altitude(at now: Date, rise: Date, dayLength: TimeInterval) -> Double {
        guard dayLength > 0 else { return 0 }
        let t = now.timeIntervalSince(rise) / dayLength
        if t >= 0, t <= 1 { return sin(.pi * t) }
        let outside = t < 0 ? -t : t - 1
        return -min(outside * 2, 1)
    }
}

extension WeatherState {
    /// Today's sun times: the feed's own sunrise/sunset, else the sunrise equation from the stored coordinates.
    func sunTimes(on date: Date = Date(), calendar: Calendar = .current) -> SunTimes? {
        if let parsed = SunTimes.parse(sunrise: detail?.sunrise, sunset: detail?.sunset, calendar: calendar) { return parsed }
        guard let latitude, let longitude else { return nil }
        return SunCalculator.times(on: date, latitude: latitude, longitude: longitude, calendar: calendar)
    }
}
