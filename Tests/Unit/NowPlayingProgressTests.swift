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

    // MARK: - AppleScript fallback (Phase 43)

    /// The scriptable-player fallback shipped with an unbalanced `if`, so every read failed with -2741
    /// and the island said "Not Playing" while a player was running. Compiling catches that whole class
    /// of breakage; running it would need a live player plus the Apple Events grant.
    func testAppleScriptFallbackCompiles() {
        guard let script = NSAppleScript(source: AppleScriptNowPlaying.source) else {
            return XCTFail("NSAppleScript did not accept the source")
        }
        var error: NSDictionary?
        XCTAssertTrue(script.compileAndReturnError(&error), "compile failed: \(String(describing: error))")
    }

    /// The tab-separated record the script prints, field by field. Pure, so the app needs no player.
    func testAppleScriptReadingParsesARecord() {
        let spotify = AppleScriptNowPlaying.parse(
            "Spotify\tplaying\tTitle\tArtist\tAlbum\t174.545\t34.17\thttps://i.scdn.co/image/abc")
        XCTAssertEqual(spotify?.app, "Spotify")
        XCTAssertEqual(spotify?.isPlaying, true)
        XCTAssertEqual(spotify?.title, "Title")
        XCTAssertEqual(spotify?.duration ?? 0, 174.545, accuracy: 0.001)
        XCTAssertEqual(spotify?.position ?? 0, 34.17, accuracy: 0.001)
        XCTAssertEqual(spotify?.artworkURL?.absoluteString, "https://i.scdn.co/image/abc")
        XCTAssertEqual(spotify?.bundleIdentifier, "com.spotify.client")

        // Music hands out a file the script exported, and a live stream reports no length.
        let music = AppleScriptNowPlaying.parse("Music\tpaused\tT\tA\tAl\t0\t0\t/tmp/art.png")
        XCTAssertEqual(music?.artworkFile?.path, "/tmp/art.png")
        XCTAssertNil(music?.artworkURL)
        XCTAssertEqual(music?.duration, 0)
        XCTAssertEqual(music?.bundleIdentifier, "com.apple.Music")

        // A non-scriptable player, a missing title and a truncated record are all "nothing".
        XCTAssertNil(AppleScriptNowPlaying.parse("VLC\tplaying\tT\tA\tAl\t1\t1"))
        XCTAssertNil(AppleScriptNowPlaying.parse("Spotify\tplaying\t\tA\tAl\t1\t1"))
        XCTAssertNil(AppleScriptNowPlaying.parse("Spotify\tplaying\tT\tA"))
    }

    // MARK: - Player-permission probe (Phase 45)

    /// `REFUSED <tab> <player> <tab> <error number>` is what the reading script returns when it could
    /// read nothing and a running player said no. Every other shape is not a refusal.
    func testRefusalMarkerParses() {
        XCTAssertEqual(AppleScriptNowPlaying.refusal(in: "REFUSED\tSpotify\t-1743"),
                       AppleScriptNowPlaying.Refusal(player: "Spotify", errorNumber: -1743))
        XCTAssertEqual(AppleScriptNowPlaying.refusal(in: "REFUSED\tMusic\t-1742\n")?.errorNumber, -1742)

        XCTAssertNil(AppleScriptNowPlaying.refusal(in: ""))
        XCTAssertNil(AppleScriptNowPlaying.refusal(in: "Spotify\tplaying\tT\tA\tAl\t1\t1"))
        XCTAssertNil(AppleScriptNowPlaying.refusal(in: "REFUSED\tVLC\t-1743"))   // a player we never ask
        XCTAssertNil(AppleScriptNowPlaying.refusal(in: "REFUSED\tSpotify\t-"))   // no number
        XCTAssertNil(AppleScriptNowPlaying.refusal(in: "REFUSED\tSpotify"))
    }

    /// The reading script must report the refusal instead of swallowing it (the Phase 45 fix): the
    /// `on error` handlers and the marker are the whole mechanism, and losing either is silent.
    func testReadingScriptReportsRefusalsInsteadOfSwallowingThem() {
        let source = AppleScriptNowPlaying.source
        XCTAssertEqual(source.components(separatedBy: "on error errMsg number errNum").count - 1, 2,
                       "each player branch needs its own error handler")
        XCTAssertTrue(source.contains("return \"REFUSED\" & sep & refusal"))
    }

    /// The two TCC refusals are a verdict; every other AppleScript failure (no such app, our own script
    /// error, nothing running) is not a permission story and must stay silent.
    func testOnlyTCCRefusalsBecomeVerdicts() {
        XCTAssertEqual(PlayerAccess.probe(scriptOutput: "REFUSED\tSpotify\t-1743"), .refused(player: "Spotify"))
        XCTAssertEqual(PlayerAccess.probe(scriptOutput: "REFUSED\tMusic\t-1742"), .refused(player: "Music"))

        for raw in ["", "REFUSED\tSpotify\t-600", "REFUSED\tSpotify\t-2741", "REFUSED\tSpotify\t0",
                    "Spotify\tplaying\tT\tA\tAl\t1\t1"] {
            XCTAssertEqual(PlayerAccess.probe(scriptOutput: raw), .unknown, raw)
        }
    }

    /// The line a surface shows in place of "Not Playing", and the settings door beside it.
    func testRefusedAccessNamesThePlayerAndCarriesTheSettingsDoor() {
        let message = PlayerAccess.refused(player: "Spotify").unreadableMessage ?? ""
        XCTAssertTrue(message.contains("Spotify"), message)
        XCTAssertTrue(message.contains("KatiKati"), message)

        XCTAssertNil(PlayerAccess.unknown.unreadableMessage)    // nothing running: nothing to explain
        XCTAssertNil(PlayerAccess.readable.unreadableMessage)
        XCTAssertEqual(PlayerAccess.automationSettingsURL?.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }
}
