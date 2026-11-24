import XCTest
@testable import KatiKati

// Boring-look notch skin — pure layout numbers, panel selection and the week strip.

final class NotchLayoutSpecTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func testOpenSizeIsTheReferenceProportion() {
        XCTAssertEqual(NotchLayoutSpec.openSize, CGSize(width: 640, height: 190))
        XCTAssertEqual(NotchGeometry.openSize(for: .boring), CGSize(width: 640, height: 190))
        XCTAssertEqual(NotchGeometry.openSize(for: .classic), CGSize(width: 480, height: 142.5), "0.75× the boring open panel (671b1fa), same proportion")
    }

    func testOpenPanelNeverExceedsScreen() {
        XCTAssertEqual(NotchLayoutSpec.openPanelSize(screenWidth: 1710, closedWidth: 185).width, 640)
        XCTAssertEqual(NotchLayoutSpec.openPanelSize(screenWidth: 500, closedWidth: 185).width, 476)
        XCTAssertEqual(NotchLayoutSpec.openPanelSize(screenWidth: 100, closedWidth: 185).width, 185, "never narrower than the notch")
    }

    // NP-2: the page pill replaced nine icons; it has to fit the ear the header leaves beside the camera.
    func testPagePillAndRightClusterFitBesideTheCutout() {
        for closed in [CGFloat(185), 212] {
            XCTAssertTrue(NotchPageChrome.fits(openWidth: 640, closedWidth: closed), "closed \(closed)")
            XCTAssertGreaterThanOrEqual(NotchPageChrome.leftEarWidth(openWidth: 640, closedWidth: closed),
                                        NotchPageChrome.pillWidth())
        }
        XCTAssertEqual(NotchPageChrome.leftEarWidth(openWidth: 100, closedWidth: 185), 0)
        XCTAssertEqual(NotchPageChrome.leftEarWidth(openWidth: 640, closedWidth: 185),
                       (640 - 185) / 2 - 4, accuracy: 0.001)
        XCTAssertGreaterThan(NotchPageChrome.pillHeight, 0)
    }

    func testHeaderHeightFollowsNotchButFitsButtons() {
        XCTAssertEqual(NotchLayoutSpec.headerHeight(closedHeight: 32), 32)
        XCTAssertEqual(NotchLayoutSpec.headerHeight(closedHeight: 10), NotchLayoutSpec.headerButtonSize)
    }

    func testMusicOrIdleShowsThePlayerNeverTheClock() {
        XCTAssertEqual(NotchLayoutSpec.panels(activityKind: .music, calendarEnabled: true), .init(left: .music, showsCalendar: true))
        XCTAssertEqual(NotchLayoutSpec.panels(activityKind: .clock, calendarEnabled: true).left, .music)
        for kind in LiveActivityKind.allCases where kind != .music && kind != .clock {
            XCTAssertEqual(NotchLayoutSpec.panels(activityKind: kind, calendarEnabled: false), .init(left: .activity, showsCalendar: false))
        }
    }

    func testEarZonesFlankTheCutoutAndGrowWithTheActivity() {
        let m = NotchGeometry.metrics(screenWidth: 1710, safeAreaTop: 32, auxLeftWidth: 760, auxRightWidth: 760, menuBarHeight: 32)
        XCTAssertTrue(m.hasHardwareNotch)
        let idle = NotchLayoutSpec.earZones(metrics: m, showsActivity: false)
        let live = NotchLayoutSpec.earZones(metrics: m, showsActivity: true)
        XCTAssertEqual(idle.left.maxX, m.cameraKeepoutBox.minX)
        XCTAssertEqual(idle.right.minX, m.cameraKeepoutBox.maxX)
        XCTAssertEqual(idle.right.maxX, m.closedSize.width, accuracy: 0.001)
        XCTAssertEqual(live.left.width, idle.left.width + NotchGeometry.sneakSide)
        XCTAssertEqual(live.right.width, idle.right.width + NotchGeometry.sneakSide, accuracy: 0.001)
        XCTAssertEqual(live.left.height, m.closedSize.height)
    }

    func testEarZonesAreEmptyOnAFakeNotch() {
        let m = NotchGeometry.metrics(screenWidth: 1920, safeAreaTop: 0, auxLeftWidth: nil, auxRightWidth: nil, menuBarHeight: 24)
        XCTAssertEqual(NotchLayoutSpec.earZones(metrics: m, showsActivity: true), .init(left: .zero, right: .zero))
    }

    func testWeekStripHasSevenDaysTodayInTheMiddle() {
        let now = Date(timeIntervalSince1970: 1_776_000_000) // mid-April 2026
        let strip = NotchLayoutSpec.weekStrip(now: now, calendar: utc)
        XCTAssertEqual(strip.count, 7)
        XCTAssertEqual(strip.filter(\.isToday).count, 1)
        XCTAssertTrue(strip[3].isToday)
        XCTAssertEqual(strip[3].dayNumber, utc.component(.day, from: now))
        for i in 1..<7 {
            XCTAssertEqual(utc.dateComponents([.day], from: strip[i - 1].date, to: strip[i].date).day, 1)
        }
    }

    func testLiquidPresetAndShapeTargetsSupportNotchAndExternalDisplays() {
        XCTAssertTrue(NotchShellPreset.allCases.contains(.liquid))
        XCTAssertEqual(NotchGeometry.openSize(for: .liquid), NotchGeometry.liquidOpenSize)

        let notchedIdle = LiquidShapeTargets.resting(mode: .idle, notchHalfWidth: 92.5, notchHeight: 32, hasHardwareNotch: true)
        XCTAssertEqual(notchedIdle.kBezel, 6.0)
        XCTAssertEqual(notchedIdle.mainHalfWidth, 92.5)

        let externalPill = LiquidShapeTargets.resting(mode: .idle, notchHalfWidth: 92.5, notchHeight: 24, hasHardwareNotch: false)
        XCTAssertEqual(externalPill.kBezel, 0.0, "External display renders a floating pill with no bezel flare")
        XCTAssertEqual(externalPill.mainHalfWidth, 74.0)

        let cardState = LiquidShapeTargets.resting(mode: .card, notchHalfWidth: 92.5, notchHeight: 32, hasHardwareNotch: true)
        let uniforms = LiquidShapeUniforms(
            state: cardState,
            viewSize: SIMD2(640, 220),
            scale: 2,
            notchHalfWidth: 91.5,
            notchHeight: 31
        )
        XCTAssertEqual(LiquidShapeSDF.hit(SIMD2(320, 80), uniforms), .card)
        XCTAssertNil(LiquidShapeSDF.hit(SIMD2(20, 20), uniforms))

        let lab = LiquidOKLab.fromSRGB(SIMD3(1, 0, 0))
        let roundTrip = LiquidOKLab.toSRGB(L: lab.x, a: lab.y, b: lab.z)
        XCTAssertEqual(roundTrip.x, 1, accuracy: 0.02)
        XCTAssertEqual(roundTrip.y, 0, accuracy: 0.02)
    }

    func testLiquidExtrasESPNParserAndWallpaperBackup() throws {
        let json = """
        {"events":[{"id":"401","status":{"type":{"state":"in","shortDetail":"Q3 4:12"}},"competitions":[{"competitors":[
          {"homeAway":"home","score":"88","team":{"abbreviation":"LAL"}},
          {"homeAway":"away","score":"84","team":{"abbreviation":"BOS"}}
        ]}]}]}
        """
        let scores = LiquidESPNParser.parseScoreboard(Data(json.utf8), league: .nba)
        XCTAssertEqual(scores.count, 1)
        XCTAssertEqual(scores[0].homeAbbrev, "LAL")
        XCTAssertEqual(scores[0].awayAbbrev, "BOS")
        XCTAssertEqual(scores[0].homeScore, "88")
        XCTAssertTrue(scores[0].isLive)

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("lq5-wp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try LiquidWallpaperBackup.saveOriginalPath("/Library/Desktop Pictures/Sequoia.heic", in: tmp)
        try LiquidWallpaperBackup.saveOriginalPath("/should/not/overwrite.heic", in: tmp)
        XCTAssertEqual(LiquidWallpaperBackup.consumeOriginalPath(in: tmp), "/Library/Desktop Pictures/Sequoia.heic")
        XCTAssertNil(LiquidWallpaperBackup.consumeOriginalPath(in: tmp))
    }

    func testNotchDisplaySkinPerDisplayResolution() {
        let suite = "test.notchDisplaySkin.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(
            NotchDisplaySkin.resolve(display: "1", fallback: .liquid, stored: NotchDisplaySkin.stored(defaults)),
            .liquid
        )
        NotchDisplaySkin.set(.boring, for: "1", defaults)
        NotchDisplaySkin.set(.dynamicIsland, for: "uuid-ext", defaults)
        let stored = NotchDisplaySkin.stored(defaults)
        XCTAssertEqual(NotchDisplaySkin.resolve(display: "1", fallback: .liquid, stored: stored), .boring)
        XCTAssertEqual(
            NotchDisplaySkin.resolve(display: "1", displayUUID: "uuid-ext", fallback: .liquid, stored: stored),
            .dynamicIsland,
            "UUID match takes precedence over numeric display ID"
        )
        NotchDisplaySkin.set(nil, for: "1", defaults)
        XCTAssertEqual(
            NotchDisplaySkin.resolve(display: "1", fallback: .liquid, stored: NotchDisplaySkin.stored(defaults)),
            .liquid
        )
    }

    func testWeekStripCrossesMonthBoundary() {
        let now = utc.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        let numbers = NotchLayoutSpec.weekStrip(now: now, calendar: utc).map(\.dayNumber)
        XCTAssertEqual(numbers, [29, 30, 31, 1, 2, 3, 4])
    }

    func testClockText() {
        XCTAssertEqual(NotchLayoutSpec.clockText(0), "0:00")
        XCTAssertEqual(NotchLayoutSpec.clockText(65), "1:05")
        XCTAssertEqual(NotchLayoutSpec.clockText(3725), "1:02:05")
        XCTAssertEqual(NotchLayoutSpec.clockText(-4), "0:00")
    }

    // Phase 34 witness: the notch pages must never ship hardcoded demo numbers again.
    func testNotchPagesHaveNoMockLiterals() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for (file, bad) in [("NotchProductivityPageView", ["No conflicts today"]),
                            ("NotchAIPageView", ["Claude 3.7 Sonnet"])] {
            let src = try String(contentsOf: root.appendingPathComponent("App/Scenes/Notch/\(file).swift"), encoding: .utf8)
            for literal in bad { XCTAssertFalse(src.contains(literal), "\(file) still has \(literal)") }
        }
    }

    // Phase 34e: a finished download is its own deduped event kind.
    func testDownloadFinishedDedupeKeyDiffersByName() {
        XCTAssertNotEqual(LiveEvent.downloadFinished(name: "a.zip").dedupeKey, LiveEvent.downloadFinished(name: "b.zip").dedupeKey)
        XCTAssertEqual(LiveEvent.downloadFinished(name: nil).dedupeKey, "download|")
    }

    // Phase 48a: a card that asks for more height than the page body has is clipped by the panel with no
    // warning, so the Productivity page's row budget is asserted against the real body instead of eyeballed.
    func testProductivityCardsFitThePageBody() {
        XCTAssertEqual(NotchLayoutSpec.pageBodyHeight(headerHeight: 38), 132)
        // 38 is the menu bar of this machine's notched display; 44 a taller one; 26 the no-notch fallback.
        for header in [CGFloat(38), 44, NotchLayoutSpec.headerHeight(closedHeight: 20)] {
            for hasReminder in [true, false] {
                XCTAssertTrue(
                    NotchProductivityLayout.fits(headerHeight: header, hasReminder: hasReminder,
                                                 cardPadding: NotchDesignSpec.cardPadding),
                    "header \(header) with a reminder: \(hasReminder)"
                )
            }
        }
        XCTAssertFalse(
            NotchProductivityLayout.fits(headerHeight: 120, hasReminder: true, cardPadding: NotchDesignSpec.cardPadding),
            "the guard has to be able to fail"
        )
    }
}
