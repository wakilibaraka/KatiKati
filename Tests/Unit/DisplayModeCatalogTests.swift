import XCTest
@testable import KatiKati

final class DisplayModeCatalogTests: XCTestCase {
    private func mode(_ points: Int, _ pixels: Int, refresh: Double = 60) -> DisplayModeOption {
        DisplayModeOption(pixelWidth: pixels, pixelHeight: pixels * 9 / 16,
                          pointWidth: points, pointHeight: points * 9 / 16, refresh: refresh)
    }

    func testScaleDecidesHiDPI() {
        XCTAssertEqual(mode(960, 1920).scale, 2, accuracy: 1e-9)
        XCTAssertTrue(mode(960, 1920).isHiDPI)
        XCTAssertFalse(mode(1920, 1920).isHiDPI, "a 1x mode is not retina however big it is")
        XCTAssertTrue(mode(1280, 1920).isHiDPI, "exactly 1.5 still counts")
        XCTAssertFalse(mode(1600, 2000).isHiDPI, "1.25 is a stretched mode, not retina")
    }

    func testHiDPISortsFirstAndDuplicatesCollapse() {
        let list = [
            mode(1920, 1920, refresh: 60),
            mode(960, 1920, refresh: 60),
            mode(960, 1920, refresh: 60),   // the same mode advertised in another colour depth
            mode(1280, 2560, refresh: 60),
        ]
        let sorted = DisplayModeCatalog.sorted(list)
        XCTAssertEqual(sorted.count, 3, "identical pictures collapse to one row")
        XCTAssertTrue(sorted.first?.isHiDPI ?? false, "the sharp rows lead the menu")
        XCTAssertEqual(sorted.filter(\.isHiDPI).count, 2)
    }

    func testMoreDesktopAreaWinsWithinTheSameDensity() {
        let sorted = DisplayModeCatalog.sorted([mode(1280, 2560), mode(1920, 3840), mode(1440, 2880)])
        XCTAssertEqual(sorted.map(\.pointWidth), [1920, 1440, 1280])
    }

    func testSharpestAtCurrentSizeKeepsTheDesktopSize() throws {
        let current = mode(1920, 1920)
        let modes = [mode(1920, 3840), mode(960, 1920), mode(2560, 2560)]
        let sharp = try XCTUnwrap(DisplayModeCatalog.sharpestAtCurrentSize(current: current, in: modes))
        XCTAssertEqual(sharp.pointWidth, 1920, "sharpening must not also change how much fits")
        XCTAssertEqual(sharp.scale, 2, accuracy: 1e-9)
        XCTAssertNil(DisplayModeCatalog.sharpestAtCurrentSize(current: mode(960, 1920), in: modes),
                     "already sharp: nothing to offer")
        XCTAssertNil(DisplayModeCatalog.sharpestAtCurrentSize(current: current, in: [mode(2560, 2560)]),
                     "no sharp twin at this size")
    }

    func testLabelReadsLikeAMenuRow() {
        XCTAssertEqual(mode(1440, 2880).label, "1440 × 810 HiDPI · 60 Hz")
        XCTAssertEqual(mode(1920, 1920, refresh: 0).label, "1920 × 1080")
    }

    func testSamePictureIgnoresRefresh() {
        XCTAssertTrue(DisplayModeCatalog.isSamePicture(mode(1920, 1920, refresh: 60), mode(1920, 1920, refresh: 120)))
        XCTAssertFalse(DisplayModeCatalog.isSamePicture(mode(1920, 1920), mode(960, 1920)))
    }

    // MARK: - Arrangement presets (SN-6)

