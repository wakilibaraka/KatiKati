import Foundation

// Pure models behind the floating calendar panel (Phase 5e): world clocks, the Pomodoro focus
// timer and alarms. No UI, no EventKit, no notifications — everything here is unit-testable.

// MARK: - World clocks (5e-E)

struct WorldClockReading: Equatable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let city: String
    let time: String
    /// -1 yesterday, 0 same day, +1 tomorrow relative to the local calendar day.
    let dayDelta: Int
    /// Signed hour difference from the local zone at `date`, e.g. "+5h", "-3h30m", "same".
    let offsetLabel: String
    let isNight: Bool
}

enum WorldClockModel {
    static let maxClocks = 4
    static let defaultIdentifiers = ["UTC", "America/New_York", "Europe/London", "Asia/Tokyo"]

    static func city(for identifier: String) -> String {
        if identifier == "UTC" || identifier == "GMT" { return "UTC" }
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }

    /// Appends `identifier` unless it is unknown, a duplicate, or the list is already full.
    static func adding(_ identifier: String, to list: [String]) -> [String] {
        guard TimeZone(identifier: identifier) != nil, !list.contains(identifier), list.count < maxClocks else { return list }
        return list + [identifier]
    }

    static func reading(
        for identifier: String, at date: Date, local: TimeZone = .current, locale: Locale = .current
    ) -> WorldClockReading? {
        guard let zone = TimeZone(identifier: identifier) else { return nil }
        var remote = Calendar(identifier: .gregorian); remote.timeZone = zone
        var home = Calendar(identifier: .gregorian); home.timeZone = local

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        formatter.timeStyle = .short
        formatter.dateStyle = .none

        let remoteDay = remote.dateComponents([.year, .month, .day], from: date)
        let homeDay = home.dateComponents([.year, .month, .day], from: date)
        var rc = Calendar(identifier: .gregorian); rc.timeZone = TimeZone(secondsFromGMT: 0)!
        let delta = rc.dateComponents([.day], from: rc.date(from: homeDay)!, to: rc.date(from: remoteDay)!).day ?? 0

        let hour = remote.component(.hour, from: date)
        return WorldClockReading(
            identifier: identifier,
            city: city(for: identifier),
            time: formatter.string(from: date),
            dayDelta: max(-1, min(1, delta)),
            offsetLabel: offsetLabel(seconds: zone.secondsFromGMT(for: date) - local.secondsFromGMT(for: date)),
            isNight: hour < 6 || hour >= 19
        )
    }

    static func offsetLabel(seconds: Int) -> String {
        guard seconds != 0 else { return "same" }
        let sign = seconds < 0 ? "-" : "+"
        let minutes = abs(seconds) / 60
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(sign)\(h)h" : "\(sign)\(h)h\(m)m"
    }
}

// MARK: - Focus timer (5e-F)

struct FocusTimerModel: Equatable {
    enum Phase: Equatable { case focus, shortBreak, longBreak }

    static let focusSeconds = 25 * 60
    static let shortBreakSeconds = 5 * 60
    static let longBreakSeconds = 15 * 60
    static let cycleLength = 4

    private(set) var phase: Phase = .focus
    private(set) var remaining: Int = FocusTimerModel.focusSeconds
    private(set) var isRunning = false
    /// Focus sessions completed in the current cycle (0…cycleLength-1 shown as lit dots).
    private(set) var completedInCycle = 0

    static func duration(of phase: Phase) -> Int {
        switch phase {
        case .focus: return focusSeconds
        case .shortBreak: return shortBreakSeconds
        case .longBreak: return longBreakSeconds
        }
    }

    var progress: Double {
        1 - Double(remaining) / Double(Self.duration(of: phase))
    }

    mutating func toggle() { isRunning.toggle() }

    mutating func reset() {
        isRunning = false
        remaining = Self.duration(of: phase)
    }

    /// Ends the current phase now and moves to the next one (does not auto-start).
    mutating func skip() {
        isRunning = false
        advance()
    }

