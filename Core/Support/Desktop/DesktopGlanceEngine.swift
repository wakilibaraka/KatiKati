import Foundation

/// Pure calendar facts for the Desktop Glance widget: lunar date, 24 solar terms, and festivals.
/// Returns identifiers only (no display strings) so the view layer localizes them.
enum DesktopSolarTerm: String, CaseIterable, Sendable {
    case minorCold, majorCold, startOfSpring, rainWater, awakeningOfInsects, springEquinox
    case clearAndBright, grainRain, startOfSummer, grainBuds, grainInEar, summerSolstice
    case minorHeat, majorHeat, startOfAutumn, endOfHeat, whiteDew, autumnEquinox
    case coldDew, frostDescent, startOfWinter, minorSnow, majorSnow, winterSolstice

    /// (month, 21st-century C constant) per the standard shou-xing approximation.
    fileprivate var parameters: (month: Int, c: Double) {
        switch self {
        case .minorCold: return (1, 5.4055)
        case .majorCold: return (1, 20.12)
        case .startOfSpring: return (2, 3.87)
        case .rainWater: return (2, 18.73)
        case .awakeningOfInsects: return (3, 5.63)
        case .springEquinox: return (3, 20.646)
        case .clearAndBright: return (4, 4.81)
        case .grainRain: return (4, 20.1)
        case .startOfSummer: return (5, 5.52)
        case .grainBuds: return (5, 21.04)
        case .grainInEar: return (6, 5.678)
        case .summerSolstice: return (6, 21.37)
        case .minorHeat: return (7, 7.108)
        case .majorHeat: return (7, 22.83)
        case .startOfAutumn: return (8, 7.5)
        case .endOfHeat: return (8, 23.13)
        case .whiteDew: return (9, 7.646)
        case .autumnEquinox: return (9, 23.042)
        case .coldDew: return (10, 8.318)
        case .frostDescent: return (10, 23.438)
        case .startOfWinter: return (11, 7.438)
        case .minorSnow: return (11, 22.36)
        case .majorSnow: return (12, 7.18)
        case .winterSolstice: return (12, 21.94)
        }
    }
}

enum DesktopFestival: String, CaseIterable, Sendable {
    case newYear, laborDay, nationalDay, christmas, valentines
    case springFestival, lanternFestival, dragonBoat, qixi, midAutumn, doubleNinth, laba
}

struct DesktopLunarDate: Equatable, Sendable {
    let month: Int
    let day: Int
    let isLeapMonth: Bool
}

struct DesktopGlanceInfo: Equatable, Sendable {
    let lunar: DesktopLunarDate?
    let solarTerm: DesktopSolarTerm?
    let festivals: [DesktopFestival]
}

enum DesktopGlanceEngine {
    /// Approximate (±1 day in rare years) day-of-month for `term` in the Gregorian `year`.
    static func solarTermDay(_ term: DesktopSolarTerm, year: Int) -> Int {
        let p = term.parameters
        let y = ((year % 100) + 100) % 100
        let leapBase = p.month <= 2 ? (y - 1) / 4 : y / 4
        return Int((Double(y) * 0.2422 + p.c).rounded(.down)) - leapBase
    }

    static func solarTerm(on date: Date, calendar: Calendar = .current) -> DesktopSolarTerm? {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = c.year, let month = c.month, let day = c.day else { return nil }
        return DesktopSolarTerm.allCases.first {
            $0.parameters.month == month && solarTermDay($0, year: year) == day
        }
    }

    static func lunarDate(on date: Date, timeZone: TimeZone = .current) -> DesktopLunarDate? {
        var chinese = Calendar(identifier: .chinese)
        chinese.timeZone = timeZone
        let c = chinese.dateComponents([.month, .day], from: date)
        guard let month = c.month, let day = c.day else { return nil }
        return DesktopLunarDate(month: month, day: day, isLeapMonth: c.isLeapMonth ?? false)
    }

    static func festivals(on date: Date, calendar: Calendar = .current) -> [DesktopFestival] {
        var found: [DesktopFestival] = []
        let c = calendar.dateComponents([.month, .day], from: date)
        switch (c.month ?? 0, c.day ?? 0) {
        case (1, 1): found.append(.newYear)
        case (2, 14): found.append(.valentines)
        case (5, 1): found.append(.laborDay)
        case (10, 1): found.append(.nationalDay)
        case (12, 25): found.append(.christmas)
        default: break
        }
        if let lunar = lunarDate(on: date, timeZone: calendar.timeZone), !lunar.isLeapMonth {
            switch (lunar.month, lunar.day) {
            case (1, 1): found.append(.springFestival)
            case (1, 15): found.append(.lanternFestival)
            case (5, 5): found.append(.dragonBoat)
            case (7, 7): found.append(.qixi)
            case (8, 15): found.append(.midAutumn)
            case (9, 9): found.append(.doubleNinth)
            case (12, 8): found.append(.laba)
            default: break
            }
        }
        return found
    }

    static func info(on date: Date, calendar: Calendar = .current) -> DesktopGlanceInfo {
        DesktopGlanceInfo(
            lunar: lunarDate(on: date, timeZone: calendar.timeZone),
            solarTerm: solarTerm(on: date, calendar: calendar),
            festivals: festivals(on: date, calendar: calendar)
        )
    }
}
