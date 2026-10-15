import XCTest

// Phase 12 (2026-10-15) — the Settings window's tab strip is built straight from
// `SettingsTab.allCases` (`SettingsWindowController.toolbarDefaultItemIdentifiers`), so this list is
// the window's contract: drop a case and a page disappears; duplicate a raw value and two toolbar
// items share one identifier, so only one of them can ever highlight. Nothing covered it before the
// Tools slice, which is why the About page could have been deleted without a single test noticing.
//
// `SettingsTab.swift` is dual-compiled, so this file needs no `import KatiKati` (same as
// `SettingsMetricsTests`).

final class SettingsTabTests: XCTestCase {
    func testTheStripIsTenTabsWithOneIdentityEach() {
        XCTAssertEqual(SettingsTab.allCases.count, 10, "ten pages is the window's shape")
        XCTAssertEqual(Set(SettingsTab.allCases.map(\.rawValue)).count, 10,
                       "two tabs sharing a raw value share one toolbar identifier")
        XCTAssertEqual(SettingsTab.allCases.first, .general)
        XCTAssertEqual(SettingsTab.allCases.last, .tools, "Tools takes the slot About left")
        XCTAssertEqual(SettingsTab(rawValue: "tiling"), .windowManagement,
                       "a stored toolbar identifier must keep resolving after a rename")
    }

    /// The rename that moved the tools off the launcher's page: the old identifier and the removed
    /// page must not resolve to anything, or a stale selection would point at the wrong page.
    func testTheOldLauncherAndAboutNamesAreGone() {
        XCTAssertNil(SettingsTab(rawValue: "launcherTools"))
        XCTAssertNil(SettingsTab(rawValue: "about"), "About is a card on General now, not a page")
        XCTAssertEqual(SettingsTab(rawValue: "launcher"), .launcher)
    }

    func testEveryTabCanBeDrawn() {
        for tab in SettingsTab.allCases {
            XCTAssertFalse(tab.title.isEmpty, "\(tab.rawValue) has no title, so its toolbar item is blank")
            XCTAssertFalse(tab.symbolName.isEmpty, "\(tab.rawValue) has no icon")
        }
    }
}