    /// One second elapsed. Returns true when a phase just completed (caller plays the chime).
    @discardableResult
    mutating func tick() -> Bool {
        guard isRunning else { return false }
        remaining -= 1
        if remaining <= 0 { advance(); return true }
        return false
    }

    private mutating func advance() {
        switch phase {
        case .focus:
            completedInCycle += 1
            if completedInCycle >= Self.cycleLength {
                phase = .longBreak
                completedInCycle = Self.cycleLength
            } else {
                phase = .shortBreak
            }
        case .shortBreak:
            phase = .focus
        case .longBreak:
            phase = .focus
            completedInCycle = 0
        }
        remaining = Self.duration(of: phase)
    }
}

// MARK: - Alarms (5e-F)

struct AlarmItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var hour: Int
    var minute: Int
    var label: String = ""
    var isEnabled = true
    /// Calendar weekdays (1 = Sunday … 7 = Saturday). Empty = one-shot, next occurrence only.
    var weekdays: Set<Int> = []

    /// Next time this alarm rings strictly after `date`, or nil when disabled.
    func nextFire(after date: Date, calendar: Calendar = .current) -> Date? {
        guard isEnabled else { return nil }
        let components = DateComponents(hour: hour, minute: minute, second: 0)
        var cursor = date
        // Up to 8 matches covers every weekday filter plus a DST-skipped local time.
        for _ in 0..<8 {
            guard let candidate = calendar.nextDate(
                after: cursor, matching: components, matchingPolicy: .nextTime
            ) else { return nil }
            if weekdays.isEmpty || weekdays.contains(calendar.component(.weekday, from: candidate)) {
                return candidate
            }
            cursor = candidate
        }
        return nil
    }
}

enum AlarmList {
    /// Alarms sorted by time of day, then by label, for stable display.
    static func sorted(_ alarms: [AlarmItem]) -> [AlarmItem] {
        alarms.sorted { ($0.hour, $0.minute, $0.label) < ($1.hour, $1.minute, $1.label) }
    }

    /// The earliest upcoming ring among enabled alarms.
    static func next(in alarms: [AlarmItem], after date: Date, calendar: Calendar = .current) -> (AlarmItem, Date)? {
        alarms.compactMap { alarm in alarm.nextFire(after: date, calendar: calendar).map { (alarm, $0) } }
            .min { $0.1 < $1.1 }
    }
}

// MARK: - Agenda fitting (5e-D)

enum AgendaFitting {
    /// How many rows fit in `height` and how many overflow into a "+N more" line.
    static func visibleCount(total: Int, height: CGFloat, rowHeight: CGFloat, reservedForMore: CGFloat) -> (shown: Int, more: Int) {
        guard total > 0, rowHeight > 0 else { return (0, 0) }
        let fitsAll = Int(max(0, height) / rowHeight)
        if fitsAll >= total { return (total, 0) }
        let shown = max(0, Int(max(0, height - reservedForMore) / rowHeight))
        return (shown, total - shown)
    }
}

// MARK: - Layout / palette / clock style (5e rework)

/// Layout preset of the floating widget tiles. Width is part of the layout. These presets, the tile
/// palette and the tile surface are the shared vocabulary for every future widget (Weather
/// redesign, Phase 7e overlay widgets).
enum CalendarPanelLayout: String, CaseIterable, Codable, Sendable {
    /// One ~340pt column of tiles, like the macOS desktop-widget stack.
    case mac
    /// Wider three-column tile grid, like the iPad widget board.
    case ipad
    /// Full-height ~420pt stack (Phase 5h): tiles stretch to use the whole screen height.
    case tall

    static let storageKey = "com.katikati.calendar.layout"
    static let macWidth: CGFloat = 340

    /// Total window width including the 8pt shadow gutter on each side.
    func width(forScreenWidth screenWidth: CGFloat) -> CGFloat {
        switch self {
        case .mac: return Self.macWidth
        case .ipad: return min(max(screenWidth / 2, 560), 760)
        case .tall: return 420
        }
    }

