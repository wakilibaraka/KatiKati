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
