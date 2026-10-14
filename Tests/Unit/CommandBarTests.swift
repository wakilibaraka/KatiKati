import XCTest
@testable import KatiKati

final class CommandBarTests: XCTestCase {

    private func app(_ id: String, _ name: String) -> LauncherApp {
        LauncherApp(bundleID: id, name: name, path: "/Applications/\(name).app", installedAt: Date(timeIntervalSince1970: 0))
    }
    private func running(_ id: String, _ name: String) -> RunningAppRef {
        RunningAppRef(bundleID: id, name: name, pid: 42, path: "/Applications/\(name).app")
    }

    func testMathRouteYieldsOnlyTheAnswer() {
        let rows = CommandBarResults.build(query: "=2+2", apps: [app("s", "Safari")], usage: [:], running: [])
        XCTAssertEqual(rows, [.answer(.math(expression: "2+2", value: "4"))])
    }

    func testWebRouteYieldsOnlyTheSearchAnswer() {
        let rows = CommandBarResults.build(query: "@swift news", apps: [], usage: [:], running: [])
        XCTAssertEqual(rows, [.answer(.web(query: "swift news"))])
    }

    func testRunningAppsRankBeforeAppMatches() {
        let rows = CommandBarResults.build(query: "safari",
                                           apps: [app("com.apple.Safari", "Safari")],
                                           usage: [:],
                                           running: [running("com.apple.Safari", "Safari")])
        XCTAssertEqual(rows, [.quit(running("com.apple.Safari", "Safari")),
                              .app(app("com.apple.Safari", "Safari"))])
    }

    func testNotRunningAppHasNoQuitRow() {
        let rows = CommandBarResults.build(query: "notes", apps: [app("n", "Notes")], usage: [:], running: [])
        XCTAssertEqual(rows, [.app(app("n", "Notes"))])
    }

    func testEmptyQueryYieldsNothing() {
        XCTAssertTrue(CommandBarResults.build(query: "", apps: [app("s", "Safari")], usage: [:], running: []).isEmpty)
        XCTAssertTrue(CommandBarResults.build(query: "   ", apps: [], usage: [:], running: []).isEmpty)
    }

    func testQuitRowsAreBestMatchFirst() {
        let rows = CommandBarResults.build(query: "term",
                                           apps: [],
                                           usage: [:],
                                           running: [running("a", "Terminal"), running("b", "iTerm")])
        // "Terminal" scores as a prefix match; "iTerm" only as a substring.
        XCTAssertEqual(rows.first, .quit(running("a", "Terminal")))
    }
}

final class SpotlightHandoffTests: XCTestCase {

    func testStepsAreOrderedAndNonEmpty() {
        let steps = SpotlightHandoff.steps()
        XCTAssertEqual(steps.first, .openKeyboard)
        XCTAssertEqual(steps.last, .testHere)
        XCTAssertEqual(steps.count, SpotlightHandoff.Step.allCases.count)
    }

    func testSettingsURLDeepLinksSystemSettings() {
        let url = URL(string: SpotlightHandoff.settingsURL)
        XCTAssertEqual(url?.scheme, "x-apple.systempreferences")
    }
}
