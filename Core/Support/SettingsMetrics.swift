import CoreGraphics

// Phase 12 (2026-10-15) — SettingsMetrics: the Settings window's one layout grid.
//
// Before this existed every page placed its content wherever its own helper said: measured live on
// 2026-10-15 the left inset ran from 20 pt (Window Management) to 108 pt (General/Notch/Advanced/
// About), and the gap between two sections ran from 0 to 100 pt on the same page. Four of the ten
// pages also grew past the 1074 pt window. Pages, cards and rows all measure themselves from here
// now, and no page may invent a margin of its own (`Docs/SETTINGS.md`, rule 1).
//
// Dual-compiled: pure numbers, no AppKit/SwiftUI, so the unit tests can pin the grid's hierarchy.

enum SettingsMetrics {
    /// Window edge → a page's content, cards included.
    static let paneMargin: CGFloat = 28
    /// Card → card on the same page.
    static let sectionSpacing: CGFloat = 20
    /// A card's header → its first row.
    static let cardHeaderSpacing: CGFloat = 10
    /// Inside a card, on every side.
    static let cardPadding: CGFloat = 14
    static let cardCornerRadius: CGFloat = 12
    static let cardFillOpacity: Double = 0.04
    /// A row's own height above and below its content. Measured live (2026-10-15): at 11 the ten
    /// pages ran ~13 % taller than the window could show, with the padding reading as dead space
    /// between rows that are already separated by a divider; 8 keeps a 25 pt control legible at 41 pt
    /// rows and pulls the long pages back inside the window.
    static let rowVerticalPadding: CGFloat = 8
    /// A checklist cell inside a `SettingsGrid`: tighter than a settings row on purpose. Measured
    /// live (2026-10-15): the window's checklists were 17–22 pt rows, and eighteen of them in one
    /// column were 306 pt of list with 2/3 of the card empty — the grid halves that, but only while
    /// a cell stays near the height of the checkbox it carries.
    static let gridRowVerticalPadding: CGFloat = 4
    /// A row's label → the note that explains it.
    static let rowNoteSpacing: CGFloat = 3
    /// One label column for the rows whose control fills the rest (sliders) or lines up in a block
    /// (segmented) — decided by control type, never by page (rule 3).
    static let labelColumnWidth: CGFloat = 150
    /// The trailing value column of a slider row ("50%", "0.40 s").
    static let valueColumnWidth: CGFloat = 52
    static let controlSpacing: CGFloat = 10
    /// Keeps a trailing control off its label at the window's narrowest.
    static let rowMinimumLabelGap: CGFloat = 12
    static let dividerOpacity: Double = 0.5

    /// The window's own width; `SettingsWindowView.contentWidth` reads this (rule 10: the window is
    /// a fixed 900 pt, so a page — and a pair's half — can be arithmetic instead of a guess).
    static let windowWidth: CGFloat = 900
    /// The width a card lays its rows out in: the window minus the page margins and card padding.
    static let cardContentWidth: CGFloat = windowWidth - 2 * paneMargin - 2 * cardPadding
    /// One column of a `SettingsRowPair`. A grid sized its columns by their own content, so the half
    /// holding the wider control took the width and squeezed the other one's control (measured live
    /// 2026-10-15: the right half's Record button rendered as “…” at 20 pt); a half is exactly half.
    static let halfRowWidth: CGFloat = cardContentWidth / 2
}
