import XCTest

// Port plan #3: ranking and shortcut glyphs for the command bar's `m ` mode, plus its routing. The
// fixture is a trimmed Safari-like menu bar: a File menu with a nested Export, an Edit menu with a
// disabled item, and the Apple menu that must never appear.

final class MenuSearchTests: XCTestCase {
    private func entry(_ path: [String], key: String? = nil, modifiers: Int = 0, enabled: Bool = true) -> MenuSearchEntry {
        MenuSearchEntry(path: path, commandKey: key, modifiers: modifiers, isEnabled: enabled)
    }

    private var fixture: [MenuSearchEntry] {
        [
            entry(["Apple", "About This Mac"]),
            entry(["File", "New Window"], key: "n"),
            entry(["File", "New Tab"], key: "t"),
            entry(["File", "Export as PDF…"], key: "e", modifiers: 1),
            entry(["File", "Export", "Export as PNG"]),
            entry(["Edit", "Undo"], key: "z", enabled: false),
            entry(["Edit", "Paste and Match Style"], key: "v", modifiers: 3),
            entry(["View", "Show Tab Bar"], key: "t", modifiers: 1),
        ]
    }

    func testGlyphsFollowMacOSOrderAndModifierBits() {
        XCTAssertEqual(MenuSearch.shortcutGlyphs(commandKey: "n", modifiers: 0), "⌘N")
        XCTAssertEqual(MenuSearch.shortcutGlyphs(commandKey: "t", modifiers: 1), "⇧⌘T")
        XCTAssertEqual(MenuSearch.shortcutGlyphs(commandKey: "v", modifiers: 3), "⌥⇧⌘V")
        XCTAssertEqual(MenuSearch.shortcutGlyphs(commandKey: "q", modifiers: 4 | 2 | 1), "⌃⌥⇧⌘Q")
    }

    func testGlyphsDropCommandWhenTheNoCommandBitIsSet() {
        XCTAssertEqual(MenuSearch.shortcutGlyphs(commandKey: "f", modifiers: 8), "F")
        XCTAssertEqual(MenuSearch.shortcutGlyphs(commandKey: "f", modifiers: 8 | 4), "⌃F")
    }

    func testNoKeyEquivalentMeansNoGlyphs() {
        XCTAssertNil(MenuSearch.shortcutGlyphs(commandKey: nil, modifiers: 0))
        XCTAssertNil(MenuSearch.shortcutGlyphs(commandKey: "", modifiers: 0))
        XCTAssertNil(MenuSearch.shortcutGlyphs(commandKey: "  ", modifiers: 1))
    }

    func testAppleMenuAndBlankTitlesNeverAppear() {
        let ranked = MenuSearch.rank("", in: fixture + [entry(["File", ""]), entry(["Apple", "Restart…"])])
        XCTAssertFalse(ranked.contains { $0.path.first == "Apple" })
        XCTAssertFalse(ranked.contains { $0.title.isEmpty })
    }

    func testTitleMatchBeatsPathOnlyMatch() {
        let ranked = MenuSearch.rank("export", in: fixture)
        XCTAssertEqual(Set(ranked.prefix(2).map(\.title)), ["Export as PDF…", "Export as PNG"],
                       "titles that start with the query come before anything matched only on its path")
    }

    func testPathOnlyMatchIsStillFound() {
        let ranked = MenuSearch.rank("edit", in: fixture)
        XCTAssertEqual(ranked.map(\.title), ["Paste and Match Style", "Undo"],
                       "no title says \"edit\"; both items match on the Edit menu in their path, enabled first")
    }

    func testDisabledItemsSinkBelowEnabledOnes() {
        let items = [entry(["Edit", "Undo Typing"], key: "z", enabled: false), entry(["Edit", "Undo Move"], key: "z")]
        XCTAssertEqual(MenuSearch.rank("undo", in: items).map(\.title), ["Undo Move", "Undo Typing"])
    }

    func testTiesKeepTheAppsOwnMenuOrder() {
        let items = [entry(["File", "Open A"]), entry(["File", "Open B"]), entry(["Edit", "Open C"])]
        XCTAssertEqual(MenuSearch.rank("open", in: items).map(\.title), ["Open A", "Open B", "Open C"])
    }

    func testEmptyQueryListsMenusInOrderEnabledFirst() {
        let ranked = MenuSearch.rank("", in: fixture)
        XCTAssertEqual(ranked.first?.title, "New Window")
        XCTAssertEqual(ranked.last?.title, "Undo", "the one disabled item is last")
    }

    func testNothingMatchesNothing() {
        XCTAssertTrue(MenuSearch.rank("zzzzzz", in: fixture).isEmpty)
    }

    func testResultLimitIsHonoured() {
        let many = (0..<100).map { entry(["File", "Item \($0)"]) }
        XCTAssertEqual(MenuSearch.rank("item", in: many).count, MenuSearch.resultLimit)
        XCTAssertEqual(MenuSearch.rank("item", in: many, limit: 5).count, 5)
    }

    func testBreadcrumbAndIdentity() {
        let e = entry(["File", "Export", "Export as PNG"])
        XCTAssertEqual(e.breadcrumb, "File › Export")
        XCTAssertEqual(e.title, "Export as PNG")
        XCTAssertNotEqual(e.id, entry(["File", "Export as PNG"]).id)
    }

    // MARK: routing

    func testBothKeywordsOpenMenuMode() {
        XCTAssertEqual(CommandKeyword.parse("m export"), .mode(.menu, "export"))
        XCTAssertEqual(CommandKeyword.parse("menu new tab"), .mode(.menu, "new tab"))
        XCTAssertEqual(CommandKeyword.parse("M Save"), .mode(.menu, "Save"))
    }

    func testBareMIsNotAMacroOrMode() {
        XCTAssertNil(CommandKeyword.parse("m"), "a bare word needs a space to become a mode")
    }

    func testMenuModeBuildsMenuRows() {
        let rows = CommandBarResults.build(query: "m new", apps: [], usage: [:], running: [], menuItems: fixture)
        guard case .menuItem(let first)? = rows.first else { return XCTFail("expected a menu row, got \(rows)") }
        XCTAssertTrue(first.title.hasPrefix("New "))
        XCTAssertTrue(rows.allSatisfy { if case .menuItem = $0 { return true } else { return false } })
    }

    func testMenuModeWithoutAnySnapshotIsEmpty() {
        XCTAssertTrue(CommandBarResults.build(query: "m new", apps: [], usage: [:], running: []).isEmpty)
    }

    func testMenuRowIDsAreStable() {
        let e = entry(["File", "New Window"], key: "n")
        XCTAssertEqual(CommandBarResult.menuItem(e).id, "menu:\(e.id)")
    }
}
