import AppKit
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

// MARK: - ML-1: music surface core

final class MusicSurfaceCoreTests: XCTestCase {

    func testGlassStylesMapOntoExistingMaterials() {
        XCTAssertEqual(MusicGlassStyle.clear.material, .clearMinimal)
        XCTAssertEqual(MusicGlassStyle.semi.material, .frostedGlass)
        XCTAssertEqual(MusicGlassStyle.tinted.material, .tintedGlass)
        XCTAssertEqual(MusicGlassStyle.allCases.count, 3)
    }

    func testAssignmentKeepsSidesDistinct() {
        var assignment = MusicControlAssignment(left: .lyrics, right: .lyrics)
        XCTAssertEqual(assignment.left, .lyrics)
        XCTAssertEqual(assignment.right, MusicControlAssignment.alternative(to: .lyrics))
        assignment.set(.copy, on: .left)
        XCTAssertEqual(assignment.left, .copy)
        XCTAssertNotEqual(assignment.left, assignment.right)
        assignment.set(.favorite, on: .right)
        XCTAssertEqual(assignment.right, .favorite)
        XCTAssertNotEqual(assignment.left, assignment.right)
    }

    func testAssignmentDecodesStoredRawValuesAndFallsBack() {
        XCTAssertEqual(MusicControlAssignment(leftRaw: "repeat", rightRaw: "copy"),
                       MusicControlAssignment(left: .repeatTrack, right: .copy))
        let fallback = MusicControlAssignment(leftRaw: "nonsense", rightRaw: nil)
        XCTAssertEqual(fallback.left, .lyrics)
        XCTAssertEqual(fallback.right, .output)
    }

    func testCapabilitiesHideSlotsThePlayerCannotServe() {
        let assignment = MusicControlAssignment(left: .shuffle, right: .output)
        let resolved = assignment.resolved(.standard)
        XCTAssertNil(resolved.left, "shuffle is not offered without a proven command")
        XCTAssertEqual(resolved.right, .output)
        var capable = MusicControlCapabilities.standard
        capable.canShuffle = true
        XCTAssertEqual(assignment.resolved(capable).left, .shuffle)
    }

    func testHorizontalSwipeSkipsOnceTheAxisLocks() {
        var machine = MusicSwipeMachine()
        machine.begin()
        machine.accumulate(deltaX: 20, deltaY: 2)
        machine.accumulate(deltaX: 60, deltaY: 3)
        XCTAssertEqual(machine.axis, .horizontal)
        XCTAssertEqual(machine.end(at: 10, currentMode: .full), .skip(forward: false))
    }

    func testVerticalSwipeResizesToTheRequestedMode() {
        var machine = MusicSwipeMachine()
        machine.begin()
        machine.accumulate(deltaX: 1, deltaY: -60)
        XCTAssertEqual(machine.end(at: 10, currentMode: .full), .resize(.full))
        machine.begin()
        machine.accumulate(deltaX: 1, deltaY: 60)
        XCTAssertEqual(machine.end(at: 11, currentMode: .full), .resize(.slim))
    }

    func testDiagonalBelowDominanceNeverFires() {
        var machine = MusicSwipeMachine()
        machine.begin()
        machine.accumulate(deltaX: 40, deltaY: 38)
        XCTAssertNil(machine.axis)
        XCTAssertEqual(machine.end(at: 10, currentMode: .full), .none)
    }

    func testShortGestureIsIgnoredAndCooldownBlocksRepeats() {
        var machine = MusicSwipeMachine(cooldown: 1)
        machine.begin()
        machine.accumulate(deltaX: 60, deltaY: 0)
        machine.begin()
        machine.accumulate(deltaX: 10, deltaY: 0)
        XCTAssertEqual(machine.end(at: 10, currentMode: .full), .none, "a 10 pt flick is not a swipe")

        machine.begin()
        machine.accumulate(deltaX: 60, deltaY: 0)
        XCTAssertEqual(machine.end(at: 10, currentMode: .full), .skip(forward: false))
        machine.begin()
        machine.accumulate(deltaX: 60, deltaY: 0)
        XCTAssertEqual(machine.end(at: 10.2, currentMode: .full), .none, "cooldown")
    }

    func testStashClampsToTheVisibleFrame() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let card = CGRect(x: 600, y: 400, width: 260, height: 280)
        let leftStash = MusicEdgeStash.stashedFrame(card, in: visible, edge: .left)
        XCTAssertEqual(leftStash.minX, -260 + MusicEdgeStash.revealWidth)
        let rightStash = MusicEdgeStash.stashedFrame(card, in: visible, edge: .right)
        XCTAssertEqual(rightStash.minX, visible.maxX - MusicEdgeStash.revealWidth)

        XCTAssertEqual(MusicEdgeStash.revealedFrame(leftStash, in: visible, edge: .left).minX, visible.minX)
        XCTAssertEqual(MusicEdgeStash.revealedFrame(rightStash, in: visible, edge: .right).maxX, visible.maxX)

