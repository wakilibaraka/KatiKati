import XCTest
@testable import KatiKati

// Phase 8d — the partial-file heuristic behind the Downloads chip's activity badge.

final class DownloadActivityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    func testBrowserPartialExtensionsAreRecognised() {
        for name in ["a.zip.crdownload", "movie.mp4.download", "x.iso.part", "y.dmg.opdownload", "Z.PDF.CRDOWNLOAD"] {
            XCTAssertTrue(DownloadActivity.isPartial(name), name)
        }
    }

    func testFinishedAndUnrelatedFilesAreNotPartial() {
        for name in ["a.zip", "notes.txt", "download", "crdownload", ".DS_Store", "partial-results.csv"] {
            XCTAssertFalse(DownloadActivity.isPartial(name), name)
        }
    }

    func testOnlyRecentlyWrittenPartialsCountAsActive() {
        let entries = [
            DownloadActivity.Entry(name: "a.crdownload", modified: now.addingTimeInterval(-2)),
            DownloadActivity.Entry(name: "b.download", modified: now.addingTimeInterval(-10)),
            DownloadActivity.Entry(name: "c.part", modified: now.addingTimeInterval(-11)),
            DownloadActivity.Entry(name: "done.zip", modified: now),
        ]
        XCTAssertEqual(DownloadActivity.activeCount(entries, now: now), 2, "a (2 s) and b (exactly at the window) are active")
    }

    func testEmptyAndFutureTimestamps() {
        XCTAssertEqual(DownloadActivity.activeCount([], now: now), 0)
        XCTAssertEqual(DownloadActivity.activeCount([.init(name: "a.crdownload", modified: now.addingTimeInterval(5))], now: now), 1, "clock skew must not hide a download")
    }
}
