import Foundation

// Phase 36 — pure rules behind the small daily helpers. No AppKit, no clocks, no IO: every threshold and
// transition is unit-tested in `DailyHelpersRulesTests`. `DailyHelpersService` feeds these and shows the result.

/// What a daily-helper notice says (the UI maps each kind to a symbol + localized headline).
enum LiveNoticeKind: String, Equatable, Sendable {
    case capsLockOn, capsLockOff
    case batteryHigh, batteryFull
}

/// 36a — Caps Lock transitions. The first reading only sets the baseline (no notice at launch).
struct CapsLockTracker: Equatable, Sendable {
    private(set) var isOn: Bool?

    mutating func update(isOn now: Bool) -> LiveNoticeKind? {
        defer { isOn = now }
        guard let before = isOn, before != now else { return nil }
        return now ? .capsLockOn : .capsLockOff
    }
}

/// 36b — "unplug" nudges while charging: once at 80% (the battery-health sweet spot) and once when full.
/// The first reading only seeds the state, so launching at 90% plugged in does not announce anything.
/// Each nudge re-arms after the level drops back or the charger is unplugged.
struct BatteryNoticeRule: Equatable, Sendable {
    static let highThreshold = 80
    private var seeded = false
    private var armedHigh = true
    private var armedFull = true

    mutating func update(_ battery: BatteryStatus) -> LiveNoticeKind? {
        guard let level = battery.level else { return nil }
        if !seeded {
            seeded = true
            armedHigh = level < Self.highThreshold
            armedFull = level < 100
            return nil
        }
        if !battery.isPluggedIn || level < Self.highThreshold - 5 { armedHigh = true }
        if !battery.isPluggedIn || level < 95 { armedFull = true }
        guard battery.isPluggedIn else { return nil }
        if level >= 100, armedFull { armedFull = false; armedHigh = false; return .batteryFull }
        if battery.isCharging, level >= Self.highThreshold, armedHigh { armedHigh = false; return .batteryHigh }
        return nil
    }
}

/// 36f — keyboard cleaning lock length. Long enough to wipe a keyboard, short enough that a forgotten
/// lock frees itself (the fixed ⌃⌥⌘P chord from Phase 24b always unlocks sooner).
enum CleaningLock {
    static let defaultSeconds = 60.0
    static func clamped(_ seconds: Double) -> Double { min(max(seconds, 10), 300) }
}