        let huge = CGRect(x: 0, y: 0, width: 2000, height: 100)
        XCTAssertEqual(MusicEdgeStash.stashedFrame(huge, in: visible, edge: .right).width, visible.width)
        XCTAssertTrue(MusicEdgeStash.isRevealed(mouseX: 12, frame: leftStash, edge: .left))
        XCTAssertFalse(MusicEdgeStash.isRevealed(mouseX: 200, frame: leftStash, edge: .left))
    }

    /// The exact corruption sequence from the plan: weather holds the capture, music comes and goes, and
    /// the capture must still be the user's original (restored only on the weather release).
    func testPanelStashOffsetsAndFullyHiddenState() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let panel = CGRect(x: 600, y: 400, width: 280, height: 320)

        let stashed = MusicEdgeStash.stashedFrame(panel, in: visible, edge: .right)
        XCTAssertEqual(MusicEdgeStash.visibleWidth(of: stashed, in: visible), MusicEdgeStash.revealWidth)
        XCTAssertFalse(MusicEdgeStash.isFullyHidden(stashed, in: visible))

        let hidden = MusicEdgeStash.stashedFrame(panel, in: visible, edge: .right, reveal: 0)
        XCTAssertEqual(MusicEdgeStash.visibleWidth(of: hidden, in: visible), 0)
        XCTAssertTrue(MusicEdgeStash.isFullyHidden(hidden, in: visible))

        let leftStashed = MusicEdgeStash.stashedFrame(panel, in: visible, edge: .left)
        XCTAssertEqual(MusicEdgeStash.visibleWidth(of: leftStashed, in: visible), MusicEdgeStash.revealWidth)
        XCTAssertEqual(MusicEdgeStash.revealedFrame(leftStashed, in: visible, edge: .left).minX, visible.minX)

        // The reveal strip starts at the screen edge and covers the sliver's vertical span.
        let rightZone = MusicEdgeStash.revealZone(in: stashed, edge: .right, visible: visible)
        XCTAssertEqual(rightZone.maxX, visible.maxX)
        XCTAssertTrue(rightZone.contains(CGPoint(x: visible.maxX - 1, y: stashed.midY)))
        XCTAssertFalse(rightZone.contains(CGPoint(x: visible.maxX - 200, y: stashed.midY)))
        let leftZone = MusicEdgeStash.revealZone(in: leftStashed, edge: .left, visible: visible)
        XCTAssertEqual(leftZone.minX, visible.minX)
        XCTAssertTrue(leftZone.contains(CGPoint(x: visible.minX + 1, y: leftStashed.midY)))
    }

    // MARK: - §5.7 shared design system

    func testScrubberHeightsAreDeterministicAndBounded() {
        let seed = MusicScrubberStyle.seed(title: "KatiKati CPU Probe", artist: "Local Test")
        XCTAssertEqual(seed, MusicScrubberStyle.seed(title: "KatiKati CPU Probe", artist: "Local Test"))
        XCTAssertNotEqual(seed, MusicScrubberStyle.seed(title: "Another", artist: "Local Test"))

        let first = MusicScrubberStyle.barHeights(seed: seed, count: 32)
        let second = MusicScrubberStyle.barHeights(seed: seed, count: 32)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 32)
        XCTAssertTrue(first.allSatisfy { $0 >= 0.18 && $0 <= 1 })
        XCTAssertNotEqual(first, MusicScrubberStyle.barHeights(seed: seed &+ 1, count: 32))
    }

    func testScrubberStylesExposeTheirBarCounts() {
        XCTAssertEqual(MusicScrubberStyle.slim.barCount, 1)
        XCTAssertEqual(MusicScrubberStyle.dotted.barCount, 24)
        XCTAssertEqual(MusicScrubberStyle.waveform.barCount, 32)
        XCTAssertEqual(MusicScrubberStyle.waveform.heights(title: "A", artist: "B").count, 32)
    }

    func testSurfaceThemesKeepOneGlassVocabulary() {
        XCTAssertEqual(MusicSurfaceTheme.allCases.count, 5)
        XCTAssertEqual(MusicSurfaceTheme(legacy: .clear), .clearGlass)
        XCTAssertEqual(MusicSurfaceTheme(legacy: .semi), .semiGlass)
        XCTAssertEqual(MusicSurfaceTheme(legacy: .tinted), .tintedGlass)
        XCTAssertEqual(MusicSurfaceTheme.semiGlass.material, .frostedGlass)
        XCTAssertTrue(MusicSurfaceTheme.semiGlass.usesMaterial)
        XCTAssertFalse(MusicSurfaceTheme.oledBlack.usesMaterial)
        XCTAssertFalse(MusicSurfaceTheme.crispLight.isDark)
        XCTAssertTrue(MusicSurfaceTheme.oledBlack.isDark)
        XCTAssertGreaterThan(MusicSurfaceTheme.oledBlack.scrimOpacity, MusicSurfaceTheme.clearGlass.scrimOpacity)
    }

    func testCardLayoutsCarryTheirOwnGeometry() {
        XCTAssertEqual(MusicCardLayout.slim.lyricSlots, 1)
        XCTAssertEqual(MusicCardLayout.hero.lyricSlots, 3)
        XCTAssertTrue(MusicCardLayout.hero.showsArtwork)
        XCTAssertFalse(MusicCardLayout.full.showsArtwork)
        XCTAssertLessThan(MusicCardLayout.slim.height(width: 320), MusicCardLayout.full.height(width: 320))
        XCTAssertLessThan(MusicCardLayout.full.height(width: 320), MusicCardLayout.hero.height(width: 320))
        XCTAssertEqual(MusicCardLayout.from(mode: .full, heroEnabled: true), .hero)
        XCTAssertEqual(MusicCardLayout.from(mode: .slim, heroEnabled: true), .slim)
    }

    func testPalettePicksTheDominantColour() {
        // A block of one strongly blue colour: the accent must come out blue, and the surface dark.
        var pixels: [UInt8] = []
        for _ in 0..<64 { pixels += [40, 60, 200, 255] }
        let palette = MusicArtworkPalette(pixels: pixels)
        XCTAssertGreaterThan(palette.accent.b, palette.accent.r)
        XCTAssertGreaterThan(palette.accent.b, palette.accent.g)
        XCTAssertTrue(palette.isDark)
        XCTAssertEqual(MusicArtworkPalette(pixels: []), MusicArtworkPalette(pixels: [1, 2, 3]))
    }

    func testStyleSelectionOverridesOnlyWhenMatchingIsOff() {
        var selection = MusicStyleSelection()
        XCTAssertTrue(selection.matchesAcrossSurfaces)
        XCTAssertEqual(selection.theme(for: .lockScreen), selection.theme(for: .desktop))

        var override = MusicSurfaceStyle.standard
        override.theme = .oledBlack
        selection.set(override, for: .lockScreen)
        // Still matched: the "override" wrote the base.
        XCTAssertEqual(selection.theme(for: .desktop), .oledBlack)

        selection.matchesAcrossSurfaces = false
        selection.base = .standard
        selection.set(override, for: .lockScreen)
        XCTAssertEqual(selection.theme(for: .lockScreen), .oledBlack)
        XCTAssertEqual(selection.theme(for: .desktop), .semiGlass)
        // Atmospheric is the shipped default now, so a matched selection paints the mesh on the wallpaper.
        XCTAssertEqual(selection.wallpaperStyle(for: .wallpaper), .atmosphericMesh)
    }

    func testLeaseNeverHandsASecondWriterTheCapture() {
        var lease = WallpaperLease()
        XCTAssertTrue(lease.acquire(.weather), "first holder captures")
        XCTAssertFalse(lease.acquire(.music), "second holder must not capture over the album art")
        XCTAssertFalse(lease.release(.music), "music leaving must not restore while weather is painting")
        XCTAssertTrue(lease.isCaptured)
        XCTAssertTrue(lease.release(.weather), "the last holder restores the user's original")
        XCTAssertFalse(lease.isCaptured)
        XCTAssertTrue(lease.holders.isEmpty)
    }

    func testLeaseAdoptsACrashLeftoverCapture() {
        var lease = WallpaperLease()
        lease.adoptCapture()
        XCTAssertFalse(lease.acquire(.music), "a persisted capture is adopted, never overwritten")
        XCTAssertTrue(lease.release(.music))
    }

    func testLockScreenBackupSurvivesACrashMidRestore() throws {
        var backup = LockScreenWallpaperBackup()
        XCTAssertTrue(backup.capture("file:///Users/me/photo.heic"))
        XCTAssertFalse(backup.capture("file:///Users/me/other.heic"), "never overwrite a held capture")
        backup.markRestorePending()
        let encoded = try JSONEncoder().encode(backup)
        var restored = try JSONDecoder().decode(LockScreenWallpaperBackup.self, from: encoded)
        XCTAssertEqual(restored.state, .restorePending)
        XCTAssertEqual(restored.takeRestore(), "file:///Users/me/photo.heic")
        XCTAssertEqual(restored.state, .idle)
        XCTAssertNil(restored.takeRestore())
    }

    func testEnhancedLRCWordsAndLineFallback() {
        let enhanced = "[00:12.50]<00:12.50>Hello <00:13.00>world\n"
        let lines = LyricsTrack.parseLRC(enhanced)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].text, "Hello world")
        XCTAssertEqual(lines[0].words, [LyricsWord(time: 12.5, text: "Hello"),
                                         LyricsWord(time: 13.0, text: "world")])
        XCTAssertEqual(LyricsTrack.activeWord(in: lines[0], at: 12.6), "Hello")
        XCTAssertEqual(LyricsTrack.activeWord(in: lines[0], at: 13.4), "world")

        let plain = LyricsTrack.parseLRC("[00:12.50]Hello world\n")
        XCTAssertEqual(plain[0].text, "Hello world")
        XCTAssertTrue(plain[0].words.isEmpty)
        XCTAssertNil(LyricsTrack.activeWord(in: plain[0], at: 20), "no word tags -> line highlighting")
        XCTAssertEqual(LyricsTrack.activeLine(in: plain, at: 20), "Hello world")
    }
}

