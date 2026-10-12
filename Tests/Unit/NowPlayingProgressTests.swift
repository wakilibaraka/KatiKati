import XCTest
@testable import KatiKati

// Phase 8b-6 — pure playback-progress maths.

final class NowPlayingProgressTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testPlayingExtrapolatesFromTimestamp() {
        let f = NowPlayingProgress.fraction(at: t0.addingTimeInterval(10), elapsed: 20, asOf: t0, rate: 1, duration: 100)
        XCTAssertEqual(f ?? -1, 0.30, accuracy: 1e-9)
    }

    func testPausedDoesNotAdvance() {
        let f = NowPlayingProgress.fraction(at: t0.addingTimeInterval(500), elapsed: 20, asOf: t0, rate: 0, duration: 100)
        XCTAssertEqual(f ?? -1, 0.20, accuracy: 1e-9)
    }

    func testClampedToTrackLength() {
        XCTAssertEqual(NowPlayingProgress.fraction(at: t0.addingTimeInterval(999), elapsed: 90, asOf: t0, rate: 1, duration: 100), 1)
        XCTAssertEqual(NowPlayingProgress.elapsed(at: t0.addingTimeInterval(999), elapsed: 90, asOf: t0, rate: 1, duration: 100), 100)
    }

    func testUnknownOrZeroDurationHasNoFraction() {
        XCTAssertNil(NowPlayingProgress.fraction(at: t0, elapsed: 5, asOf: t0, rate: 1, duration: nil))
        XCTAssertNil(NowPlayingProgress.fraction(at: t0, elapsed: 5, asOf: t0, rate: 1, duration: 0))
    }

    func testMissingOrBadElapsedHasNoFraction() {
        XCTAssertNil(NowPlayingProgress.fraction(at: t0, elapsed: nil, asOf: t0, rate: 1, duration: 100))
        XCTAssertNil(NowPlayingProgress.fraction(at: t0, elapsed: -3, asOf: t0, rate: 1, duration: 100))
        XCTAssertNil(NowPlayingProgress.fraction(at: t0, elapsed: .nan, asOf: t0, rate: 1, duration: 100))
    }

    /// A timestamp in the future (clock skew) must not run the bar backwards.
    func testFutureTimestampDoesNotRewind() {
        let e = NowPlayingProgress.elapsed(at: t0, elapsed: 20, asOf: t0.addingTimeInterval(30), rate: 1, duration: 100)
        XCTAssertEqual(e, 20)
    }
}
