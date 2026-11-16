import XCTest

final class StorageScanMathTests: XCTestCase {
    private func item(_ path: String, _ bytes: Int64) -> StorageItem { StorageItem(path: path, bytes: bytes) }

    func testTopSortsBiggestFirstAndDropsEmpty() {
        let top = StorageScanMath.top([item("/a", 5), item("/b", 0), item("/c", 9), item("/d", 7)], limit: 2)
        XCTAssertEqual(top.map(\.path), ["/c", "/d"])
    }

    func testTiesKeepPathOrderAndZeroLimitIsEmpty() {
        XCTAssertEqual(StorageScanMath.top([item("/b", 3), item("/a", 3)], limit: 5).map(\.path), ["/a", "/b"])
        XCTAssertTrue(StorageScanMath.top([item("/a", 3)], limit: 0).isEmpty)
    }

    func testShareIsRelativeToLargest() {
        let big = item("/big", 200)
        XCTAssertEqual(StorageScanMath.share(item("/x", 50), of: big), 0.25)
        XCTAssertEqual(StorageScanMath.share(big, of: big), 1)
        XCTAssertEqual(StorageScanMath.share(big, of: nil), 0)
    }

    func testSystemAndVirtualTreesAreNotScanned() {
        XCTAssertFalse(StorageScanMath.isScannable("/System/Library"))
        XCTAssertFalse(StorageScanMath.isScannable("/Volumes"))
        XCTAssertTrue(StorageScanMath.isScannable("/Users/me/Library"))
        XCTAssertTrue(StorageScanMath.isScannable("/SystemExtras"), "prefix match must respect the path boundary")
    }

    func testCompactLabelFitsTheClosedSlot() {
        XCTAssertEqual(StorageScanMath.compact(29_590_000_000), "29 GB")
        XCTAssertEqual(StorageScanMath.compact(1_250_000_000_000), "1.2 TB")
        XCTAssertEqual(StorageScanMath.compact(-5), "0 GB")
    }

    func testNameIsLastComponent() {
        XCTAssertEqual(item("/Users/me/Movies", 1).name, "Movies")
    }

    func testCategoryByExtensionIsCaseInsensitiveAndNilForOthers() {
        XCTAssertEqual(StorageCategory.of(path: "/a/IMG_1.HEIC"), .photos)
        XCTAssertEqual(StorageCategory.of(path: "/a/song.flac"), .music)
        XCTAssertEqual(StorageCategory.of(path: "/a/report.pdf"), .documents)
        XCTAssertNil(StorageCategory.of(path: "/a/main.swift"))
        XCTAssertNil(StorageCategory.of(path: "/a/noext"))
    }

    func testDeveloperTargetsAreUniqueAndNeverNestInEachOther() {
        let targets = StorageScanMath.developerTargets(home: "/h")
        XCTAssertEqual(Set(targets).count, targets.count)
        for a in targets { for b in targets where a != b { XCTAssertFalse(b.hasPrefix(a + "/"), "\(b) nests in \(a)") } }
        XCTAssertEqual(StorageScanMath.personalRoots(home: "/h").first, "/h/Desktop")
    }
}

/// 55d: the review list only offers stale, large, rebuildable folders.
final class CleanupPlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000_000)

    private func candidate(_ path: String, _ bytes: Int64, daysOld: Double) -> CleanupCandidate {
        CleanupCandidate(path: path, bytes: bytes, lastModified: now.addingTimeInterval(-daysOld * 86_400))
    }

    func testOnlyStaleLargeNonSystemEntriesAreOffered() {
        let entries = [
            candidate("/h/Library/Caches/com.example.app", 200_000_000, daysOld: 30),
            candidate("/h/Library/Caches/com.apple.Safari", 900_000_000, daysOld: 90),
            candidate("/h/Library/Caches/com.katikati.app", 300_000_000, daysOld: 60),
            candidate("/h/Library/Caches/tiny", 10_000_000, daysOld: 30),
            candidate("/h/Library/Caches/fresh", 400_000_000, daysOld: 1),
            candidate("/h/Library/Caches/marker.noindex", 500_000_000, daysOld: 40),
        ]
        let plan = CleanupPlan.candidates(from: entries, now: now)
        XCTAssertEqual(plan.map(\.path), ["/h/Library/Caches/com.example.app"])
        XCTAssertEqual(CleanupPlan.totalBytes(plan), 200_000_000)
    }

    func testSizeThresholdAndAgeBoundary() {
        let exactly = [candidate("/h/Library/Logs/a", CleanupPlan.minBytes, daysOld: Double(CleanupPlan.minAgeDays))]
        XCTAssertEqual(CleanupPlan.candidates(from: exactly, now: now).count, 1)
        let younger = [candidate("/h/Library/Logs/a", CleanupPlan.minBytes, daysOld: Double(CleanupPlan.minAgeDays) - 0.01)]
        XCTAssertTrue(CleanupPlan.candidates(from: younger, now: now).isEmpty)
    }

    func testRootsStayInsideTheHomeCachesAndLogs() {
        let roots = CleanupPlan.roots(home: "/h")
        XCTAssertTrue(roots.allSatisfy { $0.hasPrefix("/h/") })
        XCTAssertTrue(roots.contains("/h/Library/Caches"))
        XCTAssertTrue(roots.contains("/h/Library/Logs"))
        XCTAssertFalse(roots.contains("/System"))
    }
}