// MARK: - Atmospheric (Full-Bleed) pure core

final class AtmosphericCoreTests: XCTestCase {
    func testAtmosphericIsTheShippedDefault() {
        let style = MusicSurfaceStyle.standard
        XCTAssertEqual(style.wallpaperStyle, .atmosphericMesh)
        XCTAssertEqual(style.scrubber, .pill)
        XCTAssertEqual(style.layout, .full)
        XCTAssertEqual(MusicStyleSelection().base, .standard)
        // Every earlier preset is still a real, selectable style.
        XCTAssertTrue(MusicWallpaperStyle.allCases.contains(.blurredAlbum))
        XCTAssertTrue(MusicWallpaperStyle.allCases.contains(.heroArtwork))
        XCTAssertTrue(MusicWallpaperStyle.allCases.contains(.oledBlack))
        XCTAssertTrue(MusicSurfaceTheme.allCases.contains(.clearGlass))
        XCTAssertTrue(MusicScrubberStyle.allCases.contains(.waveform))
    }

    func testVolumeCurveRoundTrips() {
        for step in 0...100 {
            let position = Double(step) / 100
            let gain = MusicVolumeCurve.gain(forPosition: position)
            XCTAssertEqual(MusicVolumeCurve.position(forGain: gain), position, accuracy: 1e-9)
        }
    }

