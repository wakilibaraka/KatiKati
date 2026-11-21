import XCTest

// Phase 12 (2026-10-15) — the Settings window's tab strip is built straight from
// `SettingsTab.allCases` (`SettingsWindowController.toolbarDefaultItemIdentifiers`), so this list is
// the window's contract: drop a case and a page disappears; duplicate a raw value and two toolbar
// items share one identifier, so only one of them can ever highlight.
//
// `SettingsTab.swift` is dual-compiled, so this file needs no `import KatiKati` (same as
// `SettingsMetricsTests`).

final class SettingsTabTests: XCTestCase {
    func testTheSidebarIsThirtyTabsWithOneIdentityEach() {
        XCTAssertEqual(SettingsTab.allCases.count, 30, "thirty sidebar pages")
        XCTAssertEqual(Set(SettingsTab.allCases.map(\.rawValue)).count, 30,
                       "two tabs sharing a raw value share one toolbar identifier")
        XCTAssertEqual(SettingsTab.allCases.first, .general)
        XCTAssertEqual(SettingsTab.allCases.last, .advanced,
                       "the page visited once sits at the end; Tools is one before it")
        XCTAssertEqual(SettingsTab.allCases.dropLast().last, .tools, "Tools sits just before Advanced")
        XCTAssertEqual(SettingsTab.allCases.dropLast(2).last, .clipboard, "Clipboard sits just above Tools")
        XCTAssertEqual(SettingsTab(rawValue: "clipboard"), .clipboard)
        // 2026-10-20 split: the toolbar identifier "tiling" now names the Tiling page itself;
        // Window Management moved to its own identifier.
        XCTAssertEqual(SettingsTab(rawValue: "tiling"), .tiling,
                       "a stored toolbar identifier must keep resolving after a split")
        XCTAssertEqual(SettingsTab(rawValue: "windowManagement"), .windowManagement)
        XCTAssertEqual(SettingsTab(rawValue: "controlCenter"), .controlCenter)
        XCTAssertEqual(SettingsTab(rawValue: "notifications"), .notifications)
        // DW-4: Wallpaper became a page of its own next to Appearance.
        XCTAssertEqual(SettingsTab(rawValue: "wallpaper"), .wallpaper)
        XCTAssertEqual(SettingsTab.allCases[SettingsTab.allCases.firstIndex(of: .appearance)! + 1], .wallpaper)
        // 2026-11 reorganization: Menu Bar, Drawer, Shelf, AI Tracking elevated to dedicated tabs
        XCTAssertEqual(SettingsTab(rawValue: "menuBar"), .menuBar)
        XCTAssertEqual(SettingsTab(rawValue: "drawer"), .drawer)
        XCTAssertEqual(SettingsTab(rawValue: "shelf"), .shelf)
        XCTAssertEqual(SettingsTab(rawValue: "drawerShelf"), .shelf)
        XCTAssertEqual(SettingsTab(rawValue: "aiTracking"), .aiTracking)
        XCTAssertEqual(SettingsTab(rawValue: "info"), .general, "Info maps back to General for compatibility")
        // 2026-11 input split: Shortcuts became Keyboard Shortcuts, and Keyboard, Mouse and
        // Quit & Close are pages of their own. The old identifier keeps opening the assignments page.
        XCTAssertEqual(SettingsTab(rawValue: "shortcuts"), .shortcuts,
                       "a stored identifier must keep resolving after the split")
        XCTAssertEqual(SettingsTab(rawValue: "keyboard"), .keyboard)
        // 2026-11 second split: the key visualizer left the crowded Keyboard page for its own.
        XCTAssertEqual(SettingsTab(rawValue: "keyVisualizer"), .keyVisualizer)
        XCTAssertEqual(SettingsTab(rawValue: "mouse"), .mouse)
        XCTAssertEqual(SettingsTab(rawValue: "mouseGestures"), .mouseGestures)
        XCTAssertEqual(SettingsTab(rawValue: "quitApps"), .quitApps)
        XCTAssertEqual(SettingsTab(rawValue: "quit"), .quitApps, "the short alias resolves to the page")
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

    /// The four input pages answer "keyboard, mouse, gestures, or hybrid?" in the sidebar; a rename
    /// that put two of them back under one name would make the split invisible.
    func testTheInputPagesNameTheirOwnDevice() {
        XCTAssertEqual(SettingsTab.shortcuts.title, "Keyboard Shortcuts")
        XCTAssertEqual(SettingsTab.keyboard.title, "Keyboard")
        XCTAssertEqual(SettingsTab.mouse.title, "Mouse")
        XCTAssertEqual(SettingsTab.mouseGestures.title, "Trackpad Gestures")
        XCTAssertEqual(SettingsTab.quitApps.title, "Quit & Close")
        XCTAssertEqual(SettingsTab.keyVisualizer.title, "Key Visualizer")
        for tab in [SettingsTab.shortcuts, .keyboard, .keyVisualizer, .mouse, .mouseGestures, .quitApps] {
            XCTAssertFalse(tab.subtitle.isEmpty, "\(tab.rawValue) needs a subtitle like every other page")
        }
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
