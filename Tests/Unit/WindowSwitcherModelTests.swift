import XCTest
@testable import KatiKati

final class WindowSwitcherModelTests: XCTestCase {
    func testMRUMovesActiveToFrontAndDropsDeadWindows() {
        let mru = WindowSwitcherModel.updatedMRU(["a", "b", "c"], active: "c", alive: ["a", "c", "d"])
        XCTAssertEqual(mru, ["c", "a"])
    }

    func testMRUIgnoresActiveThatIsNotAlive() {
        XCTAssertEqual(WindowSwitcherModel.updatedMRU(["a"], active: "x", alive: ["a"]), ["a"])
        XCTAssertEqual(WindowSwitcherModel.updatedMRU(["a"], active: nil, alive: ["a"]), ["a"])
    }

    func testMRUIsCapped() {
        let ids = (0..<100).map(String.init)
        XCTAssertEqual(WindowSwitcherModel.updatedMRU([], active: "0", alive: Set(ids)).count, 1)
        XCTAssertEqual(WindowSwitcherModel.updatedMRU(ids, active: "5", alive: Set(ids)).count, WindowSwitcherModel.mruLimit)
    }

    func testOrderPutsKnownFirstByMRUThenUnknownInIncomingOrder() {
        let ordered = WindowSwitcherModel.order(candidates: ["x", "b", "y", "a"], mru: ["a", "b"])
        XCTAssertEqual(ordered, ["a", "b", "x", "y"])
    }

    func testInitialSelectionPicksPreviousWindow() {
        XCTAssertEqual(WindowSwitcherModel.initialSelection(count: 4, reverse: false), 1)
        XCTAssertEqual(WindowSwitcherModel.initialSelection(count: 4, reverse: true), 3)
        XCTAssertEqual(WindowSwitcherModel.initialSelection(count: 1, reverse: false), 0)
        XCTAssertEqual(WindowSwitcherModel.initialSelection(count: 0, reverse: true), 0)
    }

    func testStepWraps() {
        XCTAssertEqual(WindowSwitcherModel.step(selection: 3, count: 4, reverse: false), 0)
        XCTAssertEqual(WindowSwitcherModel.step(selection: 0, count: 4, reverse: true), 3)
        XCTAssertEqual(WindowSwitcherModel.step(selection: 0, count: 0, reverse: false), 0)
    }

    func testSearchMatchesTitleAndAppWordsInAnyOrder() {
        XCTAssertTrue(WindowSwitcherModel.matches(query: "", title: "x", appName: "y"))
        XCTAssertTrue(WindowSwitcherModel.matches(query: "SAF doc", title: "Docs", appName: "Safari"))
        XCTAssertFalse(WindowSwitcherModel.matches(query: "safari mail", title: "Docs", appName: "Safari"))
    }

    func testColumnsBalanceRows() {
        XCTAssertEqual(WindowSwitcherModel.columns(count: 3), 3)
        XCTAssertEqual(WindowSwitcherModel.columns(count: 6), 6)
        XCTAssertEqual(WindowSwitcherModel.columns(count: 7), 4)   // 2 rows
        XCTAssertEqual(WindowSwitcherModel.columns(count: 13), 5)  // 3 rows
        XCTAssertEqual(WindowSwitcherModel.columns(count: 0), 1)
    }

    func testNumberedWindowSwitcherBadgesAndDigits() {
        XCTAssertEqual(NumberedWindowSwitcherModel.digitBadge(for: 0), "1")
        XCTAssertEqual(NumberedWindowSwitcherModel.digitBadge(for: 8), "9")
        XCTAssertNil(NumberedWindowSwitcherModel.digitBadge(for: 9))
        XCTAssertNil(NumberedWindowSwitcherModel.digitBadge(for: -1))

        XCTAssertEqual(NumberedWindowSwitcherModel.index(forDigit: 1, count: 5), 0)
        XCTAssertEqual(NumberedWindowSwitcherModel.index(forDigit: 5, count: 5), 4)
        XCTAssertNil(NumberedWindowSwitcherModel.index(forDigit: 6, count: 5))
        XCTAssertNil(NumberedWindowSwitcherModel.index(forDigit: 0, count: 5))

        XCTAssertEqual(NumberedWindowSwitcherModel.digit(fromKeyCode: 18), 1)
        XCTAssertEqual(NumberedWindowSwitcherModel.digit(fromKeyCode: 25), 9)
        XCTAssertNil(NumberedWindowSwitcherModel.digit(fromKeyCode: 49)) // Space
    }
}