    func testVolumeCurveEndpointsAndMonotonicity() {
        XCTAssertEqual(MusicVolumeCurve.gain(forPosition: 0), 0, accuracy: 1e-12)
        XCTAssertEqual(MusicVolumeCurve.gain(forPosition: 1), 1, accuracy: 1e-12)
        XCTAssertEqual(MusicVolumeCurve.position(forGain: 0), 0, accuracy: 1e-12)
        XCTAssertEqual(MusicVolumeCurve.position(forGain: 1), 1, accuracy: 1e-12)
        var previous = -1.0
        for step in 0...50 {
            let gain = MusicVolumeCurve.gain(forPosition: Double(step) / 50)
            XCTAssertGreaterThan(gain, previous)
            previous = gain
        }
        // Exponential, not linear: half travel is well under half gain.
        XCTAssertLessThan(MusicVolumeCurve.gain(forPosition: 0.5), 0.2)
        XCTAssertEqual(MusicVolumeCurve.percent(forPosition: 0), 0)
        XCTAssertEqual(MusicVolumeCurve.percent(forPosition: 1), 100)
    }

    func testQueueRecordsDedupesAndCaps() {
        var model = MusicQueueModel()
        model.capacity = 3
        model.record(title: "A", artist: "x")
        model.record(title: "B", artist: "y")
        model.record(title: "A", artist: "x")
        XCTAssertEqual(model.history.map(\.title), ["A", "B"])
        model.record(title: "C", artist: nil)
        model.record(title: "D", artist: nil)
        XCTAssertEqual(model.history.map(\.title), ["D", "C", "A"])
        model.record(title: "   ", artist: nil)
        XCTAssertEqual(model.history.count, 3)
    }

    func testQueueSectionsUseTheZeroPermissionFallback() {
        var model = MusicQueueModel()
        model.record(title: "Played", artist: "Artist")
        let sections = model.sections(favorites: [MusicQueueEntry(title: "Starred", artist: nil)])
        XCTAssertEqual(sections.map(\.kind), [.history, .favorites])
        // No upcoming array: nothing claims a queue macOS never gave us.
        XCTAssertFalse(sections.contains { $0.kind == .upcoming })
        XCTAssertTrue(model.sections().isEmpty == false)
        XCTAssertEqual(model.sections(upcoming: [MusicQueueEntry(title: "Next", artist: nil)]).first?.kind, .upcoming)
    }

    func testMeshStopsAreDeterministicAndBounded() {
        let palette = MusicArtworkPalette(accent: MusicRGB(0.9, 0.2, 0.1),
                                          secondary: MusicRGB(0.1, 0.3, 0.8), isDark: true)
        let stops = MusicMeshStops.stops(for: palette)
        XCTAssertEqual(stops.count, 5)
        XCTAssertEqual(stops, MusicMeshStops.stops(for: palette))
        for stop in stops {
            XCTAssertTrue((0...1).contains(stop.r))
            XCTAssertTrue((0...1).contains(stop.g))
            XCTAssertTrue((0...1).contains(stop.b))
            XCTAssertTrue((0...1).contains(stop.x))
            XCTAssertTrue((0...1).contains(stop.y))
            XCTAssertGreaterThan(stop.radius, 0)
        }
    }

    func testTransportLayoutTradesDetailForSpace() {
        let small = MusicTransportLayout(size: .small)
        XCTAssertFalse(small.showsVolume)
        XCTAssertFalse(small.showsDeviceLabel)
        XCTAssertEqual(small.lyricLines, 1)
        let medium = MusicTransportLayout(size: .medium)
        XCTAssertTrue(medium.showsVolume)
        XCTAssertTrue(medium.showsDeviceLabel)
        XCTAssertTrue(medium.showsScrubber)
        let large = MusicTransportLayout(size: .large)
        XCTAssertGreaterThan(large.playDiameter, medium.playDiameter)
        XCTAssertGreaterThan(large.lyricLines, medium.lyricLines)
    }

    func testRomanizerHandlesEveryScriptThePlanNames() {
        XCTAssertTrue(MusicRomanizer.supports("ありがとう"))
        XCTAssertTrue(MusicRomanizer.supports("감사합니다"))
        XCTAssertTrue(MusicRomanizer.supports("谢谢"))
        XCTAssertTrue(MusicRomanizer.supports("Спасибо"))

        let japanese = MusicRomanizer.romanize("ありがとう")?.lowercased() ?? ""
        XCTAssertTrue(japanese.contains("arigat"), "got \(japanese)")
        let korean = MusicRomanizer.romanize("감사합니다")?.lowercased() ?? ""
        XCTAssertTrue(korean.contains("gam"), "got \(korean)")
        let han = MusicRomanizer.romanize("谢谢")?.lowercased() ?? ""
        XCTAssertTrue(han.contains("xie"), "got \(han)")
        let russian = MusicRomanizer.romanize("Спасибо")?.lowercased() ?? ""
        XCTAssertTrue(russian.contains("spasib"), "got \(russian)")
    }

