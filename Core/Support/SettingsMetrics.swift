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

    /// The window's default width; `SettingsWindowView.contentWidth` reads this as the initial size
    /// while allowing free window resize between `minWindowWidth` and the screen.
    static let windowWidth: CGFloat = 940
    /// The window is free-resizing (no max): a first launch opens at `idealWindowSize`, the user's
    /// own size is remembered after that (frame autosave).
    static let minWindowWidth: CGFloat = 640
    static let minWindowHeight: CGFloat = 440
    static let idealWindowWidth: CGFloat = 1080
    static let idealWindowHeight: CGFloat = 700
    static let sidebarWidth: CGFloat = 232
    static let sidebarCollapsedWidth: CGFloat = 64
    /// Minimum column width before a `SettingsRowPair` stacks vertically on narrow windows.
    static let pairStackThreshold: CGFloat = 720
    /// The width a card lays its rows out in at the default window width: the window minus the page
    /// margins and card padding.
    static let cardContentWidth: CGFloat = windowWidth - 2 * paneMargin - 2 * cardPadding
    /// One column of a `SettingsRowPair` at the default window width.
    static let halfRowWidth: CGFloat = cardContentWidth / 2

    /// Computes dynamic card content width for any live window width.
    static func cardContentWidth(forWindowWidth width: CGFloat) -> CGFloat {
        max(0, width - 2 * paneMargin - 2 * cardPadding)
    }

    /// Computes dynamic half-row width for any live window width.
    static func halfRowWidth(forWindowWidth width: CGFloat) -> CGFloat {
        cardContentWidth(forWindowWidth: width) / 2
    }
}
