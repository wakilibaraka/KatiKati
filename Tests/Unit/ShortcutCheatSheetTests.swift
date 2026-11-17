import XCTest
@testable import KatiKati

final class ShortcutCheatSheetTests: XCTestCase {
    func testBuildsGroupedCategoriesAndFiltersByQueryAndModifiers() {
        let entries = [
            MenuSearchEntry(path: ["File", "New Window"], commandKey: "n", modifiers: 0, isEnabled: true),
            MenuSearchEntry(path: ["File", "Export", "PDF…"], commandKey: "e", modifiers: 1, isEnabled: true),
            MenuSearchEntry(path: ["Edit", "No Shortcut"], commandKey: nil, modifiers: 0, isEnabled: true),
            MenuSearchEntry(path: ["Apple", "About"], commandKey: "i", modifiers: 0, isEnabled: true)
        ]

        let categories = ShortcutCheatSheetBuilder.build(entries: entries)
        XCTAssertEqual(categories.map(\.title), ["File"])
        XCTAssertEqual(categories.first?.items.count, 2)
        XCTAssertEqual(categories.first?.items.last?.subtitle, "Export")
        XCTAssertEqual(categories.first?.items.last?.shortcut, "⇧⌘E")

        let shiftOnly = ShortcutCheatSheetBuilder.filter(
            categories: categories,
            query: "",
            requiredModifiers: [.shift]
        )
        XCTAssertEqual(shiftOnly.first?.items.map(\.title), ["Export", "PDF…"].last.map { [$0] })

        let md = ShortcutCheatSheetBuilder.exportMarkdown(appName: "Finder", categories: categories)
        XCTAssertTrue(md.contains("# Finder Keyboard Shortcuts"))
        XCTAssertTrue(md.contains("| Export › PDF… | `⇧⌘E` |"))
    }
}