    func testRomanizerHidesItselfOnLatinText() {
        XCTAssertFalse(MusicRomanizer.supports("Thank You for the cross"))
        XCTAssertNil(MusicRomanizer.romanize("Thank You for the cross"))
    }

    func testViewModeCyclesThroughAllThree() {
        var mode = MusicViewMode.nowPlaying
        var seen: [MusicViewMode] = []
        for _ in 0..<3 { seen.append(mode); mode = mode.next }
        XCTAssertEqual(seen, [.nowPlaying, .lyrics, .queue])
        XCTAssertEqual(mode, .nowPlaying)
        XCTAssertEqual(Set(MusicViewMode.allCases.map(\.symbolName)).count, 3)
    }
}

// MARK: - §10 desktop music widget policy

final class MusicDesktopWidgetPolicyTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1080)

    func testCardIsTheDefaultPreset() {
        XCTAssertEqual(MusicDesktopWidgetPreset.standard, .card)
        XCTAssertEqual(MusicSurfaceConfig.desktopPreset(defaults: UserDefaults(suiteName: UUID().uuidString)!), .card)
    }

    func testPosterSitsBelowTheIconsAndEverythingElseAtIconLevel() {
        XCTAssertEqual(MusicDesktopWidgetPolicy.level(for: .poster), .desktopPicture)
        for preset in [MusicDesktopWidgetPreset.stage, .card, .strip] {
            XCTAssertEqual(MusicDesktopWidgetPolicy.level(for: preset), .desktopIcons)
        }
        XCTAssertLessThan(MusicDesktopWidgetPolicy.windowLevel(for: .poster),
                          MusicDesktopWidgetPolicy.windowLevel(for: .card))
    }

    func testNoPresetEverReachesANormalAppWindowLevel() {
        for preset in MusicDesktopWidgetPreset.allCases {
            XCTAssertLessThan(MusicDesktopWidgetPolicy.windowLevel(for: preset),
                              MusicDesktopWidgetPolicy.normalWindowLevel,
                              "\(preset.rawValue) must stay below normal app windows")
        }
    }

    func testOnlyPosterIsClickThrough() {
        XCTAssertTrue(MusicDesktopWidgetPolicy.ignoresMouseEvents(for: .poster))
        for preset in [MusicDesktopWidgetPreset.stage, .card, .strip] {
            XCTAssertFalse(MusicDesktopWidgetPolicy.ignoresMouseEvents(for: preset))
        }
    }

    func testAnimationsPauseWhenHiddenOrOccluded() {
        XCTAssertFalse(MusicDesktopWidgetPolicy.pausesAnimations(isHidden: false, isOccluded: false))
        XCTAssertTrue(MusicDesktopWidgetPolicy.pausesAnimations(isHidden: true, isOccluded: false))
        XCTAssertTrue(MusicDesktopWidgetPolicy.pausesAnimations(isHidden: false, isOccluded: true))
    }

    func testGeometryKeepsEveryPresetInsideTheVisibleFrameWithInsets() {
        let insets = MusicDesktopWidgetInsets(top: 12, bottom: 20, leading: 8, trailing: 8)
        for preset in MusicDesktopWidgetPreset.allCases {
            let rect = MusicDesktopWidgetGeometry.rect(for: preset, in: screen, insets: insets)
            XCTAssertTrue(screen.contains(rect), "\(preset.rawValue) escaped the visible frame")
            XCTAssertGreaterThanOrEqual(rect.minX, screen.minX + insets.leading)
            XCTAssertGreaterThanOrEqual(rect.minY, screen.minY + insets.bottom)
            XCTAssertLessThanOrEqual(rect.maxX, screen.maxX - insets.trailing)
            XCTAssertLessThanOrEqual(rect.maxY, screen.maxY - insets.top)
        }
    }

    func testPosterCoversAndStageSplitsTheVisibleFrame() {
        let poster = MusicDesktopWidgetGeometry.rect(for: .poster, in: screen)
        XCTAssertEqual(poster, screen)
        let stage = MusicDesktopWidgetGeometry.rect(for: .stage, in: screen, stageSide: .trailing)
        XCTAssertEqual(stage.width, screen.width / 2, accuracy: 0.5)
        XCTAssertEqual(stage.maxX, screen.maxX, accuracy: 0.5)
    }

    func testCardAndStripUseTheirOwnGeometry() {
        let card = MusicDesktopWidgetGeometry.rect(for: .card, in: screen)
        XCTAssertEqual(card.size, MusicDesktopWidgetGeometry.cardSize)
        XCTAssertEqual(card.maxX, screen.maxX - MusicDesktopWidgetGeometry.edgeMargin, accuracy: 0.5)
        let strip = MusicDesktopWidgetGeometry.rect(for: .strip, in: screen)
        XCTAssertEqual(strip.height, MusicDesktopWidgetGeometry.stripHeight, accuracy: 0.5)
        XCTAssertLessThan(strip.width, screen.width)
    }

    func testClampShrinksAndMovesOversizedRectsBackInside() {
        let clamped = MusicDesktopWidgetGeometry.clamp(CGRect(x: -50, y: -50, width: 4000, height: 4000), into: screen)
        XCTAssertEqual(clamped, screen)
        let moved = MusicDesktopWidgetGeometry.clamp(CGRect(x: 1700, y: 1000, width: 300, height: 200), into: screen)
        XCTAssertEqual(moved.maxX, screen.maxX, accuracy: 0.5)
        XCTAssertEqual(moved.maxY, screen.maxY, accuracy: 0.5)
    }

    func testSnapPullsToTheNearestEdgeWithinTheThresholdOnly() {
        let near = CGRect(x: 12, y: screen.height - MusicDesktopWidgetGeometry.cardSize.height - 9,
                          width: MusicDesktopWidgetGeometry.cardSize.width,
                          height: MusicDesktopWidgetGeometry.cardSize.height)
        let snapped = MusicDesktopWidgetGeometry.snap(near, into: screen)
        XCTAssertEqual(snapped.minX, screen.minX, accuracy: 0.5)
        XCTAssertEqual(snapped.maxY, screen.maxY, accuracy: 0.5)

        let far = CGRect(x: 600, y: 400, width: 300, height: 200)
        XCTAssertEqual(MusicDesktopWidgetGeometry.snap(far, into: screen), far)
    }

    func testMoveKeepsTheSizeAndStaysOnScreen() {
        let start = CGRect(x: 600, y: 400, width: 300, height: 224)
        let moved = MusicDesktopWidgetGeometry.moved(start, by: CGSize(width: 40, height: -60), into: screen)
        XCTAssertEqual(moved.size, start.size)
        XCTAssertEqual(moved.origin, CGPoint(x: 640, y: 340))

        let pinned = MusicDesktopWidgetGeometry.moved(start, by: CGSize(width: 5000, height: 5000), into: screen)
        XCTAssertEqual(pinned.size, start.size)
        XCTAssertEqual(pinned.maxX, screen.maxX, accuracy: 0.5)
        XCTAssertEqual(pinned.maxY, screen.maxY, accuracy: 0.5)
    }

    func testResizeAnchorsTheTopLeadingCornerAndHonoursTheMinimum() {
        let start = CGRect(x: 600, y: 400, width: 300, height: 224)
        let bigger = MusicDesktopWidgetGeometry.resized(start, by: CGSize(width: 80, height: 40),
                                                        preset: .card, into: screen)
        XCTAssertEqual(bigger.minX, start.minX, accuracy: 0.5)
        XCTAssertEqual(bigger.maxY, start.maxY, accuracy: 0.5)
        XCTAssertEqual(bigger.width, 380, accuracy: 0.5)
        XCTAssertEqual(bigger.height, 264, accuracy: 0.5)

        let minimum = MusicDesktopWidgetGeometry.minimumSize(for: .card)
        let tiny = MusicDesktopWidgetGeometry.resized(start, by: CGSize(width: -400, height: -400),
                                                       preset: .card, into: screen)
        XCTAssertEqual(tiny.size, minimum)
    }

    func testStripResizeOnlyChangesWidth() {
        let strip = MusicDesktopWidgetGeometry.rect(for: .strip, in: screen)
        let resized = MusicDesktopWidgetGeometry.resized(strip, by: CGSize(width: -40, height: 90),
                                                         preset: .strip, into: screen)
        XCTAssertEqual(resized.height, MusicDesktopWidgetGeometry.stripHeight, accuracy: 0.5)
        XCTAssertEqual(resized.width, strip.width - 40, accuracy: 0.5)
        XCTAssertEqual(resized.minX, strip.minX, accuracy: 0.5)
    }

    func testNormalizedPlacementRoundTripsPerDisplay() {
        let rect = MusicDesktopWidgetGeometry.rect(for: .card, in: screen)
        let normalized = MusicDesktopWidgetGeometry.normalized(rect, in: screen)
        let restored = MusicDesktopWidgetGeometry.frame(from: normalized, in: screen)
        XCTAssertEqual(restored.origin.x, rect.origin.x, accuracy: 0.5)
        XCTAssertEqual(restored.origin.y, rect.origin.y, accuracy: 0.5)
        XCTAssertEqual(restored.size.width, rect.size.width, accuracy: 0.5)
        XCTAssertEqual(restored.size.height, rect.size.height, accuracy: 0.5)
    }

    func testLockCardHeightHasOneSourceOfTruth() {
        XCTAssertEqual(MusicCardLayout.lockWidth, 340)
        XCTAssertEqual(MusicCardLayout.full.lockHeight(showsVolumeRow: true), 224)
        XCTAssertEqual(MusicCardLayout.full.lockHeight(showsVolumeRow: false), 208)
        XCTAssertEqual(MusicCardLayout.hero.lockHeight(showsVolumeRow: true), 316)
    }

    func testWallpaperDefaultMigrationHonoursAStoredChoiceExactlyOnce() {
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        MusicSurfaceConfig.ensureWallpaperDefaultMigrated(defaults: suite)
        XCTAssertEqual(suite.object(forKey: MusicSurfaceConfig.wallpaperEnabledKey) as? Bool, false)
        XCTAssertEqual(suite.object(forKey: MusicSurfaceConfig.wallpaperDefaultMigratedKey) as? Bool, true)

        let chosen = UserDefaults(suiteName: UUID().uuidString)!
        chosen.set(true, forKey: MusicSurfaceConfig.wallpaperEnabledKey)
        MusicSurfaceConfig.ensureWallpaperDefaultMigrated(defaults: chosen)
        XCTAssertEqual(chosen.object(forKey: MusicSurfaceConfig.wallpaperEnabledKey) as? Bool, true)
        XCTAssertEqual(chosen.object(forKey: MusicSurfaceConfig.wallpaperDefaultMigratedKey) as? Bool, true)
    }
}

