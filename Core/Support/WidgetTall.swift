import Foundation

// Phase 5h — pure models for the tall full-height widget stacks: the fill planner, animation
// presets and timing, the countdown timer, stopwatch and event countdowns. No UI, no AppKit.

// MARK: - Fill planner (5h-B)

struct TallTile: Equatable {
    let id: String
    let minHeight: Double
    /// Height the tile is designed for; leftover space grows tiles up to `maxHeight`.
    let idealHeight: Double
    let maxHeight: Double
    /// Share of leftover space (0 = fixed size).
    let flex: Double
    /// Optional tiles are only included while they fit; lower number = kept first.
    let optionalPriority: Int?

    init(_ id: String, min: Double, ideal: Double? = nil, max: Double? = nil, flex: Double = 1, optional priority: Int? = nil) {
        self.id = id; minHeight = min; idealHeight = ideal ?? min; maxHeight = max ?? (ideal ?? min) * 1.6
        self.flex = flex; optionalPriority = priority
    }
}

enum TallLayoutPlanner {
    /// Heights per included tile (in input order) for a stack that fills `available` points.
    /// Required tiles always appear (even if they overflow — the panel then scrolls); optional
    /// tiles are added by priority while they still fit; leftover space is shared by `flex`,
    /// first up to each tile's ideal height, then up to its max.
    static func plan(_ tiles: [TallTile], available: Double, gap: Double) -> [(id: String, height: Double)] {
        var included = tiles.filter { $0.optionalPriority == nil }.map(\.id)
        func total(_ ids: [String]) -> Double {
            let t = tiles.filter { ids.contains($0.id) }
            return t.reduce(0) { $0 + $1.minHeight } + Double(Swift.max(t.count - 1, 0)) * gap
        }
        for tile in tiles.filter({ $0.optionalPriority != nil }).sorted(by: { $0.optionalPriority! < $1.optionalPriority! }) {
            if total(included + [tile.id]) <= available { included.append(tile.id) }
        }
        let chosen = tiles.filter { included.contains($0.id) }
        var heights = chosen.map { $0.minHeight }
        var leftover = available - total(included)

        for pass in 0..<2 {
            guard leftover > 0.5 else { break }
            let caps = chosen.map { pass == 0 ? $0.idealHeight : $0.maxHeight }
            var open = chosen.indices.filter { chosen[$0].flex > 0 && heights[$0] < caps[$0] - 0.01 }
            while leftover > 0.5, !open.isEmpty {
                let weight = open.reduce(0) { $0 + chosen[$1].flex }
                var spent = 0.0
                for i in open {
                    let share = leftover * chosen[i].flex / weight
                    let add = Swift.min(share, caps[i] - heights[i])
                    heights[i] += add; spent += add
                }
                leftover -= spent
                open = open.filter { heights[$0] < caps[$0] - 0.01 }
                if spent < 0.01 { break }
            }
        }
        return zip(chosen, heights).map { ($0.id, $1) }
    }
}

// MARK: - Animation presets (5h-H)

enum WidgetAnimationPreset: String, CaseIterable, Codable, Sendable {
    /// The original behaviour: the window just appears/disappears.
    case instant
    /// The stack slides in from its screen edge.
    case slide
    /// Tiles scale up from 92% and fade in, staggered top to bottom.
    case springPop

    static let storageKey = "com.katikati.widgets.animation"
    static let `default`: WidgetAnimationPreset = .slide

    /// Stored choice (default Slide) with Reduce Motion applied.
    static func resolve(defaults: UserDefaults = .standard, reduceMotion: Bool) -> WidgetAnimationPreset {
        let chosen = defaults.string(forKey: storageKey).flatMap(WidgetAnimationPreset.init(rawValue:)) ?? .default
        return WidgetAnimationTiming.effective(chosen, reduceMotion: reduceMotion)
    }
}

enum WidgetAnimationTiming {
    static let slideDuration = 0.28
    static let closeDuration = 0.18
    static let popScale = 0.92
    static let staggerStep = 0.035
    static let maxStaggered = 8

    /// Reduce Motion always wins.
    static func effective(_ preset: WidgetAnimationPreset, reduceMotion: Bool) -> WidgetAnimationPreset {
        reduceMotion ? .instant : preset
    }

