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
    func testTheSidebarIsNineteenTabsWithOneIdentityEach() {
        XCTAssertEqual(SettingsTab.allCases.count, 19, "nineteen sidebar pages")
        XCTAssertEqual(Set(SettingsTab.allCases.map(\.rawValue)).count, 19,
                       "two tabs sharing a raw value share one toolbar identifier")
        XCTAssertEqual(SettingsTab.allCases.first, .general)
        XCTAssertEqual(SettingsTab.allCases.last, .advanced,
                       "the page visited once sits at the end; Tools is one before it")
        XCTAssertEqual(SettingsTab.allCases.dropLast().last, .info, "Info sits just before Advanced")
        // 2026-10-20 split: the toolbar identifier "tiling" now names the Tiling page itself;
        // Window Management moved to its own identifier.
        XCTAssertEqual(SettingsTab(rawValue: "tiling"), .tiling,
                       "a stored toolbar identifier must keep resolving after a split")
        XCTAssertEqual(SettingsTab(rawValue: "windowManagement"), .windowManagement)
        XCTAssertEqual(SettingsTab(rawValue: "controlCenter"), .controlCenter)
        XCTAssertEqual(SettingsTab(rawValue: "notifications"), .notifications,
                       "2026-10-22: notifications left Advanced for a page of their own")
    }

    /// The rename that moved the tools off the launcher's page: the old identifier and the removed
    /// page must not resolve to anything, or a stale selection would point at the wrong page.
    func testTheOldLauncherAndAboutNamesAreGone() {
        XCTAssertNil(SettingsTab(rawValue: "launcherTools"))
        XCTAssertNil(SettingsTab(rawValue: "about"), "About is a card on General now, not a page")
        XCTAssertEqual(SettingsTab(rawValue: "launcher"), .launcher)
    }

    func testEachSectionHasItsOwnHue() {
        let hues = SettingsTab.allCases.map { "\($0.hue.red),\($0.hue.green),\($0.hue.blue)" }
        XCTAssertEqual(Set(hues).count, hues.count, "two sections share a hue")
    }

    func testEveryTabCanBeDrawn() {
        for tab in SettingsTab.allCases {
            XCTAssertFalse(tab.title.isEmpty, "\(tab.rawValue) has no title, so its toolbar item is blank")
            XCTAssertFalse(tab.symbolName.isEmpty, "\(tab.rawValue) has no icon")
            let h = tab.hue
            XCTAssertTrue([h.red, h.green, h.blue].allSatisfy { (0...1).contains($0) }, "\(tab.rawValue) hue out of range")
        }
    }
}
