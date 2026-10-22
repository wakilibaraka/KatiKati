import XCTest

// The rule that turns another app's File menu into the two or three rows a dock chip offers. The cases
// below are the real items the macOS Dock menu competes with: Finder's New Finder Window (⌘N) and New
// Tab (⌘T), the New Folder next to them (⇧⌘N) that must not appear, and items an app disables.

final class AppNewMenuPlanTests: XCTestCase {
    private func entry(_ title: String, key: String? = nil, modifiers: Int = 0, enabled: Bool = true) -> AppNewMenuPlan.Entry {
        AppNewMenuPlan.Entry(title: title, commandKey: key, modifiers: modifiers, isEnabled: enabled)
    }

    func testCommandNAndTAreNewActions() {
        XCTAssertTrue(AppNewMenuPlan.isNewAction(entry("New Finder Window", key: "n")))
        XCTAssertTrue(AppNewMenuPlan.isNewAction(entry("New Tab", key: "t")))
        XCTAssertTrue(AppNewMenuPlan.isNewAction(entry("Neues Fenster", key: "n")), "the shortcut rule does not read the language")
    }

    func testNewFolderAndOtherModifiersAreNot() {
        XCTAssertFalse(AppNewMenuPlan.isNewAction(entry("New Folder", key: "n", modifiers: 1)), "⇧⌘N is New Folder")
        XCTAssertFalse(AppNewMenuPlan.isNewAction(entry("New Window", key: "n", modifiers: 2)), "⌥⌘N is a different action")
        XCTAssertFalse(AppNewMenuPlan.isNewAction(entry("Open", key: "o")))
    }

    func testDisabledEmptyAndDeduped() {
        XCTAssertFalse(AppNewMenuPlan.isNewAction(entry("New Window", key: "n", enabled: false)))
        XCTAssertFalse(AppNewMenuPlan.isNewAction(entry("", key: "n")))
        let rows = AppNewMenuPlan.items(from: [entry("New Window", key: "n"),
                                               entry("New Window", key: "n"),
                                               entry("New Tab", key: "t")])
        XCTAssertEqual(rows.map(\.title), ["New Window", "New Tab"])
    }

    func testTheAppOrderIsKeptAndTheListIsCapped() {
        let rows = AppNewMenuPlan.items(from: [
            entry("New Tab", key: "t"),
            entry("New Window", key: "n"),
            entry("New Viewer", key: nil),
            entry("New Document", key: nil),
            entry("Open", key: "o"),
        ])
        XCTAssertEqual(rows.map(\.title), ["New Tab", "New Window", "New Viewer"])
    }
}
