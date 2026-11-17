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

/// The Downloads read rule: a privacy-protected folder we pin ourselves is read only after the click
/// that opens it, never at launch — Files & Folders hands its grant to a code signature, and an
/// unsigned build gets a new one on every rebuild, so a launch-time read raises the system prompt with
/// no user action behind it.
final class PinnedFolderReadRuleTests: XCTestCase {
    private let downloads = "/Users/me/Downloads"
    private let documents = "/Users/me/Documents"

    private func unread(_ path: String, seeds: Set<String> = [], opened: Set<String> = []) -> Bool {
        PinnedFolderReadRule.isUnreadUntilOpened(path: path, seeds: seeds, openedThisSession: opened, builtin: downloads)
    }

    func testBuiltinIsUnreadUntilOpenedThisLaunch() {
        XCTAssertTrue(unread(downloads))
        XCTAssertFalse(unread(downloads, opened: [downloads]))
    }

    func testTrailingSlashIsTheSameFolder() {
        XCTAssertTrue(unread(downloads + "/"))
        XCTAssertFalse(unread(downloads + "/", opened: [downloads]))
    }

    func testAFolderTheUserPinnedIsReadAtOnce() {
        XCTAssertFalse(unread(documents))
    }

    func testAnUnopenedSeedIsUnreadWhateverItIs() {
        XCTAssertTrue(unread(documents, seeds: [documents]))
        XCTAssertTrue(unread(documents, seeds: [documents], opened: [documents]),
                      "the seed itself is cleared by noteOpened, not by this predicate")
    }

    func testNoBuiltinMeansNothingIsHeldBack() {
        XCTAssertFalse(PinnedFolderReadRule.isUnreadUntilOpened(path: downloads, seeds: [], openedThisSession: [], builtin: nil))
    }
}

final class FolderNewFileBadgeModelTests: XCTestCase {
    func testCountsOnlyItemsNewerThanLastOpenedAt() {
        let t0 = Date(timeIntervalSince1970: 1000)
        let entries = [
            FolderContentsLoader.Entry(url: URL(fileURLWithPath: "/a"), name: "a", isDirectory: false,
                                       dateAdded: t0.addingTimeInterval(-10), dateModified: t0),
            FolderContentsLoader.Entry(url: URL(fileURLWithPath: "/b"), name: "b", isDirectory: false,
                                       dateAdded: t0, dateModified: t0),
            FolderContentsLoader.Entry(url: URL(fileURLWithPath: "/c"), name: "c", isDirectory: false,
                                       dateAdded: t0.addingTimeInterval(5), dateModified: t0),
            FolderContentsLoader.Entry(url: URL(fileURLWithPath: "/d"), name: "d", isDirectory: false,
                                       dateAdded: nil, dateModified: t0.addingTimeInterval(15)),
        ]
        XCTAssertEqual(FolderNewFileBadgeModel.countNew(entries: entries, since: nil), 0)
        XCTAssertEqual(FolderNewFileBadgeModel.countNew(entries: entries, since: t0), 2)
    }
}
