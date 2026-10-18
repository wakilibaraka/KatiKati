import XCTest

// The breakpoints of the free-resizing Settings window. `SettingsLayoutClass.swift` is dual-compiled.

final class SettingsLayoutClassTests: XCTestCase {
    private func resolve(_ w: CGFloat, _ h: CGFloat, icons: Bool = false,
                         _ pref: SettingsStagePreference = .top) -> SettingsLayoutClass {
        SettingsLayoutClass.resolve(windowWidth: w, windowHeight: h, sidebarForcedIcons: icons, stagePreference: pref)
    }

    func testTheDefaultSizeShowsEverything() {
        let c = resolve(SettingsMetrics.idealWindowWidth, SettingsMetrics.idealWindowHeight)
        XCTAssertEqual(c.sidebar, .full)
        XCTAssertEqual(c.stage, .top)
        XCTAssertGreaterThanOrEqual(c.columns, 2)
    }

    func testTheSidebarCollapsesBelowItsBreakpointOrWhenForced() {
        XCTAssertEqual(resolve(859, 700).sidebar, .icons)
        XCTAssertEqual(resolve(860, 700).sidebar, .full)
        XCTAssertEqual(resolve(1400, 700, icons: true).sidebar, .icons)
    }

    func testTheStageHidesOnShortOrNarrowWindows() {
        XCTAssertEqual(resolve(1000, 479).stage, .hidden)
        XCTAssertEqual(resolve(1000, 480).stage, .top)
        XCTAssertEqual(resolve(719, 700, .side).stage, .hidden)
        XCTAssertEqual(resolve(720, 700, .side).stage, .side)
        XCTAssertEqual(resolve(1400, 900, .off).stage, .hidden)
    }

    func testColumnsGrowWithWidthAndAreClamped() {
        XCTAssertEqual(resolve(SettingsMetrics.minWindowWidth, 700).columns, 1)
        XCTAssertEqual(resolve(5000, 700).columns, SettingsLayoutClass.maxColumns)
        // The sidebar expands at its breakpoint and takes room back, so check each class on its own.
        let ranges: [[CGFloat]] = [
            Array(stride(from: SettingsMetrics.minWindowWidth, to: 860, by: 20)),
            Array(stride(from: 860, through: 3000, by: 20))
        ]
        for range in ranges {
            var last = 0
            for w in range {
                let c = resolve(w, 700).columns
                XCTAssertGreaterThanOrEqual(c, last, "columns must never shrink as the window widens (w=\(w))")
                last = c
            }
        }
    }

    func testTheStageLengthIsClampedToItsBounds() {
        XCTAssertEqual(SettingsStageSize.length(fraction: 0.36, available: 700), 252, accuracy: 0.001)
        XCTAssertEqual(SettingsStageSize.length(fraction: 0.05, available: 700), SettingsStageSize.minimum)
        XCTAssertEqual(SettingsStageSize.length(fraction: 0.9, available: 700), 420, accuracy: 0.001)
        XCTAssertEqual(SettingsStageSize.length(fraction: 0.36, available: 200), 120, accuracy: 0.001)
    }

    func testADragStoresAFractionThatRoundTrips() {
        let stored = SettingsStageSize.fraction(length: 300, available: 800)
        XCTAssertEqual(SettingsStageSize.length(fraction: stored, available: 800), 300, accuracy: 0.001)
        XCTAssertEqual(SettingsStageSize.fraction(length: 10, available: 800), 160.0 / 800, accuracy: 0.001)
        XCTAssertEqual(SettingsStageSize.fraction(length: 790, available: 800), 0.6, accuracy: 0.001)
        XCTAssertEqual(SettingsStageSize.fraction(length: 100, available: 0), SettingsStageSize.defaultFraction)
    }
}
