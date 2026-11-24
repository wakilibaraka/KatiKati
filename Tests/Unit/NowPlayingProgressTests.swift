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
        let hasSpotify = FileManager.default.fileExists(atPath: "/Applications/Spotify.app")
        let source = AppleScriptNowPlaying.source(includeSpotify: hasSpotify, includeMusic: true)
        guard let script = NSAppleScript(source: source) else {
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

    func testSourceFilteringOmitsStoppedOrUninstalledPlayersAndCompiles() {
        let musicOnly = AppleScriptNowPlaying.source(includeSpotify: false, includeMusic: true)
        XCTAssertFalse(musicOnly.contains("Spotify"))
        XCTAssertTrue(musicOnly.contains("Music"))
        if let musicScript = NSAppleScript(source: musicOnly) {
            var error: NSDictionary?
            XCTAssertTrue(musicScript.compileAndReturnError(&error), "compile failed: \(String(describing: error))")
        } else {
            XCTFail("NSAppleScript did not accept musicOnly source")
        }

        let spotifyOnly = AppleScriptNowPlaying.source(includeSpotify: true, includeMusic: false)
        XCTAssertTrue(spotifyOnly.contains("Spotify"))
        XCTAssertFalse(spotifyOnly.contains("Music"))
        XCTAssertNotNil(NSAppleScript(source: spotifyOnly))

        XCTAssertEqual(AppleScriptNowPlaying.source(includeSpotify: false, includeMusic: false), "")

        let sessionMusicOnly = MediaSessions.source(includeSpotify: false, includeMusic: true)
        XCTAssertFalse(sessionMusicOnly.contains("Spotify"))
        XCTAssertTrue(sessionMusicOnly.contains("Music"))
        XCTAssertEqual(MediaSessions.source(includeSpotify: false, includeMusic: false), "")
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

    // MARK: Phase 47 — which player a transport command addresses, and when the fallback is live

    /// The fallback reading names the player it read; a MediaRemote reading ever only gave a bundle id.
    /// Both must resolve, because in an unsigned build MediaRemote is precisely the reading that never
    /// arrives — addressing the transport by that unset bundle id is what left the buttons dead.
    func testTransportTargetPrefersTheFallbackPlayerAndMapsTheBundleIDs() {
        XCTAssertEqual(AppleScriptNowPlaying.transportTarget(fallbackApp: "Spotify", bundleIdentifier: nil), "Spotify")
        XCTAssertEqual(AppleScriptNowPlaying.transportTarget(fallbackApp: "Music", bundleIdentifier: "com.spotify.client"), "Music")
        XCTAssertEqual(AppleScriptNowPlaying.transportTarget(fallbackApp: nil, bundleIdentifier: "com.spotify.client"), "Spotify")
        XCTAssertEqual(AppleScriptNowPlaying.transportTarget(fallbackApp: nil, bundleIdentifier: "com.apple.Music"), "Music")
        XCTAssertNil(AppleScriptNowPlaying.transportTarget(fallbackApp: nil, bundleIdentifier: nil))
        XCTAssertNil(AppleScriptNowPlaying.transportTarget(fallbackApp: nil, bundleIdentifier: "com.apple.Safari"))
    }

    /// The fallback is re-read while it is the live source and while nothing is known yet; once
    /// MediaRemote has answered (`fallbackApp` nil, a title present) the polling stops.
    func testFallbackStaysLiveOnItsOwnReadingsAndStopsWhenMediaRemoteAnswers() {
        XCTAssertTrue(AppleScriptNowPlaying.fallbackIsLive(fallbackApp: "Spotify", title: "Track"))
        XCTAssertTrue(AppleScriptNowPlaying.fallbackIsLive(fallbackApp: nil, title: nil))
        XCTAssertTrue(AppleScriptNowPlaying.fallbackIsLive(fallbackApp: nil, title: ""))
        XCTAssertFalse(AppleScriptNowPlaying.fallbackIsLive(fallbackApp: nil, title: "Track"))
    }

    // MARK: Phase 50g — synced LRC lyrics parser & active line lookup

    func testLyricsLRCParsingAndActiveLineSelection() {
        let lrc = """
        [ar:Artist]
        [00:05.50] First line of song
        [00:12.00] Second line here
        [01:02.25] Chorus starts
        """
        let lines = LyricsTrack.parseLRC(lrc)
        XCTAssertEqual(lines, [
            LyricsLine(time: 5.5, text: "First line of song"),
            LyricsLine(time: 12.0, text: "Second line here"),
            LyricsLine(time: 62.25, text: "Chorus starts")
        ])
        XCTAssertEqual(LyricsTrack.activeLine(in: lines, at: 1.0), "First line of song")
        XCTAssertEqual(LyricsTrack.activeLine(in: lines, at: 6.0), "First line of song")
        XCTAssertEqual(LyricsTrack.activeLine(in: lines, at: 15.0), "Second line here")
        XCTAssertEqual(LyricsTrack.activeLine(in: lines, at: 70.0), "Chorus starts")
        XCTAssertNil(LyricsTrack.activeLine(in: [], at: 10.0))
    }

    // MARK: - Phase 60: Queue & Lyric Timeline Tests (Slice A-QueueLyrics)

    func testQueueReorderPlanPromotesAndRemoves() {
        let q = [
            NowPlayingQueueItem(id: "1", title: "Track 1"),
            NowPlayingQueueItem(id: "2", title: "Track 2"),
            NowPlayingQueueItem(id: "3", title: "Track 3")
        ]

        // Promote track 3 to top
        let promoted = NowPlayingQueueReorderPlan.promoteTrackToTop(in: q, id: "3")
        XCTAssertEqual(promoted.map(\.id), ["3", "1", "2"])

        // Promoting index 0 is no-op
        let same = NowPlayingQueueReorderPlan.promoteTrackToTop(in: promoted, id: "3")
        XCTAssertEqual(same.map(\.id), ["3", "1", "2"])

        // Promoting non-existent id is no-op
        let untouched = NowPlayingQueueReorderPlan.promoteTrackToTop(in: q, id: "non-existent")
        XCTAssertEqual(untouched.map(\.id), ["1", "2", "3"])

        // Remove track 2
        let removed = NowPlayingQueueReorderPlan.removeTrack(in: q, id: "2")
        XCTAssertEqual(removed.map(\.id), ["1", "3"])
    }

    func testLyricTimelineMatcherWindowAndProgress() {
        let lines = [
            LyricsLine(time: 10.0, text: "Line 1"),
            LyricsLine(time: 20.0, text: "Line 2"),
            LyricsLine(time: 30.0, text: "Line 3"),
            LyricsLine(time: 40.0, text: "Line 4"),
            LyricsLine(time: 50.0, text: "Line 5")
        ]

        // Active index
        XCTAssertEqual(LyricTimelineMatcher.activeIndex(in: lines, at: 5.0), 0)
        XCTAssertEqual(LyricTimelineMatcher.activeIndex(in: lines, at: 15.0), 0)
        XCTAssertEqual(LyricTimelineMatcher.activeIndex(in: lines, at: 22.0), 1)
        XCTAssertEqual(LyricTimelineMatcher.activeIndex(in: lines, at: 45.0), 3)

        // Sliding 3-line window centered at Line 3 (index 2)
        let win = LyricTimelineMatcher.window(in: lines, at: 31.0, windowSize: 3)
        XCTAssertEqual(win.map(\.text), ["Line 2", "Line 3", "Line 4"])

        // Line progress (midway between 20.0 and 30.0 -> elapsed 25.0 -> 0.5)
        let prog = LyricTimelineMatcher.lineProgress(in: lines, at: 25.0)
        XCTAssertEqual(prog, 0.5, accuracy: 0.05)
    }

    func testFloatingPlayerSizeDimensions() {
        XCTAssertEqual(FloatingPlayerSize.mini.defaultDimensions.width, 180)
        XCTAssertEqual(FloatingPlayerSize.player.defaultDimensions.width, 280)
        XCTAssertEqual(FloatingPlayerSize.expanded.defaultDimensions.width, 340)
    }
}

// MARK: - OW-5a: several players, one switcher

final class MediaSessionSwitcherTests: XCTestCase {
    private func session(_ app: String, playing: Bool = true) -> MediaSession {
        MediaSession(bundleID: MediaSessions.bundleID(forApp: app)!, app: app,
                     title: app + " Song", artist: "Artist", isPlaying: playing)
    }

    func testParseReadsOneRecordPerRunningPlayer() {
        let raw = "Spotify\tplaying\tSong A\tArtist A\nMusic\tpaused\tSong B\tArtist B\n"
        let sessions = MediaSessions.parse(raw)
        XCTAssertEqual(sessions.map(\.app), ["Spotify", "Music"])
        XCTAssertEqual(sessions.map(\.bundleID), ["com.spotify.client", "com.apple.Music"])
        XCTAssertEqual(sessions.first?.isPlaying, true)
        XCTAssertEqual(sessions.last?.isPlaying, false)
        XCTAssertEqual(sessions.first?.title, "Song A")
        XCTAssertEqual(sessions.last?.artist, "Artist B")
    }

    func testParseDropsUnknownPlayersEmptyTitlesAndGarbage() {
        XCTAssertTrue(MediaSessions.parse("").isEmpty)
        XCTAssertTrue(MediaSessions.parse("VLC\tplaying\tSong\tArtist").isEmpty, "only players we can script")
        XCTAssertTrue(MediaSessions.parse("Spotify\tplaying\t\tArtist").isEmpty, "no title, no session")
        XCTAssertTrue(MediaSessions.parse("REFUSED\tMusic\t-1743").isEmpty)
        XCTAssertEqual(MediaSessions.parse("Spotify\tplaying\tSong\tArtist").count, 1)
    }

    func testOrderPutsThePinnedPlayerFirstThenKnownOrder() {
        let found = [session("Music"), session("Spotify")]
        XCTAssertEqual(MediaSessions.ordered(found, pinned: nil).map(\.app), ["Spotify", "Music"])
        XCTAssertEqual(MediaSessions.ordered(found, pinned: "com.apple.Music").map(\.app), ["Music", "Spotify"])
        XCTAssertEqual(MediaSessions.ordered(found, pinned: "missing").map(\.app), ["Spotify", "Music"])
    }

    func testCycleWrapsBothWaysAndStartsAtEnds() {
        let sessions = [session("Spotify"), session("Music")]
        var forward = MediaSessionSwitcher()
        XCTAssertEqual(forward.cycle(among: sessions), "com.spotify.client", "a fresh cycle starts at the head")
        XCTAssertEqual(forward.cycle(among: sessions), "com.apple.Music")
        XCTAssertEqual(forward.cycle(among: sessions), "com.spotify.client", "wraps at the end")

        var backward = MediaSessionSwitcher()
        XCTAssertEqual(backward.cycle(among: sessions, forward: false), "com.apple.Music", "backward starts at the tail")
        XCTAssertEqual(backward.cycle(among: sessions, forward: false), "com.spotify.client", "wraps at the head")
    }

    func testCycleClearsThePinWhenNothingIsOpen() {
        var switcher = MediaSessionSwitcher()
        XCTAssertEqual(switcher.cycle(among: [session("Music")]), "com.apple.Music")
        XCTAssertNil(switcher.cycle(among: []))
        XCTAssertNil(switcher.pinnedBundleID)
    }

    func testReadingSourceTargetsExactlyOnePlayer() {
        let music = MediaSessions.readingSource(for: "Music")
        XCTAssertTrue(music.contains("tell application \"Music\""))
        XCTAssertFalse(music.contains("Spotify"), "a pinned read must not touch the other player")
        let spotify = MediaSessions.readingSource(for: "Spotify")
        XCTAssertTrue(spotify.contains("tell application \"Spotify\""))
        XCTAssertTrue(spotify.contains("artwork url"), "Spotify hands out an artwork URL")
        XCTAssertFalse(spotify.contains("Music"))
    }

    // MARK: - Liquid Synced Lyrics (LQ-2)

    func testLiquidLrcParsingAndConsensusSelection() {
        let lrc = "[00:12.50] First line\n[00:15.00][00:45.00] Chorus line\n[00:20.00] "
        let lines = LiquidLyricsSource.parse(lrc)
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[0], LiquidLyricLine(time: 12.5, text: "First line"))
        XCTAssertEqual(lines[1], LiquidLyricLine(time: 15.0, text: "Chorus line"))
        XCTAssertEqual(lines[3], LiquidLyricLine(time: 45.0, text: "Chorus line"))

        let lyrics = LiquidLyrics(key: "Artist|Song", lines: lines, plain: [])
        XCTAssertEqual(lyrics.current(at: 12.45), 0, "0.1s lead lights line just as voice lands")
        XCTAssertEqual(lyrics.line(from: 1, at: 14.2), 1, "clock step-back <= 1.5s holds current line")
        XCTAssertEqual(lyrics.line(from: 1, at: 12.5), 0, "real seek back moves immediately")

        let wrongDuration = LiquidLyricsEntry(duration: 240, lines: [LiquidLyricLine(time: 1, text: "Wrong")], plain: [])
        let rightDuration = LiquidLyricsEntry(duration: 180, lines: [LiquidLyricLine(time: 12, text: "Right")], plain: [])
        XCTAssertEqual(LiquidLyricsSource.best([wrongDuration, rightDuration], duration: 180)?.lines, rightDuration.lines)
    }
}