    static func staggerDelay(forTile index: Int) -> Double {
        Double(Swift.min(Swift.max(index, 0), maxStaggered)) * staggerStep
    }

    /// How long the window must stay up while the close animation plays.
    static func closeDelay(_ preset: WidgetAnimationPreset) -> Double {
        preset == .instant ? 0 : closeDuration
    }

    /// Off-screen start x for a slide: fully past the edge the stack hugs.
    static func slideStartX(target: Double, width: Double, side: WidgetPanelSide, screenMinX: Double, screenMaxX: Double) -> Double {
        side == .right ? screenMaxX + 8 : screenMinX - width - 8
    }
}

// MARK: - Countdown timer (5h-C)

struct CountdownTimerModel: Equatable {
    static let presets = [60, 300, 600, 900, 1800]
    static let maxSeconds = 99 * 60 + 59

    private(set) var total: Int = 300
    private(set) var remaining: Int = 300
    private(set) var isRunning = false
    private(set) var isFinished = false

    var progress: Double { total == 0 ? 0 : 1 - Double(remaining) / Double(total) }

    /// Sets a new duration (stops the timer). Clamped to 0…99:59.
    mutating func set(seconds: Int) {
        total = Swift.min(Swift.max(seconds, 0), Self.maxSeconds)
        remaining = total; isRunning = false; isFinished = false
    }

    /// ±adjust while idle changes the duration; while running it shifts the remaining time.
    mutating func adjust(by seconds: Int) {
        if isRunning {
            remaining = Swift.min(Swift.max(remaining + seconds, 1), Self.maxSeconds)
            total = Swift.max(total, remaining)
        } else {
            set(seconds: total + seconds)
        }
    }

    mutating func toggle() {
        if isFinished { reset() }
        guard remaining > 0 else { return }
        isRunning.toggle()
    }

    mutating func reset() { remaining = total; isRunning = false; isFinished = false }

    /// One second elapsed; returns true on the tick that finishes the timer.
    @discardableResult
    mutating func tick() -> Bool {
        guard isRunning else { return false }
        remaining -= 1
        if remaining <= 0 { remaining = 0; isRunning = false; isFinished = true; return true }
        return false
    }

    static func label(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
}

// MARK: - Stopwatch (5h-D)

struct StopwatchModel: Equatable {
    private(set) var accumulated: TimeInterval = 0
    private(set) var startedAt: Date?
    private(set) var laps: [TimeInterval] = []   // cumulative elapsed at each lap

    var isRunning: Bool { startedAt != nil }

    func elapsed(at now: Date) -> TimeInterval {
        accumulated + (startedAt.map { Swift.max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    mutating func toggle(at now: Date) {
        if let s = startedAt { accumulated += Swift.max(0, now.timeIntervalSince(s)); startedAt = nil } else { startedAt = now }
    }

    mutating func lap(at now: Date) {
        guard isRunning else { return }
        laps.append(elapsed(at: now))
    }

    mutating func reset() { accumulated = 0; startedAt = nil; laps = [] }

    /// Split durations (each lap minus the previous), newest first.
    var splits: [TimeInterval] {
        var out: [TimeInterval] = []; var prev = 0.0
        for l in laps { out.append(l - prev); prev = l }
        return out.reversed()
    }

    static func label(_ t: TimeInterval) -> String {
        let cs = Int((t * 100).rounded(.down)); let m = cs / 6000, s = (cs / 100) % 60
        return String(format: "%02d:%02d.%02d", m, s, cs % 100)
    }
}

// MARK: - Event countdowns (5h-D)

struct EventCountdown: Codable, Identifiable, Equatable {
    var id = UUID()
    var label: String
    var date: Date

    static let storageKey = "com.katikati.widgets.countdowns"
    static let limit = 6

    /// Whole calendar days from `now`'s day to the event's day (negative = past).
    func daysRemaining(from now: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// Upcoming first (soonest), then past events (most recent first); capped at `limit`.
    static func ordered(_ events: [EventCountdown], now: Date, calendar: Calendar = .current) -> [EventCountdown] {
        let up = events.filter { $0.daysRemaining(from: now, calendar: calendar) >= 0 }.sorted { $0.date < $1.date }
        let past = events.filter { $0.daysRemaining(from: now, calendar: calendar) < 0 }.sorted { $0.date > $1.date }
        return Array((up + past).prefix(limit))
    }
}