    func testQuartzOriginFlipsAroundThePrimaryHeight() {
        // Primary: 1710×1112 at the Cocoa origin, so it sits at Quartz 0,0.
        XCTAssertEqual(DisplayArrangementGeometry.quartzOrigin(cocoaFrame: CGRect(x: 0, y: 0, width: 1710, height: 1112),
                                                              primaryMaxY: 1112),
                       CGPoint(x: 0, y: 0))
        // A panel physically above it: Cocoa y starts at the primary's top edge, Quartz y goes negative.
        XCTAssertEqual(DisplayArrangementGeometry.quartzOrigin(cocoaFrame: CGRect(x: -164, y: 1112, width: 1920, height: 1080),
                                                              primaryMaxY: 1112),
                       CGPoint(x: -164, y: -1080))
        // A panel to the right of the primary keeps the primary's height in the flip.
        XCTAssertEqual(DisplayArrangementGeometry.quartzOrigin(cocoaFrame: CGRect(x: 1710, y: 0, width: 1280, height: 720),
                                                              primaryMaxY: 1112),
                       CGPoint(x: 1710, y: 392))
    }

    func testEntryKeepsTheDisplayKeyNotTheIndex() {
        let entry = DisplayArrangementGeometry.entry(displayKey: "402CE39A",
                                                     cocoaFrame: CGRect(x: 10, y: 20, width: 100, height: 50),
                                                     primaryMaxY: 1112)
        XCTAssertEqual(entry.displayKey, "402CE39A")
        XCTAssertEqual(entry.originX, 10)
        XCTAssertEqual(entry.originY, 1042)
    }

    func testNormalizedKeepsTheFirstEntryPerDisplay() {
        let a = DisplayArrangementEntry(displayKey: "A", originX: 0, originY: 0)
        let duplicateA = DisplayArrangementEntry(displayKey: "A", originX: 99, originY: 99)
        let b = DisplayArrangementEntry(displayKey: "B", originX: 5, originY: 5)
        XCTAssertEqual(DisplayArrangementGeometry.normalized([a, duplicateA, b]), [a, b])
    }

    func testArrangementIsCompleteOnlyWhenEveryDisplayIsConnected() {
        let preset = DisplayArrangement(name: "Desk", entries: [
            DisplayArrangementEntry(displayKey: "A", originX: 0, originY: 0),
            DisplayArrangementEntry(displayKey: "B", originX: 1710, originY: 0),
        ])
        XCTAssertTrue(DisplayArrangementGeometry.isComplete(preset, liveKeys: ["A", "B"]))
        XCTAssertTrue(DisplayArrangementGeometry.isComplete(preset, liveKeys: ["A", "B", "C"]),
                      "an extra connected display does not invalidate the preset")
        XCTAssertFalse(DisplayArrangementGeometry.isComplete(preset, liveKeys: ["A"]),
                       "a missing display would leave its neighbour somewhere nobody chose")
        XCTAssertEqual(DisplayArrangementGeometry.matchCount(preset, liveKeys: ["A", "C"]), 1)
        XCTAssertFalse(DisplayArrangementGeometry.isComplete(DisplayArrangement(name: "Empty", entries: []),
                                                             liveKeys: ["A"]))
    }

    func testArrangementRoundTripsThroughCodable() throws {
        let preset = DisplayArrangement(name: "Desk", entries: [
            DisplayArrangementEntry(displayKey: "A", originX: 0, originY: 0),
            DisplayArrangementEntry(displayKey: "B", originX: -164, originY: -1080),
        ])
        let decoded = try JSONDecoder().decode(DisplayArrangement.self, from: JSONEncoder().encode(preset))
        XCTAssertEqual(decoded, preset)
    }

    func testArrangementStoreSavesAndLoads() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "DisplayArrangementTests"))
        suite.removePersistentDomain(forName: "DisplayArrangementTests")
        XCTAssertTrue(DisplayArrangementStore.load(defaults: suite).isEmpty)
        let preset = DisplayArrangement(name: "Arrangement 1", entries: [
            DisplayArrangementEntry(displayKey: "A", originX: 0, originY: 0),
        ])
        DisplayArrangementStore.save([preset], defaults: suite)
        XCTAssertEqual(DisplayArrangementStore.load(defaults: suite), [preset])
        suite.removePersistentDomain(forName: "DisplayArrangementTests")
    }
}
