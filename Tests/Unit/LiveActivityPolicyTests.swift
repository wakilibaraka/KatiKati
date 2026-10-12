import XCTest
@testable import KatiKati

// Phase 8b-A — pure decision-engine tests for the Now-Playing "Live Island".
//
// These witness the island's priority + rotation rule in isolation: no MediaRemote, no timers, no
// UI. They are the behaviour witness required by §4.2 for the new `LiveActivityPolicy`.

final class LiveActivityPolicyTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Fallback

    /// An empty snapshot always resolves to the clock — the island is never empty.
    func testEmptySnapshotResolvesToClock() {
        let a = LiveActivityPolicy.resolve(LiveActivitySnapshot(now: now))
        XCTAssertEqual(a.kind, .clock)
        XCTAssertEqual(a.content, .clock)
    }

    /// Data present but not "active" (music loaded but paused, focus loaded but stopped, etc.)
    /// must still fall through to the clock.
    func testInactivePayloadsFallThroughToClock() {
        let s = LiveActivitySnapshot(
            music: MusicContent(title: "T", artist: "A", progress: 0.5, hasPrevious: true, hasNext: true),
            musicIsPlaying: false,
            focus: FocusContent(phase: .focus, remaining: 100, progress: 0.1, completedInCycle: 0),
            focusIsRunning: false,
            countdown: CountdownContent(label: "Trip", daysRemaining: 2),
            countdownIsNear: false,
            timer: TimerContent(remaining: 30, total: 60, progress: 0.5),
            timerIsRunning: false,
            stopwatch: StopwatchContent(elapsed: 12),
            stopwatchIsRunning: false,
            now: now
        )
        XCTAssertEqual(LiveActivityPolicy.resolve(s).kind, .clock)
    }

    // MARK: - Priority ordering (music beats everything)

    func testMusicBeatsEverything() {
        let s = LiveActivitySnapshot(
            music: MusicContent(title: "Song", artist: "Band", progress: 0.4, hasPrevious: true, hasNext: true),
            musicIsPlaying: true,
            focus: FocusContent(phase: .focus, remaining: 100, progress: 0.1, completedInCycle: 1),
            focusIsRunning: true,
            countdown: CountdownContent(label: "Trip", daysRemaining: 0),
            countdownIsNear: true,
            timer: TimerContent(remaining: 30, total: 60, progress: 0.5),
            timerIsRunning: true,
            stopwatch: StopwatchContent(elapsed: 5),
            stopwatchIsRunning: true,
            now: now
        )
        let a = LiveActivityPolicy.resolve(s)
        XCTAssertEqual(a.kind, .music)
        XCTAssertEqual(a.content, .music(MusicContent(title: "Song", artist: "Band", progress: 0.4, hasPrevious: true, hasNext: true)))
    }

    /// Music only owns the island while actually playing — a loaded-but-paused track hands off.
    func testPausedMusicHandsOff() {
        let s = LiveActivitySnapshot(
            music: MusicContent(title: "Song", artist: "Band", progress: 0.4, hasPrevious: true, hasNext: true),
            musicIsPlaying: false,
            focus: FocusContent(phase: .shortBreak, remaining: 200, progress: 0.33, completedInCycle: 2),
            focusIsRunning: true,
            now: now
        )
        let a = LiveActivityPolicy.resolve(s)
        XCTAssertEqual(a.kind, .focus)
        XCTAssertEqual(a.content, .focus(FocusContent(phase: .shortBreak, remaining: 200, progress: 0.33, completedInCycle: 2)))
    }

    // MARK: - Focus

    func testFocusBeatsCountdownTimerStopwatch() {
        let s = LiveActivitySnapshot(
            focus: FocusContent(phase: .focus, remaining: 100, progress: 0.1, completedInCycle: 0),
            focusIsRunning: true,
            countdown: CountdownContent(label: "Trip", daysRemaining: 0),
            countdownIsNear: true,
            timer: TimerContent(remaining: 30, total: 60, progress: 0.5),
            timerIsRunning: true,
            stopwatch: StopwatchContent(elapsed: 5),
            stopwatchIsRunning: true,
            now: now
        )
        XCTAssertEqual(LiveActivityPolicy.resolve(s).kind, .focus)
    }


    // MARK: - Countdown + horizon

    func testCountdownWinsWhenNearAndNothingHigher() {
        let s = LiveActivitySnapshot(
            countdown: CountdownContent(label: "Trip", daysRemaining: 3),
            countdownIsNear: true,
            timer: TimerContent(remaining: 30, total: 60, progress: 0.5),
            timerIsRunning: true,
            now: now
        )
        let a = LiveActivityPolicy.resolve(s)
        XCTAssertEqual(a.kind, .countdown)
        XCTAssertEqual(a.content, .countdown(CountdownContent(label: "Trip", daysRemaining: 3)))
    }

    /// A far-future countdown (`countdownIsNear == false`) must not displace the timer/clock.
    func testFarCountdownDoesNotOwnIsland() {
        let s = LiveActivitySnapshot(
            countdown: CountdownContent(label: "Christmas", daysRemaining: 90),
            countdownIsNear: false,
            now: now
        )
        XCTAssertEqual(LiveActivityPolicy.resolve(s).kind, .clock)
    }

    // MARK: - isWithinHorizon boundaries

    func testHorizonBoundaries() {
        XCTAssertTrue(LiveActivityPolicy.isWithinHorizon(daysRemaining: 0), "today is near")
        XCTAssertTrue(LiveActivityPolicy.isWithinHorizon(daysRemaining: LiveActivityPolicy.countdownHorizonDays), "horizon edge is inclusive")
        XCTAssertFalse(LiveActivityPolicy.isWithinHorizon(daysRemaining: LiveActivityPolicy.countdownHorizonDays + 1), "just past horizon is not near")
        XCTAssertFalse(LiveActivityPolicy.isWithinHorizon(daysRemaining: -1), "a past event is not near")
    }

    /// The horizon constant agrees with `isWithinHorizon` at every boundary it implies.
    func testIsWithinHorizonMatchesConstant() {
        let h = LiveActivityPolicy.countdownHorizonDays
        XCTAssertTrue(LiveActivityPolicy.isWithinHorizon(daysRemaining: h))
        XCTAssertFalse(LiveActivityPolicy.isWithinHorizon(daysRemaining: h + 1))
    }

    // MARK: - Timer / stopwatch / clock tail

    func testTimerBeatsStopwatchAndClock() {
        let s = LiveActivitySnapshot(
            timer: TimerContent(remaining: 45, total: 300, progress: 0.85),
            timerIsRunning: true,
            stopwatch: StopwatchContent(elapsed: 99),
            stopwatchIsRunning: true,
            now: now
        )
        let a = LiveActivityPolicy.resolve(s)
        XCTAssertEqual(a.kind, .timer)
        XCTAssertEqual(a.content, .timer(TimerContent(remaining: 45, total: 300, progress: 0.85)))
    }

    func testStopwatchWinsOverClock() {
        let s = LiveActivitySnapshot(
            stopwatch: StopwatchContent(elapsed: 12.5),
            stopwatchIsRunning: true,
            now: now
        )
        let a = LiveActivityPolicy.resolve(s)
        XCTAssertEqual(a.kind, .stopwatch)
        XCTAssertEqual(a.content, .stopwatch(StopwatchContent(elapsed: 12.5)))
    }

    /// A finished (not running) timer must not linger on the island.
    func testFinishedTimerFallsBackToClock() {
        let s = LiveActivitySnapshot(
            timer: TimerContent(remaining: 0, total: 60, progress: 1),
            timerIsRunning: false,
            now: now
        )
        XCTAssertEqual(LiveActivityPolicy.resolve(s).kind, .clock)
    }
}
