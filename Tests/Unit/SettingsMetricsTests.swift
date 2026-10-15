import XCTest

/// Phase 12 — the Settings grid is one set of numbers shared by every page, so its hierarchy is the
/// thing worth pinning: a section must read as a bigger break than a row, and a card must still fit
/// a label plus a control at the window's real width.
final class SettingsMetricsTests: XCTestCase {
    /// The settings window's content width (`SettingsWindowView.contentWidth`), duplicated here
    /// because the view file is app-target-only.
    private let contentWidth: CGFloat = 900

    func testSectionReadsAsABiggerBreakThanARow() {
        XCTAssertGreaterThan(SettingsMetrics.sectionSpacing, SettingsMetrics.rowVerticalPadding,
                             "a section gap smaller than a row's padding stops reading as a group")
        XCTAssertGreaterThan(SettingsMetrics.cardHeaderSpacing, SettingsMetrics.rowNoteSpacing,
                             "a header must sit further from its rows than a note sits from its row")
        XCTAssertGreaterThan(SettingsMetrics.rowMinimumLabelGap, 0,
                             "a trailing control needs a gap from its label")
        XCTAssertGreaterThan(SettingsMetrics.controlSpacing, 0)
    }

    /// A pair's two halves are equal (`Docs/SETTINGS.md` rules 5 and 10): the window is a fixed
    /// width, and both halves must be the same number of points or one of them squeezes its
    /// trailing control (measured live 2026-10-15: a Record button at 20 pt reading “…”).
    func testAPairsHalvesSplitTheCardEvenly() {
        XCTAssertEqual(SettingsMetrics.halfRowWidth * 2, SettingsMetrics.cardContentWidth,
                       "two halves must fill one card, no more and no less")
        XCTAssertEqual(SettingsMetrics.cardContentWidth,
                       SettingsMetrics.windowWidth - 2 * SettingsMetrics.paneMargin - 2 * SettingsMetrics.cardPadding,
                       "a card's content is the window minus the page margin and the card's padding")
    }

    /// A checklist cell is tighter than a settings row (`Docs/SETTINGS.md` rule 5): the grid only
    /// saves a page height while a cell stays near the checkbox it carries.
    func testAChecklistCellIsTighterThanARow() {
        XCTAssertGreaterThan(SettingsMetrics.gridRowVerticalPadding, 0,
                             "a cell with no padding reads as a wrapped column")
        XCTAssertLessThan(SettingsMetrics.gridRowVerticalPadding, SettingsMetrics.rowVerticalPadding)
    }

    func testCardSitsInsideThePageAndLeavesRoomForAControl() {
        XCTAssertLessThan(SettingsMetrics.cardPadding, SettingsMetrics.paneMargin,
                          "a card padded wider than the page margin starts to read as its own page")
        XCTAssertGreaterThan(SettingsMetrics.cardFillOpacity, 0)
        XCTAssertLessThan(SettingsMetrics.cardFillOpacity, 0.2)
        XCTAssertGreaterThan(SettingsMetrics.dividerOpacity, 0)
        XCTAssertLessThan(SettingsMetrics.dividerOpacity, 1)

        let usable = contentWidth
            - 2 * SettingsMetrics.paneMargin
            - 2 * SettingsMetrics.cardPadding
        XCTAssertGreaterThan(usable, SettingsMetrics.labelColumnWidth + SettingsMetrics.valueColumnWidth)
    }
}
