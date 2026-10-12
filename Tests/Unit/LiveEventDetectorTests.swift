import XCTest
@testable import KatiKati

// Phase 8b-4 (part A) — tests for the pure event detector.
//
// `LiveEventDetector.events(from:to:)` is the whole "what just happened?" rule set: two consecutive
// `LiveActivitySources` snapshots in, a typed event list out. No UI, no permissions, no timers, so
// every transition — and every "quiet" case — is pinned here.

final class LiveEventDetectorTests: XCTestCase {

    // MARK: - Quiet

    /// Identical inputs are never news — the feed must not spam a toast on every steady tick.
    func testIdenticalSnapshotsProduceNoEvents() {
        let s = LiveActivitySources(musicTitle: "Song", musicIsPlaying: true, focusRemaining: 60, focusIsRunning: true, timerRemaining: 30, timerTotal: 300, timerIsRunning: true, stopwatchElapsed: 12, stopwatchIsRunning: true)
        XCTAssertEqual(LiveEventDetector.events(from: s, to: s), [])
    }

    /// The pristine idle snapshot (no music, nothing running) yields nothing.
    func testIdleToIdleProducesNoEvents() {
        XCTAssertEqual(LiveEventDetector.events(from: .idle, to: .idle), [])
    }

    // MARK: - Timer

    /// Running → not running is a finished timer, carrying its length.
    func testTimerFinishedFiresWithTotal() {
        let before = LiveActivitySources(timerRemaining: 1, timerTotal: 300, timerIsRunning: true)
        let after = LiveActivitySources(timerRemaining: 0, timerTotal: 300, timerIsRunning: false)
        XCTAssertEqual(LiveEventDetector.events(from: before, to: after), [.timerFinished(total: 300)])
    }

    /// A zero-length "timer" was never a timer — no event.
    func testZeroLengthTimerDoesNotFire() {
        let before = LiveActivitySources(timerTotal: 0, timerIsRunning: true)
        let after = LiveActivitySources(timerTotal: 0, timerIsRunning: false)
        XCTAssertEqual(LiveEventDetector.events(from: before, to: after), [])
    }

    /// Stopped → stopped is not a transition.
    func testTimerStaysStoppedNoEvent() {
        let s = LiveActivitySources(timerRemaining: 0, timerTotal: 300, timerIsRunning: false)
        XCTAssertEqual(LiveEventDetector.events(from: s, to: s), [])
    }

    // MARK: - Focus

    /// A running session turning over focus → break is the headline focus event.
    func testFocusPhaseTurnoverFires() {
        let before = LiveActivitySources(focusPhase: .focus, focusRemaining: 0, focusIsRunning: true)
        let after = LiveActivitySources(focusPhase: .shortBreak, focusRemaining: 300, focusIsRunning: true)
        XCTAssertEqual(LiveEventDetector.events(from: before, to: after), [.focusPhaseChanged(phase: .shortBreak)])
    }

    /// A session *starting* (nil → focus) is a start, not a turnover — no announcement.
    func testFocusSessionStartIsNotAPhaseChange() {
        let before = LiveActivitySources()
        let after = LiveActivitySources(focusPhase: .focus, focusRemaining: 1500, focusIsRunning: true)
        XCTAssertEqual(LiveEventDetector.events(from: before, to: after), [])
    }

    /// A paused session reporting a stale phase is not a turnover.
    func testStoppedFocusDoesNotFire() {
        let before = LiveActivitySources(focusPhase: .focus, focusIsRunning: false)
        let after = LiveActivitySources(focusPhase: .shortBreak, focusIsRunning: false)
        XCTAssertEqual(LiveEventDetector.events(from: before, to: after), [])
    }

    /// The banked-session counter advancing fires with the new count.
    func testFocusCycleCompletionFires() {
        let before = LiveActivitySources(focusPhase: .focus, focusIsRunning: true, focusCompletedInCycle: 1)
        let after = LiveActivitySources(focusPhase: .shortBreak, focusIsRunning: true, focusCompletedInCycle: 2)
        XCTAssertTrue(LiveEventDetector.events(from: before, to: after).contains(.focusCycleCompleted(completedInCycle: 2)))
    }

    /// A counter that does not advance is silent.
    func testFocusCycleUnchangedNoEvent() {
        let before = LiveActivitySources(focusPhase: .focus, focusIsRunning: true, focusCompletedInCycle: 2)
        let after = LiveActivitySources(focusPhase: .focus, focusRemaining: 100, focusIsRunning: true, focusCompletedInCycle: 2)
        XCTAssertEqual(LiveEventDetector.events(from: before, to: after), [])
    }

    // MARK: - Stopwatch

