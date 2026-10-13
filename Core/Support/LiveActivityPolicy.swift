import Foundation

// Phase 8b-A — the pure decision engine behind the Now-Playing "Live Island".
//
// The island is a single capsule that always shows the *most relevant* live activity. This file
// decides **which** one wins, given a snapshot of every candidate. It is deliberately pure: no UI,
// no AppKit, no MediaRemote, no EventKit, no timers, no notifications. That makes the whole
// priority + rotation rule unit-testable (see `LiveActivityPolicyTests`) and keeps the private-API
// and TCC surfaces out of the test path.
//
// The plan's rotation order (HYBRID_PLAN §8b) is the priority order here, highest first:
//   music (playing) → focus/pomodoro (running) → event countdown (near) → countdown timer (running)
//   → stopwatch (running) → live clock (always-available fallback).
//
// No user-facing strings live here. This is data only; the UI layer maps `kind`/content to a
// localized label and an SF Symbol. `trackTitle`/`trackArtist`/`countdownLabel` are real metadata
// the user typed or the OS reported — not translatable copy.

// MARK: - The activities that can own the island

/// What is currently on the island. Ordered by priority (lower raw value = higher priority) so a
/// simple `<` compares "which activity should win".
enum LiveActivityKind: Int, CaseIterable, Sendable, Comparable {
    /// A track is playing (MediaRemote). Highest priority — the island is, first and foremost, Now Playing.
    case music
    /// A Pomodoro/focus session is running.
    case focus
    /// An event countdown is upcoming within the horizon.
    case countdown
    /// A countdown timer is running.
    case timer
    /// The stopwatch is running.
    case stopwatch
    /// Always-available fallback: the live clock.
    case clock

