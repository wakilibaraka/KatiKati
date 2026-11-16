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