    /// Running → stopped carries the frozen elapsed time.
    func testStopwatchStoppedFires() {
        let before = LiveActivitySources(stopwatchElapsed: 12, stopwatchIsRunning: true)
        let after = LiveActivitySources(stopwatchElapsed: 13, stopwatchIsRunning: false)
        XCTAssertEqual(LiveEventDetector.events(from: before, to: after), [.stopwatchStopped(elapsed: 13)])
    }

    // MARK: - Countdown

    /// The soonest event arriving at "today" fires once…
    func testCountdownReachedTodayFires() {
        let before = LiveActivitySources(countdownLabel: "Trip", countdownDaysRemaining: 1)
        let after = LiveActivitySources(countdownLabel: "Trip", countdownDaysRemaining: 0)
        XCTAssertEqual(LiveEventDetector.events(from: before, to: after), [.countdownReachedToday(label: "Trip")])
    }

    /// …and not again on the next tick (no all-day re-announce).
    func testCountdownStaysTodayNoRepeatEvent() {
        let s = LiveActivitySources(countdownLabel: "Trip", countdownDaysRemaining: 0)
        XCTAssertEqual(LiveEventDetector.events(from: s, to: s), [])
    }

    // MARK: - Music

    /// A new track while playing announces the change.
    func testTrackChangeFires() {
        let before = LiveActivitySources(musicTitle: "A", musicArtist: "Band", musicIsPlaying: true)
        let after = LiveActivitySources(musicTitle: "B", musicArtist: "Band", musicIsPlaying: true)
        XCTAssertEqual(LiveEventDetector.events(from: before, to: after), [.trackChanged(title: "B", artist: "Band")])
    }

    /// Pausing/resuming the same track is not a change.
    func testSameTrackResumeNoEvent() {
        let paused = LiveActivitySources(musicTitle: "A", musicArtist: "Band", musicIsPlaying: false)
        let playing = LiveActivitySources(musicTitle: "A", musicArtist: "Band", musicIsPlaying: true)
        XCTAssertEqual(LiveEventDetector.events(from: paused, to: playing), [])
    }

    /// An empty track (no title, no artist) is never announced, even though the identity "changed".
    func testEmptyTrackNotAnnounced() {
        let before = LiveActivitySources()
        let after = LiveActivitySources(musicIsPlaying: true)
        XCTAssertEqual(LiveEventDetector.events(from: before, to: after), [])
    }

    // MARK: - Ordering

    /// When several things happen on one tick the list is most-alert-worthy first, so a one-toast UI
    /// shows the finished timer rather than the ambient track change.
    func testTimerOutranksTrackChange() {
        let before = LiveActivitySources(musicTitle: "A", musicIsPlaying: true, timerRemaining: 1, timerTotal: 300, timerIsRunning: true)
        let after = LiveActivitySources(musicTitle: "B", musicIsPlaying: true, timerRemaining: 0, timerTotal: 300, timerIsRunning: false)
        XCTAssertEqual(LiveEventDetector.events(from: before, to: after),
                       [.timerFinished(total: 300), .trackChanged(title: "B", artist: nil)])
    }

    // MARK: - Presentation mapping (8b-4B)

    /// The toast's symbol + data-derived detail per event. The headline is localized, so it is not
    /// asserted here (that would pin one language); the symbol and the numbers are deterministic.

    func testPresentationSymbolsAndDetails() {
        XCTAssertEqual(LiveEventPresentation(.timerFinished(total: 300)).symbol, "timer")
        XCTAssertEqual(LiveEventPresentation(.timerFinished(total: 300)).detail, "5:00")

        XCTAssertEqual(LiveEventPresentation(.stopwatchStopped(elapsed: 13)).symbol, "stopwatch")
        XCTAssertEqual(LiveEventPresentation(.stopwatchStopped(elapsed: 13)).detail, "0:13")

        XCTAssertEqual(LiveEventPresentation(.focusCycleCompleted(completedInCycle: 3)).symbol, "checkmark.circle.fill")
        XCTAssertNil(LiveEventPresentation(.focusCycleCompleted(completedInCycle: 3)).detail)

        XCTAssertEqual(LiveEventPresentation(.countdownReachedToday(label: "Trip")).symbol, "calendar")
        XCTAssertEqual(LiveEventPresentation(.focusPhaseChanged(phase: .shortBreak)).symbol, "brain.head.profile")
    }

    /// The track toast shows the title, falling back to the artist when the stream has no title.
    func testPresentationTrackDetailFallsBackToArtist() {
        XCTAssertEqual(LiveEventPresentation(.trackChanged(title: "A", artist: "Band")).detail, "A")
        XCTAssertEqual(LiveEventPresentation(.trackChanged(title: nil, artist: "Band")).detail, "Band")
        XCTAssertNil(LiveEventPresentation(.trackChanged(title: nil, artist: nil)).detail)
    }
}