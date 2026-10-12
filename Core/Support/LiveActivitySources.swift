import Foundation

// Phase 8b-A — the pure source projection and phase-bridge behind the Live Island.
//
// This file is deliberately pure (no AppKit, no MainActor, no MediaRemote, no timers): it holds the
// flat `LiveActivitySources` value type the app-layer assembler fills in, the fold that turns it into
// the pure `LiveActivitySnapshot` the policy consumes, and the `FocusTimerModel.Phase` →
// `LiveFocusPhase` bridge. Because it is pure it is dual-compiled into the app target and the test
// target, exactly like `LiveActivityPolicy.swift` / `CalendarPanelModels.swift`.
//
// The app-layer ticker that reads the real controllers lives in `App/Composition/LiveActivityFeed.swift`
// (app-only) — see that file for the live wiring.

/// A read-only projection of every source the island needs at one instant. Keeping this as plain
/// values (rather than passing the controllers into `LiveActivityPolicy`) means the pure policy never
/// learns about AppKit/MainActor/MediaRemote, and the assembler's mapping is trivially testable.
struct LiveActivitySources {
    var musicTitle: String? = nil
    var musicArtist: String? = nil
    var musicIsPlaying: Bool = false

    var focusPhase: FocusTimerModel.Phase? = nil
    var focusRemaining: Int = 0
    var focusIsRunning: Bool = false
    var focusCompletedInCycle: Int = 0

    /// The soonest upcoming event countdown (already filtered to `daysRemaining >= 0`), or nil.
    var countdownLabel: String? = nil
    var countdownDaysRemaining: Int? = nil

    var timerRemaining: Int = 0
    var timerTotal: Int = 0
    var timerIsRunning: Bool = false

    var stopwatchElapsed: TimeInterval = 0
    var stopwatchIsRunning: Bool = false

    static let idle = LiveActivitySources()

    /// Fold the raw source values into the pure `LiveActivitySnapshot` the policy consumes. Mirrors
    /// the same priority/horizon rules the policy enforces, but only to decide the boolean flags
    /// (e.g. `countdownIsNear`) — the policy re-checks and remains authoritative.
    func snapshot(now: Date) -> LiveActivitySnapshot {
        var music: MusicContent?
        if musicTitle != nil || musicArtist != nil {
            music = MusicContent(title: musicTitle, artist: musicArtist, progress: nil, hasPrevious: true, hasNext: true)
        }

        var focus: FocusContent?
        if let phase = focusPhase {
            let duration = FocusTimerModel.duration(of: phase)
            let progress = duration > 0 ? 1 - Double(focusRemaining) / Double(duration) : 0
            focus = FocusContent(
                phase: LiveFocusPhase(phase: phase),
                remaining: focusRemaining,
                progress: max(0, min(1, progress)),
                completedInCycle: focusCompletedInCycle
            )
        }

        var countdown: CountdownContent?
        var countdownIsNear = false
        if let label = countdownLabel, let days = countdownDaysRemaining {
            countdown = CountdownContent(label: label, daysRemaining: days)
            countdownIsNear = LiveActivityPolicy.isWithinHorizon(daysRemaining: days)
        }

        let timerProgress = timerTotal > 0 ? max(0, min(1, 1 - Double(timerRemaining) / Double(timerTotal))) : 0
        let timer = TimerContent(remaining: timerRemaining, total: timerTotal, progress: timerProgress)

        let stopwatch = StopwatchContent(elapsed: stopwatchElapsed)

        return LiveActivitySnapshot(
            music: music,
            musicIsPlaying: musicIsPlaying,
            focus: focus,
            focusIsRunning: focusIsRunning,
            countdown: countdown,
            countdownIsNear: countdownIsNear,
            timer: timer,
            timerIsRunning: timerIsRunning,
            stopwatch: stopwatch,
            stopwatchIsRunning: stopwatchIsRunning,
            now: now
        )
    }
}

// MARK: - Focus phase bridge

extension LiveFocusPhase {
    /// Bridges the app/focus model's phase into the island's own phase enum.
    init(phase: FocusTimerModel.Phase) {
        switch phase {
        case .focus: self = .focus
        case .shortBreak: self = .shortBreak
        case .longBreak: self = .longBreak
        }
    }
}

// MARK: - Display formatting (pure, testable)

/// Rendering helpers for the capsule's *kinetic numbers* (focus/timer remaining, stopwatch elapsed).
///
/// These are **data, not copy**: the UI renders them through `Text(verbatim:)` / a plain `String`
/// variable, never `Text("…")` with interpolation — the localization gate scans `Text("literal")`
/// and would read an interpolated literal as a missing catalog key (a pattern the repo banned in the
/// earlier localization sweep). Pure and total, so the rollover + clamping rules are unit-testable
/// without a view.
enum LiveIslandFormat {
    /// `m:ss` under an hour, `h:mm:ss` at/after an hour. Negative input clamps to `0:00` — a focus
    /// timer can briefly report `-1` on the tick it crosses zero, and the capsule must never render
    /// `-1:-1`.
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let hours = s / 3600
        let minutes = (s % 3600) / 60
        let secs = s % 60
        func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        return hours > 0
            ? "\(hours):\(pad(minutes)):\(pad(secs))"
            : "\(minutes):\(pad(secs))"
    }

    /// The stopwatch reading, truncating fractional seconds to whole seconds (0.9s should read
    /// `0:00`, like a real stopwatch, not round up to `0:01`). Non-finite input can't crash the tick
    /// (`Int(nan)` traps), so it is guarded back to `0:00`.
    static func stopwatch(_ elapsed: TimeInterval) -> String {
        guard elapsed.isFinite else { return clock(0) }
        return clock(Int(elapsed))
    }
}
