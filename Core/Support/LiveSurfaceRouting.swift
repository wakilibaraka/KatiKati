import Foundation

// Phase 8b-5 — the pure router behind "Live Activities on the notch AND the dock, without duplicates".
//
// The Live Island can render on two independent surfaces (the dock capsule and the notch). The
// *ambient* activity (the rotating capsule) is a status display and may show on both. An *event
// notification* (toast, OS banner) is different: showing "Time's up" twice is noise, so each event
// goes to exactly one place by default and the user can opt in to "Both" or turn events off.
//
// Everything here is a pure decision — no AppKit, no timers, no clock reads (the caller passes `now`),
// no user-facing strings — so the whole routing matrix is unit-tested. It is dual-compiled into the
// app + test targets, like `LiveActivityPolicy.swift` / `LiveEventDetector.swift`.

/// A place the Live Island can render.
enum LiveSurface: String, CaseIterable, Sendable {
    case dock
    case notch
}

/// The user's choice of where event notifications show. `automatic` is the default.
enum LiveEventRoute: String, CaseIterable, Sendable {
    /// The notch if it is usable, otherwise the dock.
    case automatic
    case notch
    case dock
    /// Explicit opt-in: every usable surface shows the event.
    case both
    case off
}

enum LiveSurfaceRouting {
    /// Which surfaces should show an event, given the user's route and the surfaces that are
    /// *usable right now* (enabled, present — e.g. a notch panel exists — and not hidden by a
    /// fullscreen window). A chosen-but-unusable surface falls through to the other usable one, so an
    /// event is never lost silently and never doubled unless `.both` was chosen.
    static func targets(route: LiveEventRoute, usable: Set<LiveSurface>) -> Set<LiveSurface> {
        guard !usable.isEmpty else { return [] }
        switch route {
        case .off:
            return []
        case .both:
            return usable
        case .automatic, .notch:
            return usable.contains(.notch) ? [.notch] : [.dock]
        case .dock:
            return usable.contains(.dock) ? [.dock] : [.notch]
        }
    }

    /// Whether an OS Notification Center banner should be posted. Banners are opt-in and are only a
    /// fallback for "no in-app surface showed it" — so turning them on can never double an on-screen
    /// toast. Routing `.off` also silences the banner (the user turned events off).
    static func shouldPostOSBanner(bannersEnabled: Bool, route: LiveEventRoute, shownOn: Set<LiveSurface>) -> Bool {
        bannersEnabled && route != .off && shownOn.isEmpty
    }
}

/// One event's full delivery decision: usable surfaces + the user's route + the cooldown. The app-layer
/// `LiveEventCenter` owns one and only does the showing, so the policy stays in the unit-tested core.
struct LiveEventDispatcher {
    var deduper = LiveEventDeduper()

    /// The surface(s) that should show `event` now — empty when routed off, nothing is usable, or the
    /// event is a repeat inside the cooldown.
    mutating func targets(for event: LiveEvent, route: LiveEventRoute, usable: Set<LiveSurface>, now: Date) -> Set<LiveSurface> {
        let targets = LiveSurfaceRouting.targets(route: route, usable: usable)
        guard !targets.isEmpty, deduper.shouldDeliver(event, now: now) else { return [] }
        return targets
    }
}

/// Refcount for the shared feed's 1 Hz tick: it should run while at least one surface (a dock capsule
/// per display, or the notch) needs it, and not at all otherwise (§4 idle-CPU gate). Each call returns
/// `true` exactly when the tick should start / stop.
struct LiveTickGate {
    private(set) var users = 0
    var isActive: Bool { users > 0 }

    /// A surface appeared. `true` if this is the first one (start the tick).
    mutating func retain() -> Bool {
        users += 1
        return users == 1
    }

    /// A surface went away. `true` if that was the last one (stop the tick); extra releases are ignored.
    mutating func release() -> Bool {
        guard users > 0 else { return false }
        users -= 1
        return users == 0
    }
}

extension LiveEvent {
    /// Identity used to drop a repeat of the same event inside the cooldown window. Payload that
    /// varies without being "a different event" (stopwatch elapsed, timer total) is left out; payload
    /// that makes it a different event (the track, the focus phase, the countdown label) is kept.
    var dedupeKey: String {
        switch self {
        case let .trackChanged(title, artist): return "track|\(title ?? "")|\(artist ?? "")"
        case let .focusPhaseChanged(phase): return "focusPhase|\(phase.rawValue)"
        case let .focusCycleCompleted(count): return "focusCycle|\(count)"
        case .timerFinished: return "timerFinished"
        case .stopwatchStopped: return "stopwatchStopped"
        case let .countdownReachedToday(label): return "countdownToday|\(label)"
        }
    }
}

/// Drops an event that already fired within `cooldown` seconds. Value type: the caller owns one and
/// mutates it, so it needs no locking and tests inject `now`.
struct LiveEventDeduper {
    var cooldown: TimeInterval
    private var lastDelivered: [String: Date] = [:]

    init(cooldown: TimeInterval = 5) {
        self.cooldown = cooldown
    }

    /// `true` if `event` should be delivered now (and records it); `false` if it is a repeat inside
    /// the cooldown window.
    mutating func shouldDeliver(_ event: LiveEvent, now: Date) -> Bool {
        let key = event.dedupeKey
        if let last = lastDelivered[key], now.timeIntervalSince(last) < cooldown {
            return false
        }
        lastDelivered[key] = now
        // Keep the table small: forget anything old enough to be irrelevant.
        if lastDelivered.count > 32 {
            lastDelivered = lastDelivered.filter { now.timeIntervalSince($0.value) < cooldown }
        }
        return true
    }
}
