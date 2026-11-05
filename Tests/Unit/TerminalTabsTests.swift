import XCTest
@testable import KatiKati

final class TerminalTabsTests: XCTestCase {
    func testStartsWithOneSelectedTab() {
        let tabs = TerminalTabs()
        XCTAssertEqual(tabs.tabs.count, 1)
        XCTAssertEqual(tabs.selectedID, tabs.tabs[0].id)
    }

    func testAddInsertsAfterSelectedSelectsAndInheritsDirectory() {
        var tabs = TerminalTabs()
        let first = tabs.tabs[0].id
        tabs.setDirectory("/Users/me/code", for: first)
        let second = tabs.add()
        tabs.select(first)
        let third = tabs.add()
        XCTAssertEqual(tabs.tabs.map(\.id), [first, third!.id, second!.id])
        XCTAssertEqual(tabs.selectedID, third!.id)
        XCTAssertEqual(third?.directory, "/Users/me/code")
    }

    func testAddStopsAtTheCap() {
        var tabs = TerminalTabs()
        for _ in 1..<TerminalTabs.maxTabs { XCTAssertNotNil(tabs.add()) }
        XCTAssertFalse(tabs.canAdd)
        let selected = tabs.selectedID
        XCTAssertNil(tabs.add())
        XCTAssertEqual(tabs.tabs.count, TerminalTabs.maxTabs)
        XCTAssertEqual(tabs.selectedID, selected)
    }

    func testCloseSelectedPicksTheNeighbourAndLastFallsBack() {
        var tabs = TerminalTabs()
        let a = tabs.tabs[0].id
        let b = tabs.add()!.id
        let c = tabs.add()!.id
        tabs.select(b)
        XCTAssertTrue(tabs.close(b))
        XCTAssertEqual(tabs.selectedID, c)
        XCTAssertTrue(tabs.close(c))
        XCTAssertEqual(tabs.selectedID, a)
    }

    func testCloseUnselectedKeepsSelectionAndOnlyTabCannotClose() {
        var tabs = TerminalTabs()
        let a = tabs.tabs[0].id
        XCTAssertFalse(tabs.close(a))
        let b = tabs.add()!.id
        XCTAssertTrue(tabs.close(a))
        XCTAssertEqual(tabs.selectedID, b)
        XCTAssertFalse(tabs.close(UUID()))
    }

    func testCycleWrapsBothWays() {
        var tabs = TerminalTabs()
        let a = tabs.tabs[0].id
        let b = tabs.add()!.id
        tabs.cycle(1)
        XCTAssertEqual(tabs.selectedID, a)
        tabs.cycle(-1)
        XCTAssertEqual(tabs.selectedID, b)
    }

    func testDisplayTitlePrefersTitleThenDirectoryThenShell() {
        var tabs = TerminalTabs()
        let id = tabs.tabs[0].id
        XCTAssertEqual(tabs.selected.displayTitle, "Shell")
        tabs.setDirectory("/Users/me/code/KatiKati", for: id)
        XCTAssertEqual(tabs.selected.displayTitle, "KatiKati")
        tabs.setTitle("  vim  ", for: id)
        XCTAssertEqual(tabs.selected.displayTitle, "vim")
    }

    func testSelectUnknownIDIsIgnored() {
        var tabs = TerminalTabs()
        let id = tabs.selectedID
        tabs.select(UUID())
        XCTAssertEqual(tabs.selectedID, id)
    }
}
