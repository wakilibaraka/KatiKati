import XCTest
@testable import KatiKati

final class LauncherPlusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func app(_ id: String, _ name: String, days: Double = 100, cat: String = "") -> LauncherApp {
        LauncherApp(bundleID: id, name: name, path: "/Applications/\(name).app",
                    installedAt: now.addingTimeInterval(-days * 86_400), category: cat)
    }

    // MARK: 13f pinned union + fixed pages

    func testSeparatePinnedUnionsDockAndLauncherPinsWithoutDuplicates() {
        let apps = [app("a", "A"), app("b", "B"), app("c", "C"), app("d", "D")]
        let page = LauncherAppIndex.page(apps: apps, usage: [:], pinned: ["c", "a", "gone"], presets: [], columns: 4, now: now,
                                         keptIDs: ["a", "b"], separatePinned: true)
        XCTAssertEqual(page.pinned.map(\.bundleID), ["a", "b", "c"])
        XCTAssertTrue(page.mostUsed.isEmpty, "pins must not repeat in Most Used")
        XCTAssertEqual(page.all.count, 4)
    }

    func testLegacyPageBehaviourUnchangedWhenNotSeparate() {
        let apps = [app("a", "A"), app("b", "B")]
        let page = LauncherAppIndex.page(apps: apps, usage: [:], pinned: ["b"], presets: [], columns: 4, now: now, keptIDs: ["a"])
        XCTAssertTrue(page.pinned.isEmpty)
        XCTAssertEqual(page.mostUsed.map(\.bundleID), ["b"])
    }

    func testPaginateRowsGivesEveryPageTheSameCapacity() {
        let apps = (0..<30).map { app("i\($0)", String(format: "App%02d", $0)) }
        let page = LauncherPage(mostUsed: Array(apps[0..<4]), recentlyInstalled: Array(apps[4..<6]), all: apps, pinned: [])
        let pages = LauncherPaging.paginateRows(page, columns: 4, rowsPerPage: 3)
        // Rows: mostUsed 1, recent 1, all 8 → 10 rows over 3-row pages = 4 pages.
        XCTAssertEqual(pages.count, 4)
        for p in pages.dropLast() {
            let rows = p.reduce(0) { $0 + ($1.apps.count + 3) / 4 }
            XCTAssertEqual(rows, 3)
        }
        XCTAssertEqual(pages[0].map(\.kind), [.mostUsed, .recentlyInstalled, .allApps])
        XCTAssertTrue(pages[0].allSatisfy(\.showsHeader))
        XCTAssertFalse(pages[1][0].showsHeader, "a continued block has no divider")
    }

    func testPaginateRowsPutsPinnedFirstAndCategoriesInsteadOfAll() {
        let a = app("a", "A", cat: "public.app-category.games"), b = app("b", "B", cat: "")
        let groups = LauncherSort.groups([a, b])
        let page = LauncherPage(mostUsed: [], recentlyInstalled: [], all: [a, b], pinned: [b], groups: groups)
        let kinds = LauncherPaging.paginateRows(page, columns: 4, rowsPerPage: 5).flatMap { $0 }.map(\.kind)
        XCTAssertEqual(kinds, [.pinned, .category("Games"), .category("Other")])
    }

    // MARK: 13g sort + categories

    func testCategoryTitles() {
        XCTAssertEqual(LauncherCategory.title(forUTI: "public.app-category.productivity"), "Productivity")
        XCTAssertEqual(LauncherCategory.title(forUTI: "public.app-category.graphics-design"), "Graphics Design")
        XCTAssertEqual(LauncherCategory.title(forUTI: ""), "Other")
    }

    func testSortModes() {
        let apps = [app("b", "Banana", days: 5), app("a", "apple", days: 50), app("c", "Cherry", days: 1)]
        let usage = ["a": LauncherUsage(launches: 9, lastLaunched: now), "c": LauncherUsage(launches: 2, lastLaunched: now)]
        func ids(_ m: LauncherSortMode, order: [String] = []) -> [String] {
            LauncherSort.apply(m, to: apps, usage: usage, order: order).map(\.bundleID)
        }
        XCTAssertEqual(ids(.name), ["a", "b", "c"])
        XCTAssertEqual(ids(.mostUsed), ["a", "c", "b"])
        XCTAssertEqual(ids(.recentlyAdded), ["c", "b", "a"])
        XCTAssertEqual(ids(.custom, order: ["c"]), ["c", "b", "a"])
    }

    func testGroupsAlphabeticalWithOtherLast() {
        let apps = [app("1", "A", cat: ""), app("2", "B", cat: "public.app-category.utilities"),
                    app("3", "C", cat: "public.app-category.developer-tools")]
        XCTAssertEqual(LauncherSort.groups(apps).map(\.title), ["Developer Tools", "Utilities", "Other"])
    }

    // MARK: 13g prefs

    func testPrefsClampAndRoundTrip() {
        var p = LauncherPrefs()
        p.blur = 7; p.columns = 2; p.rows = 99; p.iconScale = .nan
        let c = p.clamped()
        XCTAssertEqual(c.blur, 1); XCTAssertEqual(c.columns, 5); XCTAssertEqual(c.rows, 6); XCTAssertEqual(c.iconScale, 1)
        let d = UserDefaults(suiteName: "LauncherPlusTests.\(UUID())")!
        XCTAssertEqual(LauncherPrefs.load(d), LauncherPrefs())
        var q = LauncherPrefs(); q.sort = .category; q.columns = 6; q.groupByCategory = true
        q.save(d)
        XCTAssertEqual(LauncherPrefs.load(d), q)
    }

    // MARK: 13h presets

    func testHidePresetsAreFrozenAndReversible() {
        XCTAssertTrue(LauncherHidePresets.bundleIDs.contains("com.apple.Chess"))
        XCTAssertTrue(LauncherHidePresets.bundleIDs.contains("com.apple.podcasts"))
        XCTAssertTrue(LauncherHidePresets.bundleIDs.contains("com.apple.Magnifier"))
        XCTAssertTrue(LauncherHidePresets.bundleIDs.contains("com.apple.Automator"))
        XCTAssertEqual(Set(LauncherHidePresets.bundleIDs).count, LauncherHidePresets.bundleIDs.count)
        let hidden = LauncherHidePresets.hidingAll(["my.app", "com.apple.Chess"])
        XCTAssertEqual(hidden.filter { $0 == "com.apple.Chess" }.count, 1)
        XCTAssertEqual(LauncherHidePresets.restoringAll(hidden), ["my.app"])
    }

    // MARK: 13i quick actions

    func testQuickActionResolvesUrlsAndSearches() {
        XCTAssertEqual(LauncherQuickAction.resolve("https://apple.com/mac"), .open(URL(string: "https://apple.com/mac")!))
        XCTAssertEqual(LauncherQuickAction.resolve("apple.com"), .open(URL(string: "https://apple.com")!))
        if case .webSearch(let url)? = LauncherQuickAction.resolve("swift concurrency") {
            XCTAssertTrue(url.absoluteString.hasPrefix("https://duckduckgo.com/?q=swift"))
        } else { XCTFail("expected a web search") }
        if case .webSearch? = LauncherQuickAction.resolve("v1.2") {} else { XCTFail("a version number is not a URL") }
        XCTAssertNil(LauncherQuickAction.resolve("   "))
    }
}
