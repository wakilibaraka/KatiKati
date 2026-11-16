import Foundation

// Keep Awake policy: decides, from plain inputs, whether the Mac should be held awake. Pure and
// time-injected so the rules are unit-testable; the Platform service feeds it and applies the result.

enum KeepAwakeReason: Equatable, Sendable {
    case manual, agents, grace, off, batteryLow, timerEnded
}

struct KeepAwakeInputs: Equatable, Sendable {
    /// The owner's manual switch (and its optional end time; nil = until switched off).
    var manualOn = false
    var manualEnd: Date?
    var agentsEnabled = true
    var lidClosedEnabled = false
    /// An AI agent is working right now (any provider, interactive or background).
    var agentsWorking = false
    var batteryPercent: Int?
    var onBattery = false
    var externalDisplay = false
    /// Hold this long after the last agent activity so short pauses between turns don't sleep the Mac.
    var graceSeconds: TimeInterval = 180
    var floorPercent = 20
}

struct KeepAwakeDecision: Equatable, Sendable {
    var hold: Bool
    var reason: KeepAwakeReason
    /// Whether `pmset disablesleep` should be on (lid closed keeps running). Implies `hold`.
    var lidGuard: Bool
}

/// Ruler scrubber math for a drag-to-set duration, 1 minute ... 8 hours. Ticks are finer at the short end
/// (1 min up to 10, 5 min up to 1 h, 15 min up to 3 h, 30 min up to 8 h), and every `pointsPerTick` of
/// horizontal drag moves one tick. Pure: the view feeds drag deltas, the service gets whole minutes.
enum PomodoroScrubberMath {
    static let minMinutes = 1
    static let maxMinutes = 480
    static let pointsPerTick: Double = 8

    /// Every selectable value, ascending.
    static let ticks: [Int] = {
        var out = Array(1...10)
        out += stride(from: 15, through: 60, by: 5)
        out += stride(from: 75, through: 180, by: 15)
        out += stride(from: 210, through: 480, by: 30)
        return out
    }()

    /// The tick closest to `minutes` (clamped into range; ties go to the shorter one).
    static func snap(_ minutes: Int) -> Int {
        let m = min(max(minutes, minMinutes), maxMinutes)
        return ticks.min { abs($0 - m) < abs($1 - m) } ?? m
    }

    /// Minutes after dragging `delta` points from `start`. Dragging right lengthens; non-finite deltas change nothing.
    static func minutes(start: Int, dragDelta delta: Double) -> Int {
        let base = snap(start)
        guard delta.isFinite, let i = ticks.firstIndex(of: base) else { return base }
        let moved = i + Int((delta / pointsPerTick).rounded(.towardZero))
        return ticks[min(max(moved, 0), ticks.count - 1)]
    }

    /// "25m", "1h", "1h 30m".
    static func label(minutes: Int) -> String {
        let m = min(max(minutes, minMinutes), maxMinutes)
        let h = m / 60, r = m % 60
        if h == 0 { return "\(r)m" }
        return r == 0 ? "\(h)h" : "\(h)h \(r)m"
    }
}

/// Tracks the last time an agent was seen working so the grace window can outlive the signal.
struct KeepAwakePolicy: Equatable, Sendable {
    private(set) var lastAgentActivity: Date?

    mutating func decide(_ i: KeepAwakeInputs, now: Date) -> KeepAwakeDecision {
        if i.agentsEnabled && i.agentsWorking { lastAgentActivity = now }
        // Battery floor beats every other reason; on AC the floor never applies.
        if i.onBattery, let pct = i.batteryPercent, pct < i.floorPercent {
            return KeepAwakeDecision(hold: false, reason: .batteryLow, lidGuard: false)
        }
        var reason: KeepAwakeReason = .off
        if i.manualOn {
            if let end = i.manualEnd, now >= end { reason = .timerEnded } else { reason = .manual }
        }
        if reason != .manual, i.agentsEnabled {
            if i.agentsWorking { reason = .agents }
            else if let last = lastAgentActivity, now.timeIntervalSince(last) < i.graceSeconds { reason = .grace }
        }
        let hold = reason == .manual || reason == .agents || reason == .grace
        // The lid guard needs admin rights and misbehaves with an external display, so it is off there.
        return KeepAwakeDecision(hold: hold, reason: reason,
                                 lidGuard: hold && i.lidClosedEnabled && !i.externalDisplay)
    }
}
