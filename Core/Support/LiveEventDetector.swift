import Foundation

// Phase 8b-4 (part A) — the pure "what just happened?" engine behind the Live Island's event feed.
//
// `LiveActivityPolicy` answers "what is the island showing *now*"; this answers "what *changed* since
// the last tick, and is it worth telling the user about". It compares two consecutive source
// snapshots (`LiveActivitySources` — the same value type the 1 Hz feed already builds) and returns the
// typed events that fired.
//
// Pure and total: no UI, no AppKit, no `UNUserNotificationCenter`, no clock reads, no timers. Identical
// inputs always yield `[]`. That keeps every transition rule unit-testable and lets the app layer
// decide *how* to surface an event — an in-app island toast by default (8b-4 part B), an opt-in OS
// banner later (8b-4 part C). Because it is pure it is dual-compiled into the app + test targets,
// exactly like `LiveActivityPolicy.swift` / `LiveActivitySources.swift`.
//
// Deliberately deferred (they need sources the island does not have yet — see HYBRID_PLAN §8b-B):
// Reminder/Alarm due and Weather severe alert. They slot in as extra `LiveEvent` cases when those
// sources land; nothing here needs to change shape to accept them.

/// A live event worth surfacing on the island. Data only: the UI maps each kind to a localized string
/// + SF Symbol, and the OS-banner tier maps a subset to a `UNNotificationRequest`.
enum LiveEvent: Equatable, Sendable {
    /// The playing track's identity changed (or music started with a track).
    case trackChanged(title: String?, artist: String?)
    /// The focus/pomodoro phase turned over (focus→break, break→focus).
    case focusPhaseChanged(phase: LiveFocusPhase)
    /// A focus session was banked (the cycle counter advanced).
    case focusCycleCompleted(completedInCycle: Int)
    /// A countdown timer ran out.
    case timerFinished(total: Int)
    /// The stopwatch was stopped.
    case stopwatchStopped(elapsed: TimeInterval)
    /// The soonest upcoming event arrived at "today".
    case countdownReachedToday(label: String)
}

enum LiveEventDetector {
    /// Events that fired between `previous` and `current`, most-alert-worthy first (so a UI that can
    /// only show one toast at a time shows the important one).
    static func events(from previous: LiveActivitySources, to current: LiveActivitySources) -> [LiveEvent] {
        var out: [LiveEvent] = []

        if let finished = timerFinished(from: previous, to: current) { out.append(finished) }
        if let phase = focusPhaseChanged(from: previous, to: current) { out.append(phase) }
        if let cycle = focusCycleCompleted(from: previous, to: current) { out.append(cycle) }
        if let stopped = stopwatchStopped(from: previous, to: current) { out.append(stopped) }
        if let reached = countdownReachedToday(from: previous, to: current) { out.append(reached) }
        if let track = trackChanged(from: previous, to: current) { out.append(track) }

        return out
    }

    // MARK: - Rules (one function each; every boundary is unit-tested)

    /// A timer that was running and is no longer running (and actually had a length) has finished. A
    /// zero-length timer is not an event (there is no "timer" to finish).
    private static func timerFinished(from previous: LiveActivitySources, to current: LiveActivitySources) -> LiveEvent? {
        guard previous.timerIsRunning, !current.timerIsRunning else { return nil }
        let total = current.timerTotal > 0 ? current.timerTotal : previous.timerTotal
        guard total > 0 else { return nil }
        return .timerFinished(total: total)
    }

    /// The phase turned over while the session stayed running. A `nil` on either side is a start/stop,
    /// not a turnover — announcing "focus" the moment a session begins is noise, not news. Phases are
    /// compared through the island's own enum so this stays independent of `FocusTimerModel.Phase`'s
    /// conformance.
    private static func focusPhaseChanged(from previous: LiveActivitySources, to current: LiveActivitySources) -> LiveEvent? {
        guard let before = previous.focusPhase, let after = current.focusPhase else { return nil }
        guard current.focusIsRunning else { return nil }
        let beforeBridged = LiveFocusPhase(phase: before)
        let afterBridged = LiveFocusPhase(phase: after)
        guard beforeBridged != afterBridged else { return nil }
        return .focusPhaseChanged(phase: afterBridged)
    }

    /// The completed-in-cycle counter advanced (a session was banked). Fires once with the new count,
    /// even if the counter jumped by more than one.
    private static func focusCycleCompleted(from previous: LiveActivitySources, to current: LiveActivitySources) -> LiveEvent? {
        guard current.focusCompletedInCycle > previous.focusCompletedInCycle else { return nil }
        return .focusCycleCompleted(completedInCycle: current.focusCompletedInCycle)
    }

    /// The stopwatch was running and is no longer running. Elapsed is read from `current` (it freezes
    /// when the stopwatch stops).
    private static func stopwatchStopped(from previous: LiveActivitySources, to current: LiveActivitySources) -> LiveEvent? {
        guard previous.stopwatchIsRunning, !current.stopwatchIsRunning else { return nil }
        return .stopwatchStopped(elapsed: current.stopwatchElapsed)
    }

    /// The soonest upcoming event arrived at "today" (`0` days). Fires on the tick it becomes today, or
    /// when a *different* event that is already today becomes the soonest — but not again on every
    /// subsequent tick, so a day-long event does not re-announce itself all day.
    private static func countdownReachedToday(from previous: LiveActivitySources, to current: LiveActivitySources) -> LiveEvent? {
        guard current.countdownDaysRemaining == 0, let label = current.countdownLabel else { return nil }
        let alreadyAnnounced = previous.countdownDaysRemaining == 0 && previous.countdownLabel == label
        guard !alreadyAnnounced else { return nil }
        return .countdownReachedToday(label: label)
    }

    /// The playing track's identity changed. Starting music with a track counts as a change (the
    /// previous identity is `nil`), so "now playing" is announced once; pausing and resuming the *same*
    /// track is not a change, and a truly empty track (no title and no artist) is not announced.
    private static func trackChanged(from previous: LiveActivitySources, to current: LiveActivitySources) -> LiveEvent? {
        guard current.musicIsPlaying else { return nil }
        guard current.musicTitle != nil || current.musicArtist != nil else { return nil }
        let changed = previous.musicTitle != current.musicTitle || previous.musicArtist != current.musicArtist
        guard changed else { return nil }
        return .trackChanged(title: current.musicTitle, artist: current.musicArtist)
    }
}