    /// True when the stack should grow to the full available height.
    var fillsHeight: Bool { self == .tall }
}

/// Which screen edge a widget-tile stack hugs.
enum WidgetPanelSide: Sendable { case left, right }

extension CalendarPanelLayout {
    /// The shared widget layout: the stored choice, else the pre-rework size preset mapped over
    /// (`compact420`→mac, `halfScreen`→ipad), else **iPad** for fresh installs (Phase 16b). The result is persisted.
    static func resolve(defaults: UserDefaults = .standard) -> CalendarPanelLayout {
        if let raw = defaults.string(forKey: storageKey), let layout = CalendarPanelLayout(rawValue: raw) { return layout }
        let migrated = CalendarPanelSettingsMigration.layout(fromLegacy: defaults.string(forKey: "com.katikati.calendar.panelPreset")) ?? .ipad
        defaults.set(migrated.rawValue, forKey: storageKey)
        return migrated
    }
}

enum TileKind: CaseIterable { case date, clock, focus, calendar, agenda, reminders, alarms, timer, stopwatch, notes, countdown, nowPlaying, calculator, screenTime, network, battery, topApps, batteries }

extension TileKind {
    /// Phase 16n: the Control Center's user widgets (the six ported tiles). Stored by case name;
    /// unknown names are dropped, duplicates collapse; nil of a never-written key gives the default.
    static let controlCenterDefault: [TileKind] = [.calculator, .screenTime, .network, .battery, .topApps, .batteries]

    static func parse(_ raw: String?) -> [TileKind] {
        guard let raw else { return controlCenterDefault }
        var seen = Set<String>()
        return raw.split(separator: ",").compactMap { part -> TileKind? in
            let name = part.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, seen.insert(name).inserted else { return nil }
            return TileKind.allCases.first { "\($0)" == name }
        }
    }

    static func serialize(_ tiles: [TileKind]) -> String { tiles.map { "\($0)" }.joined(separator: ",") }
}

public struct TileRGB: Equatable, Sendable { public let r: Double; public let g: Double; public let b: Double
    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b } }

/// Accent / header-band colour per tile. The solid tile base follows system light/dark and is not
/// part of the palette.
enum TilePalette: String, CaseIterable, Codable, Sendable {
    case classic, vivid, pastel, mono

    static let storageKey = "com.katikati.calendar.palette"

