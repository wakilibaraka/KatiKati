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
}
