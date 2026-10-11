import XCTest
@testable import KatiKati

final class LauncherAppIndexTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func app(_ id: String, _ name: String, days: Double = 100, path: String? = nil) -> LauncherApp {
        LauncherApp(bundleID: id, name: name, path: path ?? "/Applications/\(name).app", installedAt: now.addingTimeInterval(-days * 86_400))
    }

    func testMergeDedupesPrefersShortestPathAndExcludes() {
        let a = app("x", "X", path: "/Users/me/Downloads/X.app")
        let b = app("x", "X", path: "/Applications/X.app")
        let c = app("y", "Y")
        let out = LauncherAppIndex.merged([a, b, c, app("", "NoID")], excluding: ["y"])
        XCTAssertEqual(out.map(\.path), ["/Applications/X.app"])
    }

    func testMergedSortsByNameCaseInsensitive() {
        let out = LauncherAppIndex.merged([app("b", "banana"), app("a", "Apple"), app("c", "Cherry")])
        XCTAssertEqual(out.map(\.name), ["Apple", "banana", "Cherry"])
    }

    func testSectionsOrderAndNoDuplicates() {
        let apps = [app("p", "Pinned"), app("u1", "Used1"), app("u2", "Used2"), app("n", "New", days: 2), app("old", "Old")]
        var usage: [String: LauncherUsage] = [:]
        LauncherAppIndex.recordLaunch(&usage, bundleID: "u1", at: now)
        LauncherAppIndex.recordLaunch(&usage, bundleID: "u2", at: now)
        LauncherAppIndex.recordLaunch(&usage, bundleID: "u2", at: now)
        LauncherAppIndex.recordLaunch(&usage, bundleID: "p", at: now)
        let s = LauncherAppIndex.sections(apps: apps, usage: usage, pinned: ["p", "gone"], now: now)
        XCTAssertEqual(s.pinned.map(\.bundleID), ["p"])
        XCTAssertEqual(s.mostUsed.map(\.bundleID), ["u2", "u1"])
        XCTAssertEqual(s.recentlyInstalled.map(\.bundleID), ["n"])
    }

    func testRecentWindowAndFutureDatesExcluded() {
        let apps = [app("a", "A", days: 29), app("b", "B", days: 31), app("c", "C", days: -1)]
        let s = LauncherAppIndex.sections(apps: apps, usage: [:], pinned: [], now: now)
        XCTAssertEqual(s.recentlyInstalled.map(\.bundleID), ["a"])
    }

    func testLimitsAndNegativeLimits() {
        let apps = (0..<5).map { app("a\($0)", "A\($0)", days: Double($0)) }
        XCTAssertEqual(LauncherAppIndex.sections(apps: apps, usage: [:], pinned: [], now: now, recentLimit: 2).recentlyInstalled.count, 2)
        XCTAssertTrue(LauncherAppIndex.sections(apps: apps, usage: [:], pinned: [], now: now, recentLimit: -1).recentlyInstalled.isEmpty)
    }

    func testTogglePin() {
        XCTAssertEqual(LauncherAppIndex.togglePin(["a"], "b"), ["a", "b"])
        XCTAssertEqual(LauncherAppIndex.togglePin(["a", "b"], "a"), ["b"])
    }

    func testSearchScoring() {
        XCTAssertEqual(LauncherSearch.score(query: "safari", name: "Safari"), 1000)
        XCTAssertNotNil(LauncherSearch.score(query: "vsc", name: "Visual Studio Code"))
        XCTAssertNotNil(LauncherSearch.score(query: "ps", name: "Photoshop"))
        XCTAssertNil(LauncherSearch.score(query: "zzz", name: "Safari"))
        XCTAssertNil(LauncherSearch.score(query: "  ", name: "Safari"))
        XCTAssertEqual(LauncherSearch.score(query: "cafe", name: "Café"), 1000)
    }

    func testSearchRanksPrefixOverSubstringAndUsageBreaksTies() {
        let apps = [app("1", "Notes Pro"), app("2", "Keynote"), app("3", "Notion")]
        let usage = ["3": LauncherUsage(launches: 5, lastLaunched: now)]
        XCTAssertEqual(LauncherSearch.search("not", in: apps, usage: usage).map(\.bundleID), ["3", "1", "2"])
    }
}
