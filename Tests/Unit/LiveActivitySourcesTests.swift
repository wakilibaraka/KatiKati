import XCTest
@testable import KatiKati

// Phase 8b-2 — tests for the app-layer snapshot fold (`LiveActivitySources.snapshot`).
//
// `LiveActivityFeed` reads live `@MainActor` controllers (MediaRemote + timers) that are not
// injectable state, so we test the pure fold: raw source values → `LiveActivitySnapshot` → the
// policy's resolve. That is where the mapping rules live (horizon flag, progress clamps, phase
// bridge, timer-finished guard). End-to-end wiring is witnessed by later slices' eyeball.

final class LiveActivitySourcesTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Music

    /// Music fields flow through; a title-less stream still builds a (nil-title) payload so the
    /// policy can show "playing" state.
    func testMusicPayloadCarriesTitleArtist() {
        let snap = LiveActivitySources(musicTitle: "Song", musicArtist: "Band", musicIsPlaying: true).snapshot(now: now)
        XCTAssertEqual(snap.music?.title, "Song")
        XCTAssertEqual(snap.music?.artist, "Band")
        XCTAssertTrue(snap.musicIsPlaying)
        XCTAssertNil(snap.music?.progress, "no MediaRemote duration yet — progress is nil, not faked")
    }

    /// No music metadata at all → nil payload, so the policy falls through.
    func testNoMusicProducesNilPayload() {
        let snap = LiveActivitySources.idle.snapshot(now: now)
        XCTAssertNil(snap.music)
        XCTAssertFalse(snap.musicIsPlaying)
    }

    // MARK: - Focus

    /// Focus phase bridges into the policy's enum, progress is computed + clamped 0…1.
    func testFocusPhaseBridgeAndProgress() {
        let snap = LiveActivitySources(
            focusPhase: FocusTimerModel.Phase.shortBreak, focusRemaining: 60, focusIsRunning: true, focusCompletedInCycle: 2
        ).snapshot(now: now)
        guard case .focus(let c) = LiveActivityPolicy.resolve(snap).content else {
            return XCTFail("expected focus content")
        }
        XCTAssertEqual(c.phase, .shortBreak)
        XCTAssertEqual(c.remaining, 60)
        XCTAssertEqual(c.completedInCycle, 2)
        // shortBreak = 300s; 60 remaining → progress 0.8.
        XCTAssertEqual(c.progress, 0.8, accuracy: 0.001)
    }

    /// A paused focus session reports `focusPhase == nil` at the assembler level, so it cannot win.
    func testPausedFocusHasNoPhase() {
        let snap = LiveActivitySources(focusPhase: nil, focusRemaining: 300, focusIsRunning: false).snapshot(now: now)
        XCTAssertNil(snap.focus)
        XCTAssertFalse(snap.focusIsRunning)
    }

    // MARK: - Countdown horizon flag

    /// A near countdown sets `countdownIsNear` true (the feed mirrors the policy's horizon).
    func testNearCountdownFlaggedNear() {
        let snap = LiveActivitySources(countdownLabel: "Trip", countdownDaysRemaining: 3).snapshot(now: now)
        XCTAssertTrue(snap.countdownIsNear)
        XCTAssertEqual(snap.countdown?.label, "Trip")
        XCTAssertEqual(snap.countdown?.daysRemaining, 3)
    }

    /// A far countdown (beyond the 7-day horizon) is flagged not-near, so the policy ignores it.
    func testFarCountdownFlaggedNotNear() {
        let snap = LiveActivitySources(countdownLabel: "Christmas", countdownDaysRemaining: 90).snapshot(now: now)
        XCTAssertFalse(snap.countdownIsNear)
        XCTAssertEqual(LiveActivityPolicy.resolve(snap).kind, .clock)
    }

    /// No countdown → nil + not near.
    func testNoCountdown() {
        let snap = LiveActivitySources.idle.snapshot(now: now)
        XCTAssertNil(snap.countdown)
        XCTAssertFalse(snap.countdownIsNear)
    }

    // MARK: - Timer progress clamp

    /// Timer progress is computed and clamped; the finished guard lives in the feed (`isRunning &&
    /// !isFinished`), so a running timer here is honoured.
    func testTimerProgressClamped() {
        let snap = LiveActivitySources(timerRemaining: 30, timerTotal: 300, timerIsRunning: true).snapshot(now: now)
        let a = LiveActivityPolicy.resolve(snap)
        XCTAssertEqual(a.kind, .timer)
        XCTAssertEqual(a.content, LiveActivity.Content.timer(TimerContent(remaining: 30, total: 300, progress: 0.9)))
    }

    /// total == 0 must not divide by zero — progress clamps to 0.
    func testTimerZeroTotalNoNaN() {
        let snap = LiveActivitySources(timerRemaining: 0, timerTotal: 0, timerIsRunning: true).snapshot(now: now)
        guard case .timer(let c) = LiveActivityPolicy.resolve(snap).content else {
            return XCTFail("expected timer content")
        }
        XCTAssertEqual(c.progress, 0)
    }

    // MARK: - Stopwatch passthrough

    func testStopwatchElapsedPassthrough() {
        let snap = LiveActivitySources(stopwatchElapsed: 42.5, stopwatchIsRunning: true).snapshot(now: now)
        let a = LiveActivityPolicy.resolve(snap)
        XCTAssertEqual(a.kind, .stopwatch)
        XCTAssertEqual(a.content, LiveActivity.Content.stopwatch(StopwatchContent(elapsed: 42.5)))
    }

    // MARK: - Focus phase bridge exhaustive

    /// Every `FocusTimerModel.Phase` maps to the matching `LiveFocusPhase`.
    func testFocusPhaseBridgeAllCases() {
        XCTAssertEqual(LiveFocusPhase(phase: .focus), .focus)
        XCTAssertEqual(LiveFocusPhase(phase: .shortBreak), .shortBreak)
        XCTAssertEqual(LiveFocusPhase(phase: .longBreak), .longBreak)
    }

    // MARK: - LiveIslandFormat (kinetic numbers in the capsule)

    /// Sub-minute readings pad to `m:ss` (a stopwatch reads `0:00` at rest, never `:0`).
    func testFormatClockSubMinutePads() {
        XCTAssertEqual(LiveIslandFormat.clock(0), "0:00")
        XCTAssertEqual(LiveIslandFormat.clock(5), "0:05")
        XCTAssertEqual(LiveIslandFormat.clock(59), "0:59")
    }

    /// Minute + hour rollover: 60s is `1:00`, 3599 is `59:59`, 3600 promotes to `1:00:00`.
    func testFormatClockRollover() {
        XCTAssertEqual(LiveIslandFormat.clock(60), "1:00")
        XCTAssertEqual(LiveIslandFormat.clock(3599), "59:59")
        XCTAssertEqual(LiveIslandFormat.clock(3600), "1:00:00")
        XCTAssertEqual(LiveIslandFormat.clock(3661), "1:01:01")
    }

    /// A focus timer can report a small negative on the tick it crosses zero — the capsule must
    /// clamp, never render `-1:-1`.
    func testFormatClockClampsNegative() {
        XCTAssertEqual(LiveIslandFormat.clock(-1), "0:00")
        XCTAssertEqual(LiveIslandFormat.clock(-3600), "0:00")
    }

    /// The stopwatch truncates fractional seconds (0.9s is `0:00`, not `0:01`).
    func testFormatStopwatchTruncates() {
        XCTAssertEqual(LiveIslandFormat.stopwatch(0), "0:00")
        XCTAssertEqual(LiveIslandFormat.stopwatch(5.9), "0:05")
        XCTAssertEqual(LiveIslandFormat.stopwatch(59.99), "0:59")
    }

    /// Non-finite elapsed can't crash the tick (`Int(nan)` traps) — it falls back to `0:00`.
    func testFormatStopwatchNonFiniteIsSafe() {
        XCTAssertEqual(LiveIslandFormat.stopwatch(.nan), "0:00")
        XCTAssertEqual(LiveIslandFormat.stopwatch(.infinity), "0:00")
    }
}