// MARK: - §10 desktop music widget: the live move/resize path

/// Drives the production placement object — the same one whose `interaction` closures the SwiftUI card holds —
/// against a real `NSPanel` and its own per-display record, so a no-op move, a stale frame read or a wrong
/// anchor would fail here and not just in the geometry math.
@MainActor
final class MusicDesktopWidgetInteractionTests: XCTestCase {
    /// `NowPlayingProgress.swift` and the placement seam compile into this test target as well, so these tests
    /// drive the same source the app runs, with this module's copy of the types.
    private typealias WidgetPreset = MusicDesktopWidgetPreset
    private typealias WidgetGeometry = MusicDesktopWidgetGeometry

    private let surface = CGRect(x: 0, y: 0, width: 1728, height: 1080)
    private let displayID = "display-under-test"
    private var defaults: UserDefaults!
    private var suiteName = ""
    private let key = "test.frames"

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        suiteName = "musicdesk.interaction.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDragMovesTheRealPanelAndCommitsItsFrame() {
        let (panel, placement) = makePlacement(.card, frame: CGRect(x: 600, y: 400, width: 300, height: 224))

        placement.interaction.move(CGSize(width: 40, height: -60))

        XCTAssertEqual(panel.frame.origin.x, 640, accuracy: 0.5)
        XCTAssertEqual(panel.frame.origin.y, 340, accuracy: 0.5)
        XCTAssertEqual(panel.frame.size, CGSize(width: 300, height: 224), "a drag must not resize")

