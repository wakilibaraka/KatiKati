import Combine
import Foundation

// Phase 8b-2 — the app-layer ticker for the Live Island (app target only).
//
// `LiveActivityPolicy` + `LiveActivitySources` (both pure, Core/Support) decide *which* activity wins
// and how to fold raw values into a snapshot. This type is the only impure part: it reads the real app
// services on a steady tick and publishes the resolved `LiveActivity` for the island UI to render. It
// is the single source of truth for "what the island shows now".
//
// Design:
// - All reads happen on the main actor (every source controller is `@MainActor ObservableObject`).
// - A 1 Hz `Timer` keeps the island *live*: the clock ticks, focus/timer remaining counts down,
//   stopwatch elapsed climbs. The timer runs only while the island is active (`start()`/`stop()`),
//   so idle CPU stays flat when the surface is hidden (§4 proof: idle-CPU gate).
// - The snapshot fold itself lives in the pure `LiveActivitySources` (unit-tested separately); this
//   file only maps the live controllers into those plain values.
//
// Because it touches `NowPlayingService` / `ProductivityServices`, this file is compiled into the app
// target only (like `NowPlayingService.swift`); tests reach it via `@testable import`.

// MARK: - Feed

/// Assembles a `LiveActivitySnapshot` from the real services each tick and publishes the resolved
/// `LiveActivity`. Lives on the main actor; the 1 Hz timer runs only between `start()` and `stop()`.
@MainActor
final class LiveActivityFeed: ObservableObject {
    @Published public private(set) var activity: LiveActivity
    @Published public var isNotchExpanded = false

    private let nowPlaying: NowPlayingService
    private let focus: FocusTimerController
    private let timer: CountdownTimerController
    private let stopwatch: StopwatchController
    private let countdowns: EventCountdownStore

    private var ticker: Timer?
    /// How many rendering surfaces (dock capsule per display, notch) currently need the tick.
    private var tickGate = LiveTickGate()
    private var cancellables = Set<AnyCancellable>()

    /// The one app-wide feed (8b-5). The dock capsule on every display and the notch all read this,
    /// so there is a single 1 Hz timer and a single source of truth no matter how many surfaces are
    /// on. `ProductivityServices.shared` is the precedent for an app-wide `@MainActor` registry.
    static let shared = LiveActivityFeed()

    /// Injected for tests; defaults to the shared registry so the island wiring needs no arguments.
    init(
        nowPlaying: NowPlayingService = NowPlayingService(),
        focus: FocusTimerController = ProductivityServices.shared.focus,
        timer: CountdownTimerController = ProductivityServices.shared.timer,
        stopwatch: StopwatchController = ProductivityServices.shared.stopwatch,
        countdowns: EventCountdownStore = ProductivityServices.shared.countdowns
    ) {
        self.nowPlaying = nowPlaying
        self.focus = focus
        self.timer = timer
        self.stopwatch = stopwatch
        self.countdowns = countdowns
        self.activity = LiveActivityPolicy.resolve(LiveActivitySnapshot(now: Date()))

        // Phase 33 addition: Wire instant reactive updates when nowPlaying or any productivity source changes
        sourceChanges()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    deinit { ticker?.invalidate() }

    /// Begin the live tick. Safe to call twice (idempotent).
    func start() {
        guard ticker == nil else { return }
        refresh()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // Common run-loop mode so the island keeps ticking while menus/tracking are open.
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    /// Stop the live tick (idle-CPU gate: no timer while the surface is hidden).
    func stop() {
        ticker?.invalidate(); ticker = nil
    }

    /// A surface appeared and needs the tick. The timer runs while at least one surface holds the
    /// feed, so two displays or the dock plus the notch share one timer, and none runs when all are off.
    func retain() {
        if tickGate.retain() { start() }
    }

    /// A surface went away. Pairs with `retain()`; extra releases are ignored.
    func release() {
        if tickGate.release() { stop() }
    }

    /// Whether the tick is running (diagnostics).
    var isTicking: Bool { ticker != nil }

    /// Re-read every source and republish. Also callable on demand (e.g. right before showing the
    /// island so the first frame is already current).
    func refresh() {
        activity = LiveActivityPolicy.resolve(sources(at: Date()).snapshot(now: Date()))
    }

    // MARK: - Transport (island capsule affordance)

    /// The raw Now-Playing state, for the island's music popup (theme, album art, transport). The
    /// capsule itself renders the resolved `activity`; this is only for the popup's richer view.
    var nowPlayingState: NowPlayingState { nowPlaying.state }

    /// Play/pause pass-through for the capsule's one affordance (music only). Refreshes immediately
    /// so the popup/capsule can flip without waiting a full tick; MediaRemote's own async update
    /// settles the final state on the next tick.
    func nextTrack() { nowPlaying.nextTrack(); refresh() }
    func previousTrack() { nowPlaying.previousTrack(); refresh() }

    func togglePlayPause() {
        nowPlaying.togglePlayPause()
        refresh()
    }

    func play() {
        nowPlaying.play()
        refresh()
    }

    func pause() {
        nowPlaying.pause()
        refresh()
    }

    func seek(to seconds: Double) {
        nowPlaying.seek(to: seconds)
        refresh()
    }

    // MARK: - Change notification (for the event feed)

    /// Fires whenever any source controller publishes a change. The app-level `LiveEventCenter`
    /// subscribes to this instead of polling, so the Live Island's event feed costs zero idle CPU
    /// (the §4 idle-CPU posture: no timer, no wakeups when nothing moves).
    ///
    /// Emissions are *will*-change, so an observer must read the sources on a later run-loop turn —
    /// the centre does exactly that with `.receive(on: DispatchQueue.main)`.
    func sourceChanges() -> AnyPublisher<Void, Never> {
        Publishers.MergeMany(
            nowPlaying.objectWillChange,
            focus.objectWillChange,
            timer.objectWillChange,
            stopwatch.objectWillChange,
            countdowns.objectWillChange
        )
        .map { _ in () }
        .eraseToAnyPublisher()
    }

    // MARK: - Source mapping (pure, testable)

    /// Translate the live controllers into `LiveActivitySources`. Reads only; no mutation.
    func sources(at now: Date) -> LiveActivitySources {
        // Music
        let state = nowPlaying.state

        // Focus / Pomodoro
        let focusModel = focus.model

        // Event countdown: soonest upcoming (>= 0 days).
        var countdownLabel: String?
        var countdownDays: Int?
        let upcoming = countdowns.events
            .map { (label: $0.label, days: $0.daysRemaining(from: now)) }
            .filter { $0.days >= 0 }
            .min { $0.days < $1.days }
        if let u = upcoming { countdownLabel = u.label; countdownDays = u.days }

        // Countdown timer
        let timerModel = timer.model

        // Stopwatch (elapsed computed against `now` so the feed is live between controller ticks).
        let stopwatchModel = stopwatch.model

        return LiveActivitySources(
            musicTitle: state.title,
            musicArtist: state.artist,
            musicIsPlaying: state.isPlaying,
            focusPhase: focusModel.isRunning ? focusModel.phase : nil,
            focusRemaining: focusModel.remaining,
            focusIsRunning: focusModel.isRunning,
            focusCompletedInCycle: focusModel.completedInCycle,
            countdownLabel: countdownLabel,
            countdownDaysRemaining: countdownDays,
            timerRemaining: timerModel.remaining,
            timerTotal: timerModel.total,
            timerIsRunning: timerModel.isRunning && !timerModel.isFinished,
            stopwatchElapsed: stopwatchModel.elapsed(at: now),
            stopwatchIsRunning: stopwatchModel.isRunning
        )
    }
}
