import XCTest
@testable import KatiKati

final class TerminalSupportTests: XCTestCase {
    func testPanelSizeBoundsClampAndPersist() {
        let tooSmall = TerminalPanelSizeBounds.clamped(CGSize(width: 100, height: 50))
        XCTAssertEqual(tooSmall.width, TerminalPanelSizeBounds.minWidth)
        XCTAssertEqual(tooSmall.height, TerminalPanelSizeBounds.minHeight)

        let tooLarge = TerminalPanelSizeBounds.clamped(CGSize(width: 2400, height: 1500))
        XCTAssertEqual(tooLarge.width, TerminalPanelSizeBounds.maxWidth)
        XCTAssertEqual(tooLarge.height, TerminalPanelSizeBounds.maxHeight)

        let suite = "terminal-size-bounds-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        XCTAssertEqual(TerminalPanelSizeBounds.load(defaults), TerminalPanelSizeBounds.defaultSize)
        TerminalPanelSizeBounds.save(CGSize(width: 780, height: 520), defaults: defaults)
        XCTAssertEqual(TerminalPanelSizeBounds.load(defaults), CGSize(width: 780, height: 520))
    }

    func testThemePresetsExposeDistinctPalettes() {
        XCTAssertEqual(TerminalThemePreset.allCases.count, 4)
        let backgrounds = Set(TerminalThemePreset.allCases.map { "\($0.backgroundRGB.r),\($0.backgroundRGB.g),\($0.backgroundRGB.b)" })
        XCTAssertEqual(backgrounds.count, 4)
        XCTAssertNotEqual(TerminalThemePreset.paperLight.foregroundRGB, TerminalThemePreset.katikatiDark.foregroundRGB)
    }

    func testShellEscapedCDCommandHandlesSpacesQuotesAndRejectsControlChars() {
        XCTAssertEqual(
            TerminalSnippet.shellEscapedCDCommand(for: "/Users/baraka/My Folder/It's Here"),
            "cd '/Users/baraka/My Folder/It'\\''s Here'\n"
        )
        XCTAssertNil(TerminalSnippet.shellEscapedCDCommand(for: ""))
        XCTAssertNil(TerminalSnippet.shellEscapedCDCommand(for: "/tmp/evil\nrm -rf /"))
        XCTAssertNil(TerminalSnippet.shellEscapedCDCommand(for: "/tmp/null\0byte"))
    }

    func testBufferSearchFindsCaseInsensitiveMatchesUpToLimit() {
        let buffer = """
        line one OK
        Error: failed to open socket
        all clear
        error: retry timed out
        ERROR: final failure
        """
        let empty = TerminalBufferSearch.matches(in: buffer, query: "   ")
        XCTAssertTrue(empty.isEmpty)

        let all = TerminalBufferSearch.matches(in: buffer, query: "error")
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.map(\.lineIndex), [1, 3, 4])

        let limited = TerminalBufferSearch.matches(in: buffer, query: "error", limit: 2)
        XCTAssertEqual(limited.count, 2)
        XCTAssertEqual(limited.map(\.lineIndex), [1, 3])
    }
}
