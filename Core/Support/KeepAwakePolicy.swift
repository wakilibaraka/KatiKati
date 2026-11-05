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