    func accent(for tile: TileKind) -> TileRGB {
        switch self {
        case .classic:
            switch tile {
            case .date: return TileRGB(r: 0.93, g: 0.18, b: 0.27)
            case .clock: return TileRGB(r: 0.20, g: 0.20, b: 0.22)
            case .focus: return TileRGB(r: 0.20, g: 0.78, b: 0.35)
            case .calendar, .agenda: return TileRGB(r: 0.04, g: 0.52, b: 1.00)
            case .reminders: return TileRGB(r: 0.98, g: 0.80, b: 0.10)
            case .alarms: return TileRGB(r: 1.00, g: 0.58, b: 0.00)
            case .timer: return TileRGB(r: 1.00, g: 0.42, b: 0.10)
            case .stopwatch: return TileRGB(r: 0.37, g: 0.36, b: 0.90)
            case .notes: return TileRGB(r: 0.98, g: 0.80, b: 0.10)
            case .countdown: return TileRGB(r: 0.69, g: 0.32, b: 0.87)
            case .nowPlaying: return TileRGB(r: 0.90, g: 0.30, b: 0.45)
            case .calculator: return TileRGB(r: 0.42, g: 0.44, b: 0.52)
            case .screenTime: return TileRGB(r: 0.72, g: 0.48, b: 0.18)
            case .network: return TileRGB(r: 0.15, g: 0.65, b: 0.85)
            case .battery: return TileRGB(r: 0.25, g: 0.72, b: 0.30)
            case .topApps: return TileRGB(r: 0.85, g: 0.35, b: 0.20)
            case .batteries: return TileRGB(r: 0.35, g: 0.55, b: 0.90)
            }
        case .vivid:
            switch tile {
            case .date: return TileRGB(r: 1.00, g: 0.16, b: 0.33)
            case .clock: return TileRGB(r: 0.37, g: 0.36, b: 0.90)
            case .focus: return TileRGB(r: 0.00, g: 0.85, b: 0.45)
            case .calendar, .agenda: return TileRGB(r: 0.00, g: 0.45, b: 1.00)
            case .reminders: return TileRGB(r: 1.00, g: 0.80, b: 0.00)
            case .alarms: return TileRGB(r: 1.00, g: 0.40, b: 0.05)
            case .timer: return TileRGB(r: 1.00, g: 0.30, b: 0.15)
            case .stopwatch: return TileRGB(r: 0.30, g: 0.30, b: 1.00)
            case .notes: return TileRGB(r: 1.00, g: 0.82, b: 0.00)
            case .countdown: return TileRGB(r: 0.75, g: 0.20, b: 0.95)
            case .nowPlaying: return TileRGB(r: 1.00, g: 0.20, b: 0.50)
            case .calculator: return TileRGB(r: 0.30, g: 0.32, b: 0.95)
            case .screenTime: return TileRGB(r: 0.95, g: 0.55, b: 0.10)
            case .network: return TileRGB(r: 0.00, g: 0.75, b: 1.00)
            case .battery: return TileRGB(r: 0.10, g: 0.85, b: 0.30)
            case .topApps: return TileRGB(r: 1.00, g: 0.30, b: 0.15)
            case .batteries: return TileRGB(r: 0.25, g: 0.50, b: 1.00)
            }
        case .pastel:
            switch tile {
            case .date: return TileRGB(r: 0.98, g: 0.50, b: 0.56)
            case .clock: return TileRGB(r: 0.62, g: 0.60, b: 0.95)
            case .focus: return TileRGB(r: 0.45, g: 0.85, b: 0.62)
            case .calendar, .agenda: return TileRGB(r: 0.50, g: 0.72, b: 0.98)
            case .reminders: return TileRGB(r: 0.98, g: 0.88, b: 0.45)
            case .alarms: return TileRGB(r: 0.98, g: 0.72, b: 0.45)
            case .timer: return TileRGB(r: 0.98, g: 0.62, b: 0.50)
            case .stopwatch: return TileRGB(r: 0.62, g: 0.60, b: 0.95)
            case .notes: return TileRGB(r: 0.98, g: 0.88, b: 0.45)
            case .countdown: return TileRGB(r: 0.80, g: 0.62, b: 0.92)
            case .nowPlaying: return TileRGB(r: 0.98, g: 0.62, b: 0.72)
            case .calculator: return TileRGB(r: 0.66, g: 0.68, b: 0.85)
            case .screenTime: return TileRGB(r: 0.90, g: 0.70, b: 0.45)
            case .network: return TileRGB(r: 0.55, g: 0.82, b: 0.96)
            case .battery: return TileRGB(r: 0.55, g: 0.88, b: 0.60)
            case .topApps: return TileRGB(r: 0.95, g: 0.60, b: 0.50)
            case .batteries: return TileRGB(r: 0.60, g: 0.72, b: 0.95)
            }
        case .mono:
            return TileRGB(r: 0.36, g: 0.37, b: 0.41)
        }
    }
}

enum CalendarClockStyle: String, CaseIterable, Codable, Sendable {
    case flip, analog, date
    static let storageKey = "com.katikati.calendar.clockStyle"
}

enum CalendarPanelSettingsMigration {
    /// Maps the pre-rework size preset values onto layouts (`compact420`→mac, `halfScreen`→ipad).
    static func layout(fromLegacy value: String?) -> CalendarPanelLayout? {
        switch value {
        case "compact420": return .mac
        case "halfScreen": return .ipad
        default: return nil
        }
    }
}

// MARK: - Countdown

enum NextEventCountdown {
    /// First timed event that has not started yet, from a start-sorted list.
    static func next(startingAfter now: Date, in starts: [Date]) -> Date? {
        starts.filter { $0 > now }.min()
    }
}