/// Droppy Slice D-AppCleaner: test app leftover scan plan.
final class AppLeftoverScanPlanTests: XCTestCase {
    private let home = "/Users/testuser"

    func testProtectedBundleIDsAreRejected() {
        XCTAssertTrue(AppLeftoverScanPlan.isProtected(bundleID: "com.apple.Safari"))
        XCTAssertTrue(AppLeftoverScanPlan.isProtected(bundleID: "com.apple.finder"))
        XCTAssertTrue(AppLeftoverScanPlan.isProtected(bundleID: "com.katikati.app"))
        XCTAssertTrue(AppLeftoverScanPlan.isProtected(bundleID: ""))
        XCTAssertFalse(AppLeftoverScanPlan.isProtected(bundleID: "com.spotify.client"))
        XCTAssertTrue(AppLeftoverScanPlan.expectedCandidatePaths(home: home, bundleID: "com.apple.Safari", appName: "Safari").isEmpty)
        XCTAssertTrue(AppLeftoverScanPlan.expectedCandidatePaths(home: home, bundleID: "com.katikati.app", appName: "KatiKati").isEmpty)
    }

    func testExpectedCandidatePathsGenerateStandardRoots() {
        let paths = AppLeftoverScanPlan.expectedCandidatePaths(home: home, bundleID: "com.spotify.client", appName: "Spotify.app")
        XCTAssertTrue(paths.contains("/Users/testuser/Library/Application Support/Spotify"))
        XCTAssertTrue(paths.contains("/Users/testuser/Library/Application Support/com.spotify.client"))
        XCTAssertTrue(paths.contains("/Users/testuser/Library/Caches/com.spotify.client"))
        XCTAssertTrue(paths.contains("/Users/testuser/Library/Preferences/com.spotify.client.plist"))
        XCTAssertTrue(paths.contains("/Users/testuser/Library/Saved Application State/com.spotify.client.savedState"))
    }

    func testMatchesByBundleIDAndAppName() {
        XCTAssertTrue(AppLeftoverScanPlan.matches(entryName: "com.spotify.client", bundleID: "com.spotify.client", appName: "Spotify"))
        XCTAssertTrue(AppLeftoverScanPlan.matches(entryName: "com.spotify.client.plist", bundleID: "com.spotify.client", appName: "Spotify"))
        XCTAssertTrue(AppLeftoverScanPlan.matches(entryName: "com.spotify.client.savedState", bundleID: "com.spotify.client", appName: "Spotify"))
        XCTAssertTrue(AppLeftoverScanPlan.matches(entryName: "Spotify", bundleID: "com.spotify.client", appName: "Spotify"))
        XCTAssertFalse(AppLeftoverScanPlan.matches(entryName: "com.apple.Safari", bundleID: "com.spotify.client", appName: "Spotify"))
        XCTAssertFalse(AppLeftoverScanPlan.matches(entryName: "UnrelatedApp", bundleID: "com.spotify.client", appName: "Spotify"))
    }

    func testCandidatePathsFiltersExistingEntries() {
        let existing = [
            "/Users/testuser/Library/Application Support/Spotify",
            "/Users/testuser/Library/Caches/com.spotify.client",
            "/Users/testuser/Library/Preferences/com.spotify.client.plist",
            "/Users/testuser/Library/Preferences/com.other.app.plist",
            "/Users/testuser/Desktop/Spotify.app" // Outside target directories
        ]
        let found = AppLeftoverScanPlan.candidatePaths(home: home, existingPaths: existing, bundleID: "com.spotify.client", appName: "Spotify")
        XCTAssertEqual(found, [
            "/Users/testuser/Library/Application Support/Spotify",
            "/Users/testuser/Library/Caches/com.spotify.client",
            "/Users/testuser/Library/Preferences/com.spotify.client.plist"
        ])
    }
}