final class WindowSwitcherStyleModelTests: XCTestCase {
    func testStyleConfigRoundTripsAndNormalizes() throws {
        let accent = WindowSwitcherAccentColor(red: 2, green: -1, blue: 0.4, alpha: 2)
        let config = WindowSwitcherStyleConfig(iconSize: 200, spacing: -4, rows: 12, columns: -2,
                                               opacity: 3, accentColor: accent, animationSpeed: 0.01,
                                               keepOpenOnRelease: true)
        let normalized = config.normalized()
        XCTAssertEqual(normalized.iconSize, 128)
        XCTAssertEqual(normalized.spacing, 0)
        XCTAssertEqual(normalized.rows, 8)
        XCTAssertEqual(normalized.columns, 0)
        XCTAssertEqual(normalized.opacity, 1)
        XCTAssertEqual(normalized.animationSpeed, 0.1)
        XCTAssertEqual(normalized.accentColor, WindowSwitcherAccentColor(red: 1, green: 0, blue: 0.4, alpha: 1))
        XCTAssertTrue(normalized.keepOpenOnRelease)

        let decoded = try JSONDecoder().decode(WindowSwitcherStyleConfig.self,
                                               from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded, config)
        XCTAssertEqual(WindowSwitcherStyle.allCases.count, 6)
        XCTAssertTrue(WindowSwitcherStyle.thumbnail.usesLiveThumbnails)
        XCTAssertFalse(WindowSwitcherStyle.list.usesLiveThumbnails)
    }

    func testPredictiveRankerBlendsRecencyAndFrequencyAndResets() {
        let old = WindowPredictiveRanker.key(bundleID: "com.example.old", title: "Old")
        let recent = WindowPredictiveRanker.key(bundleID: "com.example.recent", title: "Recent")
        var ranker = WindowPredictiveRanker(halfLife: 1_800)
        for _ in 0..<10 { ranker.record(old, at: 0) }
        ranker.record(recent, at: 100)

        XCTAssertEqual(ranker.order(candidates: [old, recent], at: 100), [recent, old])
        XCTAssertEqual(ranker.score(bundleID: "com.example.recent", title: "Recent", at: 100),
                       ranker.score(for: recent, at: 100))
        XCTAssertGreaterThan(ranker.score(for: recent, at: 100), ranker.score(for: recent, at: 1_900))
        XCTAssertEqual(ranker.score(for: "missing", at: 100), 0)

        ranker.resetLearnedData()
        XCTAssertEqual(ranker.score(for: recent, at: 100), 0)
    }

    func testFilterPolicyHonoursDisplaySpaceAndVisibilityToggles() {
        let displayA = "display-a"
        let displayB = "display-b"
        func window(_ id: String,
                    bundle: String = "com.example.app",
                    display: String?,
                    status: WindowStatus) -> WindowRecord {
            WindowRecord(id: WindowID(rawValue: id), appID: AppID(rawValue: "app"), pid: 1,
                         bundleIdentifier: bundle, title: id, bounds: .zero, status: status,
                         displayUUID: display)
        }

        let activeA = window("a", display: displayA, status: .active)
        let activeB = window("b", display: displayB, status: .inactive)
        let unknownDisplay = window("c", display: nil, status: .inactive)
        let minimized = window("d", display: displayA, status: .minimized)
        let hidden = window("e", display: displayA, status: .hidden)
        let ignored = window("f", bundle: "com.example.ignore", display: displayA, status: .active)

        var policy = WindowFilterPolicy(currentDisplayOnly: true, ignoredBundleIDs: [" com.example.ignore "])
        let context = WindowFilterContext(currentDisplayUUID: displayA, currentSpaceWindowIDs: ["a", "c"])
        XCTAssertTrue(policy.allows(activeA, context: context))
        XCTAssertFalse(policy.allows(activeB, context: context))
        XCTAssertTrue(policy.allows(unknownDisplay, context: context), "unknown display is not evidence of another display")
        XCTAssertFalse(policy.allows(ignored, context: context))

        policy.showMinimized = false
        policy.showHidden = false
        XCTAssertFalse(policy.allows(minimized, context: context))
        XCTAssertFalse(policy.allows(hidden, context: context))

        policy.currentSpaceOnly = true
        let spaceContext = WindowFilterContext(currentDisplayUUID: displayA, currentSpaceWindowIDs: ["a"])
        XCTAssertTrue(policy.allows(activeA, context: spaceContext))
        XCTAssertFalse(policy.allows(unknownDisplay, context: spaceContext))
        XCTAssertTrue(policy.allows(activeA, context: WindowFilterContext(currentDisplayUUID: displayA)),
                      "nil Space membership means unknown, so the filter is a no-op")
        XCTAssertEqual(policy.normalized().ignoredBundleIDs, ["com.example.ignore"])
    }
}