    static func < (lhs: LiveActivityKind, rhs: LiveActivityKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The Pomodoro/focus phase, mirroring `FocusTimerModel.Phase` without importing its UI-free sibling
/// (kept independent so the policy stays a leaf with no cross-file coupling).
enum LiveFocusPhase: Int, Sendable {
    case focus
    case shortBreak
    case longBreak
}

// MARK: - Per-activity content (exhaustive; only the winning kind's payload is non-nil)

struct MusicContent: Equatable, Sendable {
    /// Track title as reported by MediaRemote (may be nil for a stream with no title).
    let title: String?
    let artist: String?
    /// Playback position 0…1, or nil when the app reports no duration.
    let progress: Double?
    /// Whether a previous/next track is available (transport-button state).
    let hasPrevious: Bool
    let hasNext: Bool
}

struct FocusContent: Equatable, Sendable {
    let phase: LiveFocusPhase
    /// Seconds left in the current phase.
    let remaining: Int
    /// 0…1 progress through the current phase.
    let progress: Double
    /// Focus sessions completed in the current cycle (drives the lit-dot row).
    let completedInCycle: Int
}

struct CountdownContent: Equatable, Sendable {
    /// The event's user-given label.
    let label: String
    /// Whole calendar days until the event (0 = today).
    let daysRemaining: Int
}

struct TimerContent: Equatable, Sendable {
    let remaining: Int
    let total: Int
    /// 0…1 progress.
    let progress: Double
}

struct StopwatchContent: Equatable, Sendable {
    /// Elapsed seconds.
    let elapsed: TimeInterval
}

// MARK: - Snapshot (what the app layer assembles from its services each tick)

/// A point-in-time snapshot of every candidate activity. The app layer builds this from
/// `NowPlayingService`, `FocusTimerController`, `EventCountdownStore`, `CountdownTimerController`
/// and `StopwatchController`; the policy never touches those types directly.
struct LiveActivitySnapshot: Equatable, Sendable {
    var music: MusicContent?
    /// `true` only while a track is actually playing (MediaRemote rate > 0).
    var musicIsPlaying: Bool

    var focus: FocusContent?
    var focusIsRunning: Bool

    /// The soonest upcoming event countdown, if any (nil when none are set).
    var countdown: CountdownContent?
    /// Whether that countdown should be considered "near" enough to show. The app layer can compute
    /// this however it likes; when in doubt it can use `LiveActivityPolicy.isWithinHorizon(days:)`.
    var countdownIsNear: Bool

    var timer: TimerContent?
    var timerIsRunning: Bool

    var stopwatch: StopwatchContent?
    var stopwatchIsRunning: Bool

    /// The current instant, carried so the clock fallback and day math are reproducible in tests.
    var now: Date

    init(
        music: MusicContent? = nil,
        musicIsPlaying: Bool = false,
        focus: FocusContent? = nil,
        focusIsRunning: Bool = false,
        countdown: CountdownContent? = nil,
        countdownIsNear: Bool = false,
        timer: TimerContent? = nil,
        timerIsRunning: Bool = false,
        stopwatch: StopwatchContent? = nil,
        stopwatchIsRunning: Bool = false,
        now: Date = Date()
    ) {
        self.music = music
        self.musicIsPlaying = musicIsPlaying
        self.focus = focus
        self.focusIsRunning = focusIsRunning
        self.countdown = countdown
        self.countdownIsNear = countdownIsNear
        self.timer = timer
        self.timerIsRunning = timerIsRunning
        self.stopwatch = stopwatch
        self.stopwatchIsRunning = stopwatchIsRunning
        self.now = now
    }
}

// MARK: - The resolved island

/// The single activity the island should show, plus its typed payload. `kind` is the authoritative
/// "what wins" signal; `content` carries the data for that kind (all other cases are the empty
/// `.clock` case). UI switches on `content` to render.
struct LiveActivity: Equatable, Sendable {
    let kind: LiveActivityKind
    let content: Content

    enum Content: Equatable, Sendable {
        case music(MusicContent)
        case focus(FocusContent)
        case countdown(CountdownContent)
        case timer(TimerContent)
        case stopwatch(StopwatchContent)
        case clock
    }
}

// MARK: - Policy

enum LiveActivityPolicy {
    /// A countdown further out than this many days does not own the island — a "Christmas in 90
    /// days" should never permanently replace the clock. Today (0) through `countdownHorizonDays`
    /// inclusive still show. Tuning knob; witnessed in tests.
    public static let countdownHorizonDays = 7

    /// Whether a countdown `daysRemaining` away is near enough to surface on the island.
    public static func isWithinHorizon(daysRemaining: Int) -> Bool {
        daysRemaining >= 0 && daysRemaining <= countdownHorizonDays
    }

    /// Resolve the highest-priority live activity from a snapshot. Pure and total: always returns
    /// something (worst case `.clock`).
    public static func resolve(_ s: LiveActivitySnapshot) -> LiveActivity {
        // 1. Music — only while actually playing.
        if s.musicIsPlaying, let music = s.music {
            return LiveActivity(kind: .music, content: .music(music))
        }
        // 2. Focus / Pomodoro — while running.
        if s.focusIsRunning, let focus = s.focus {
            return LiveActivity(kind: .focus, content: .focus(focus))
        }
        // 3. Event countdown — only when near.
        if s.countdownIsNear, let countdown = s.countdown {
            return LiveActivity(kind: .countdown, content: .countdown(countdown))
        }
        // 4. Countdown timer — while running (a finished timer is transient; the feed announces it).
        if s.timerIsRunning, let timer = s.timer {
            return LiveActivity(kind: .timer, content: .timer(timer))
        }
        // 5. Stopwatch — while running.
        if s.stopwatchIsRunning, let stopwatch = s.stopwatch {
            return LiveActivity(kind: .stopwatch, content: .stopwatch(stopwatch))
        }
        // 6. Live clock — always available.
        return LiveActivity(kind: .clock, content: .clock)
    }
}


// MARK: - Dock capsule idle actions (Phase 10c-1)

/// What the dock Live Island chip offers when nothing is live (the policy's `.clock` fallback). The chip
/// no longer draws the time — the time capsule owns that — so the idle state is these quick actions.
enum LiveIdleAction: CaseIterable, Sendable {
    case focus
    case timer
    case keepAwake

    var symbolName: String {
        switch self {
        case .focus: return "brain.head.profile"
        case .timer: return "timer"
        case .keepAwake: return "cup.and.saucer"
        }
    }

    /// Default length a one-tap timer starts with.
    static let quickTimerSeconds = 5 * 60

    /// The dock chip shows idle actions exactly when the winning activity is the clock fallback.
    static func showsIdleActions(for kind: LiveActivityKind) -> Bool { kind == .clock }
}

extension LiveActivity {
    /// 0…1 ring around the dock chip glyph: focus phase, running timer, or track position. Nil when
    /// the activity has no meaningful progress (clock, stopwatch, countdown, a stream with no duration).
    var ringProgress: Double? {
        let raw: Double?
        switch content {
        case .focus(let focus): raw = focus.progress
        case .timer(let timer): raw = timer.progress
        case .music(let music): raw = music.progress
        case .countdown, .stopwatch, .clock: raw = nil
        }
        return raw.map { min(1, max(0, $0)) }
    }
}
