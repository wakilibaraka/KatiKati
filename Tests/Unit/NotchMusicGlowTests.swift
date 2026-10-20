import XCTest
@testable import KatiKati

final class NotchMusicGlowTests: XCTestCase {
    func testDefaultIsTheStaticHalo() {
        XCTAssertEqual(NotchMusicGlow.default, .halo)
        XCTAssertFalse(NotchMusicGlow.halo.isAnimated(reduceMotion: false))
    }

    func testOnlyPulseMovesAndReduceMotionFreezesIt() {
        XCTAssertTrue(NotchMusicGlow.pulse.isAnimated(reduceMotion: false))
        XCTAssertFalse(NotchMusicGlow.pulse.isAnimated(reduceMotion: true))
        XCTAssertEqual(NotchMusicGlow.pulse.level(at: 0.4, boost: 0, reduceMotion: true), NotchMusicGlow.restLevel)
    }

    func testStaticStylesIgnoreTime() {
        for style in [NotchMusicGlow.halo, .edge] {
            XCTAssertEqual(style.level(at: 0, boost: 0, reduceMotion: false), style.level(at: 1.7, boost: 0, reduceMotion: false))
        }
    }

    func testPulseStaysInsideItsBand() {
        for t in stride(from: 0.0, to: 6.0, by: 0.25) {
            let v = NotchMusicGlow.pulse.level(at: t, boost: 0, reduceMotion: false)
            XCTAssertGreaterThanOrEqual(v, NotchMusicGlow.restLevel * 0.7 - 1e-9)
            XCTAssertLessThanOrEqual(v, NotchMusicGlow.restLevel + 1e-9)
        }
    }

    func testBoostLiftsToFullAndClamps() {
        XCTAssertEqual(NotchMusicGlow.halo.level(at: 0, boost: 1, reduceMotion: false), 1, accuracy: 1e-9)
        XCTAssertEqual(NotchMusicGlow.halo.level(at: 0, boost: 5, reduceMotion: false), 1, accuracy: 1e-9)
        XCTAssertGreaterThan(NotchMusicGlow.halo.level(at: 0, boost: 0.5, reduceMotion: false), NotchMusicGlow.restLevel)
    }
}
