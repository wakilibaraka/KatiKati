import Foundation

// Phase 36 — pure rules behind the small daily helpers. No AppKit, no clocks, no IO: every threshold and
// transition is unit-tested in `DailyHelpersRulesTests`. `DailyHelpersService` feeds these and shows the result.

/// What a daily-helper notice says (the UI maps each kind to a symbol + localized headline).
enum LiveNoticeKind: String, Equatable, Sendable {
    case capsLockOn, capsLockOff
    case batteryHigh, batteryFull
    case hydrate, pause
}

/// 56e — wellness reminders. Fixed gaps (no picker): water hourly, a screen break every 50 minutes.
extension LiveNoticeKind {
    var reminderInterval: TimeInterval? {
        switch self {
        case .hydrate: return 3600
        case .pause: return 3000
        default: return nil
        }
    }
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

    /// What a lock that outlived its own process does at the next launch.
    enum Launch: Equatable {
        /// Nothing pending, or the window has passed: the lock must not hold the keyboard.
        case release
        /// Still inside the window: hold it for the seconds left.
        case resume(seconds: Int)
    }

    /// Phase 12 safety fix. The lock pauses the keyboard through the persisted 24b pause, but its
    /// deadline was never written down — so a crash or force-quit mid-lock came up with a dead
    /// keyboard until ⌃⌥⌘P. The deadline is persisted now and this is the whole decision on it:
    /// a window still running resumes, anything else fails **open**.
    ///
    /// The one case it cannot answer: a *pre-fix* crash leaves `isPaused` on with no deadline at
    /// all, which is indistinguishable from a deliberate 24b pause — the caller leaves that alone
    /// (`shortcut:` nothing persists a lock's start before Phase 12, so `nil` must stay hands-off).
    static func launchDecision(deadline: Date?, now: Date) -> Launch {
        guard let deadline else { return .release }
        let left = deadline.timeIntervalSince(now)
        guard left > 0 else { return .release }
        return .resume(seconds: Int(left.rounded(.up)))
    }
}

/// 36c — which mounted volumes get an eject pill: real external, ejectable drives only (never the boot
/// volume, an internal disk, a disk image, or a network share).
enum EjectPolicy {
    static func isOffered(isEjectable: Bool, isInternal: Bool, isLocal: Bool, isRoot: Bool) -> Bool {
        isEjectable && !isInternal && isLocal && !isRoot
    }
}

/// 36h — which privacy dots show (green camera, orange microphone, both can show together).
struct PrivacyDots: Equatable, Sendable {
    var camera = false
    var microphone = false
    var isEmpty: Bool { !camera && !microphone }
}

// MARK: - Droppy-Inspired Slice E-Breather: BreatherWellnessEngine

struct BreatherRingProgress: Equatable, Sendable {
    var completed: Int
    var target: Int

    var progress: Double {
        guard target > 0 else { return 0 }
        return min(1.0, max(0.0, Double(completed) / Double(target)))
    }
}

struct BreatherRings: Equatable, Sendable {
    var eyes: BreatherRingProgress
    var stretch: BreatherRingProgress
    var hydrate: BreatherRingProgress

    var allCompleted: Bool {
        eyes.progress >= 1.0 && stretch.progress >= 1.0 && hydrate.progress >= 1.0
    }
}

struct BreatherStreak: Equatable, Sendable {
    var count: Int
    var lastCompletedDate: Date?

    mutating func recordCompletion(on date: Date, calendar: Calendar = .current) {
        if let last = lastCompletedDate {
            if calendar.isDate(last, inSameDayAs: date) {
                return
            }
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: date),
               calendar.isDate(last, inSameDayAs: yesterday) {
                count += 1
            } else {
                count = 1
            }
        } else {
            count = 1
        }
        lastCompletedDate = date
    }
}

enum BreatherActivityType: String, CaseIterable, Identifiable, Sendable {
    case eyes
    case stretch
    case hydrate

    var id: String { rawValue }

    var intervalSeconds: TimeInterval {
        switch self {
        case .eyes: return 1200
        case .stretch: return 3000
        case .hydrate: return 3600
        }
    }
}

struct BreatherScheduleEngine: Equatable, Sendable {
    var rings: BreatherRings
    var streak: BreatherStreak

    init(
        rings: BreatherRings = BreatherRings(
            eyes: BreatherRingProgress(completed: 0, target: 12),
            stretch: BreatherRingProgress(completed: 0, target: 6),
            hydrate: BreatherRingProgress(completed: 0, target: 8)
        ),
        streak: BreatherStreak = BreatherStreak(count: 0, lastCompletedDate: nil)
    ) {
        self.rings = rings
        self.streak = streak
    }

    /// Evaluates if a reminder prompt should trigger or be suppressed.
    /// Strictly suppressed when camera or microphone is in use, or a call is active.
    static func shouldSuppress(
        cameraInUse: Bool,
        microphoneInUse: Bool,
        callActive: Bool
    ) -> Bool {
        cameraInUse || microphoneInUse || callActive
    }

    /// Logs completion of an activity, advancing the respective ring and updating streaks when all rings are completed.
    mutating func completeActivity(_ type: BreatherActivityType, date: Date = Date(), calendar: Calendar = .current) {
        switch type {
        case .eyes:
            rings.eyes.completed += 1
        case .stretch:
            rings.stretch.completed += 1
        case .hydrate:
            rings.hydrate.completed += 1
        }

        if rings.allCompleted {
            streak.recordCompletion(on: date, calendar: calendar)
        }
    }
}