        placement.interaction.commit()

        let stored = committedFrame()
        XCTAssertNotNil(stored)
        assertFrame(stored, equals: panel.frame)
        assertFrame(placement.restoredFrame, equals: panel.frame)
    }

    func testDragOffTheVisibleFrameIsClampedOnTheRealPanel() {
        let (panel, placement) = makePlacement(.card, frame: CGRect(x: 600, y: 400, width: 300, height: 224))

        placement.interaction.move(CGSize(width: 5000, height: 5000))

        XCTAssertEqual(panel.frame.maxX, surface.maxX, accuracy: 0.5)
        XCTAssertEqual(panel.frame.maxY, surface.maxY, accuracy: 0.5)
        XCTAssertEqual(panel.frame.size, CGSize(width: 300, height: 224))

        placement.interaction.move(CGSize(width: -5000, height: -5000))

        XCTAssertEqual(panel.frame.minX, surface.minX, accuracy: 0.5)
        XCTAssertEqual(panel.frame.minY, surface.minY, accuracy: 0.5)

        placement.interaction.commit()
        assertFrame(committedFrame(), equals: panel.frame)
    }

    func testCornerGripResizeAnchorsTheTopLeadingCornerAndCommits() {
        let (panel, placement) = makePlacement(.card, frame: CGRect(x: 600, y: 400, width: 300, height: 224))

        placement.interaction.resize(CGSize(width: 80, height: 40))

        XCTAssertEqual(panel.frame.width, 380, accuracy: 0.5)
        XCTAssertEqual(panel.frame.height, 264, accuracy: 0.5)
        XCTAssertEqual(panel.frame.minX, 600, accuracy: 0.5, "the left edge must hold still")
        XCTAssertEqual(panel.frame.maxY, 624, accuracy: 0.5, "the top edge must hold still")

        placement.interaction.commit()

        let stored = committedFrame()
        assertFrame(stored, equals: panel.frame)
        XCTAssertEqual(stored?.width ?? 0, 380, accuracy: 0.5)
        XCTAssertEqual(stored?.height ?? 0, 264, accuracy: 0.5)
    }

    func testResizeCannotShrinkBelowThePresetMinimum() {
        for preset: WidgetPreset in [.card, .stage] {
            let (panel, placement) = makePlacement(preset,
                                                   frame: CGRect(x: 900, y: 500, width: 600, height: 500))

            placement.interaction.resize(CGSize(width: -2000, height: -2000))

            XCTAssertEqual(panel.frame.size, WidgetGeometry.minimumSize(for: preset),
                           "\(preset.rawValue) shrank below its minimum")
            XCTAssertEqual(panel.frame.minX, 900, accuracy: 0.5)
            XCTAssertEqual(panel.frame.maxY, 1000, accuracy: 0.5)

            placement.interaction.commit()
            assertFrame(committedFrame(), equals: panel.frame)
        }
    }

    func testStripGripChangesWidthOnly() {
        let start = CGRect(x: 24, y: 24, width: 1680, height: WidgetGeometry.stripHeight)
        let (panel, placement) = makePlacement(.strip, frame: start)

        placement.interaction.resize(CGSize(width: -120, height: 120))

        XCTAssertEqual(panel.frame.width, 1560, accuracy: 0.5)
        XCTAssertEqual(panel.frame.height, WidgetGeometry.stripHeight, accuracy: 0.5,
                       "a strip must never grow taller")
        XCTAssertEqual(panel.frame.minX, start.minX, accuracy: 0.5)
        XCTAssertEqual(panel.frame.maxY, start.maxY, accuracy: 0.5)

        placement.interaction.commit()
        assertFrame(committedFrame(), equals: panel.frame)
    }

    func testCommitSnapsTheRealPanelAndStoresTheSnappedFrame() {
        // Nine points off the right edge: inside the snap threshold, so the widget settles flush.
        let start = CGRect(x: surface.maxX - 300 - 9, y: 500, width: 300, height: 224)
        let (panel, placement) = makePlacement(.card, frame: start)

        placement.interaction.commit()

        XCTAssertEqual(panel.frame.maxX, surface.maxX, accuracy: 0.5, "commit must snap the live panel")
        assertFrame(committedFrame(), equals: panel.frame)
    }

    func testResizeOffTheSurfaceKeepsThePanelInsideIt() {
        let (panel, placement) = makePlacement(.card, frame: CGRect(x: 600, y: 400, width: 300, height: 224))

        placement.interaction.resize(CGSize(width: 5000, height: 5000))

        XCTAssertLessThanOrEqual(panel.frame.maxX, surface.maxX + 0.5)
        XCTAssertLessThanOrEqual(panel.frame.maxY, surface.maxY + 0.5)
        XCTAssertEqual(panel.frame.minX, 600, accuracy: 0.5)
        XCTAssertEqual(panel.frame.maxY, 624, accuracy: 0.5)

        placement.interaction.commit()
        assertFrame(committedFrame(), equals: panel.frame)
    }

    func testPosterIsClickThroughAndNeverResizes() {
        let start = CGRect(x: 0, y: 0, width: 1728, height: 1080)
        let (panel, placement) = makePlacement(.poster, frame: start)

        placement.interaction.resize(CGSize(width: -400, height: -400))

        XCTAssertEqual(panel.frame.size, start.size)
    }

    func testACommittedFrameIsWhatAFreshPlacementRestores() {
        let (panel, placement) = makePlacement(.card, frame: CGRect(x: 600, y: 400, width: 300, height: 224))
        placement.interaction.move(CGSize(width: -100, height: 50))
        placement.interaction.resize(CGSize(width: 60, height: 30))
        placement.interaction.commit()

        let freshPanel = makePanel(frame: .zero)
        let restored = MusicDesktopWidgetPlacement(panel: freshPanel,
                                                   displayID: displayID,
                                                   preset: .card,
                                                   bounds: surface,
                                                   store: store())
        assertFrame(restored.restoredFrame, equals: panel.frame)
    }

    func testNormalizedPlacementRoundTripsWithNonZeroOriginBounds() {
        for bounds in [CGRect(x: 80, y: 68, width: 1648, height: 980),
                       CGRect(x: -1440, y: 74, width: 1440, height: 826)] {
            let rect = WidgetGeometry.rect(for: .card, in: bounds)
            let normalized = WidgetGeometry.normalized(rect, in: bounds)
            assertFrame(WidgetGeometry.frame(from: normalized, in: bounds), equals: rect)
        }
    }

    func testScreenSpaceMouseDeltasKeepDragAndResizeSignsAligned() {
        let start = CGPoint(x: 500, y: 600)
        let movedRightDown = CGPoint(x: 540, y: 560)
        XCTAssertEqual(WidgetGeometry.dragDelta(from: start, to: movedRightDown), CGSize(width: 40, height: -40))
        XCTAssertEqual(WidgetGeometry.resizeDelta(from: start, to: movedRightDown), CGSize(width: 40, height: 40))
    }

    func testCommitReentrancyGuardStopsRecursiveDidMoveCommitLoop() {
        let start = CGRect(x: surface.maxX - 300 - 9, y: 500, width: 300, height: 224)
        let (panel, placement) = makePlacement(.card, frame: start)
        var notifications = 0
        var reentrantCommits = 0
        let token = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification,
                                                           object: panel, queue: nil) { _ in
            notifications += 1
            if placement.commit() != nil { reentrantCommits += 1 }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        XCTAssertNotNil(placement.commit())
        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(reentrantCommits, 0)
        XCTAssertEqual(panel.frame.maxX, surface.maxX, accuracy: 0.5)
    }

    func testRedundantFrameRecordDoesNotBroadcastDefaultsChange() {
        let rect = CGRect(x: 600, y: 400, width: 300, height: 224)
        var changes = 0
        let token = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                           object: defaults, queue: nil) { _ in
            changes += 1
        }
        defer { NotificationCenter.default.removeObserver(token) }

        store().record(rect, for: displayID, in: surface)
        XCTAssertEqual(changes, 1)
        store().record(rect, for: displayID, in: surface)
        XCTAssertEqual(changes, 1, "identical frame must not re-fire UserDefaults.didChangeNotification")
    }

    // MARK: helpers

    private func makePanel(frame: CGRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.setFrame(frame, display: false)
        return panel
    }

    private func makePlacement(_ preset: WidgetPreset, frame: CGRect)
        -> (panel: NSPanel, placement: MusicDesktopWidgetPlacement) {
        let panel = makePanel(frame: frame)
        let placement = MusicDesktopWidgetPlacement(panel: panel,
                                                    displayID: displayID,
                                                    preset: preset,
                                                    bounds: surface,
                                                    store: store())
        return (panel, placement)
    }

    private func store() -> MusicDesktopWidgetFrameStore {
        MusicDesktopWidgetFrameStore(defaults: defaults, key: key)
    }

    /// Reads back what production wrote, not an in-memory copy.
    private func committedFrame() -> CGRect? {
        store().rect(for: displayID, in: surface)
    }

    private func assertFrame(_ actual: CGRect?, equals expected: CGRect,
                             file: StaticString = #filePath, line: UInt = #line) {
        guard let actual else {
            XCTFail("no frame committed for \(displayID)", file: file, line: line)
            return
        }
        XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.5, file: file, line: line)
    }
}
