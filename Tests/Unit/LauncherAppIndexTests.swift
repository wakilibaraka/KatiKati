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

    func testPageFillsOneRowUsageThenPresets() {
        let apps = [app("com.apple.Safari", "Safari"), app("com.apple.Terminal", "Terminal"), app("com.apple.finder", "Finder"),
                    app("u", "Used"), app("n", "New", days: 2), app("old", "Old")]
        var usage: [String: LauncherUsage] = [:]
        LauncherAppIndex.recordLaunch(&usage, bundleID: "u", at: now)
        let page = LauncherAppIndex.page(apps: apps, usage: usage, pinned: [], columns: 3, now: now)
        // Real usage first, then presets in preset order; the row stops at `columns`.
        XCTAssertEqual(page.mostUsed.map(\.bundleID), ["u", "com.apple.Safari", "com.apple.Terminal"])
        // Not repeated above; Finder is a preset that missed the row so it is not "recent" (it is old).
        XCTAssertEqual(page.recentlyInstalled.map(\.bundleID), ["n"])
        XCTAssertEqual(page.all.count, 6)
    }

    func testPagePinsFirstAndMissingPresetsSkipped() {
        let apps = [app("a", "A"), app("com.apple.Safari", "Safari")]
        let page = LauncherAppIndex.page(apps: apps, usage: [:], pinned: ["a", "gone"], columns: 5, now: now)
        XCTAssertEqual(page.mostUsed.map(\.bundleID), ["a", "com.apple.Safari"])
        XCTAssertEqual(LauncherAppIndex.page(apps: [], usage: [:], pinned: [], columns: 0, now: now).mostUsed, [])
    }

    func testGridColumnsFromWidth() {
        XCTAssertEqual(LauncherGrid.columns(forWidth: 0), 1)
        XCTAssertEqual(LauncherGrid.columns(forWidth: 104), 1)
        XCTAssertEqual(LauncherGrid.columns(forWidth: 232), 2)
        XCTAssertEqual(LauncherGrid.columns(forWidth: 920), 8)
    }

    func testPagingFillsEachPageThenContinuesAllApps() {
        func apps(_ n: Int, _ tag: String) -> [LauncherApp] { (0..<n).map { app("\(tag)\($0)", "\(tag)\($0)") } }
        let all = apps(40, "a")
        let page = LauncherPage(mostUsed: apps(8, "m"), recentlyInstalled: apps(8, "r"), all: all)
        let pages = LauncherPaging.paginate(page, columns: 8, pageHeight: 400, rowHeight: 100, headerHeight: 30)
        // Page 1: Most Used (130) + Recently Installed (130) + one row of All Apps (130) = 390 of 400.
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].map(\.kind), [.mostUsed, .recentlyInstalled, .allApps])
        XCTAssertEqual(pages[0][2].apps.count, 8)
        XCTAssertTrue(pages[0].allSatisfy(\.showsHeader))
        // Page 2 continues All Apps without a header: 4 rows of 8 fit in 400.
        XCTAssertEqual(pages[1].map(\.kind), [.allApps])
        XCTAssertEqual(pages[1][0].apps.count, 32)
        XCTAssertFalse(pages[1][0].showsHeader)
        XCTAssertEqual(pages.flatMap { $0 }.filter { $0.kind == .allApps }.flatMap(\.apps), all, "no app is lost or repeated")
    }

    func testPagingEdgeCases() {
        XCTAssertTrue(LauncherPaging.paginate(LauncherPage(mostUsed: [], recentlyInstalled: [], all: []),
                                              columns: 8, pageHeight: 400, rowHeight: 100, headerHeight: 30).isEmpty)
        // A page too short for even one row still shows one row per page rather than looping forever.
        let one = LauncherPage(mostUsed: [], recentlyInstalled: [], all: (0..<5).map { app("x\($0)", "x\($0)") })
        let pages = LauncherPaging.paginate(one, columns: 2, pageHeight: 10, rowHeight: 100, headerHeight: 30)
        XCTAssertEqual(pages.flatMap { $0 }.flatMap(\.apps).count, 5)
        XCTAssertEqual(pages.count, 3)
    }

    func testHiddenAppsLeaveTheGridAndCustomOrderWins() {
        let apps = [app("a", "Alpha"), app("b", "Beta"), app("c", "Gamma"), app("d", "Delta")]
        let page = LauncherAppIndex.page(apps: apps, usage: [:], pinned: [], presets: [], columns: 4, now: now,
                                         hidden: ["b"], order: ["d", "a"])
        XCTAssertEqual(page.all.map(\.bundleID), ["d", "a", "c"], "ordered first, hidden gone, the rest keep their order")
        XCTAssertFalse(page.mostUsed.contains { $0.bundleID == "b" })
    }

    func testMoveBeforeTargetAndToEnd() {
        XCTAssertEqual(LauncherOrdering.move(["a", "b", "c", "d"], moving: "d", before: "b"), ["a", "d", "b", "c"])
        XCTAssertEqual(LauncherOrdering.move(["a", "b", "c"], moving: "a", before: nil), ["b", "c", "a"])
        XCTAssertEqual(LauncherOrdering.move(["a", "b"], moving: "a", before: "a"), ["a", "b"])
        XCTAssertEqual(LauncherOrdering.move(["a", "b"], moving: "zz", before: "a"), ["a", "b"])
        XCTAssertEqual(LauncherOrdering.toggleHidden(["a"], "b"), ["a", "b"])
        XCTAssertEqual(LauncherOrdering.toggleHidden(["a", "b"], "a"), ["b"])
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
