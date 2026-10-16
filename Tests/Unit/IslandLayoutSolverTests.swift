import CoreGraphics
import XCTest
@testable import KatiKati

final class IslandLayoutSolverTests: XCTestCase {
    private func split3Layout(
        appCount: Int,
        screenWidth: CGFloat = 1728,
        gap: CGFloat = 10,
        margin: CGFloat = 12,
        barHeight: CGFloat = 46,
        bottomMargin: CGFloat = 8,
        screenOriginX: CGFloat = 0,
        screenMinY: CGFloat = 0
    ) -> IslandLayoutSolver.IslandLayout {
        IslandLayoutSolver.layout(
            screenWidth: screenWidth,
            mode: .split3, widgetOrder: BarSection.canonicalOrder, widgetWidths: [:],
            tileStride: 46,
            appCount: appCount,
            weatherWidth: 200,
            clockWidth: 100,
            clusterWidth: 140,
            gap: gap,
            margin: margin,
            barHeight: barHeight,
            bottomMargin: bottomMargin,
            screenOriginX: screenOriginX,
            screenMinY: screenMinY
        )
    }

    private func split4Layout(
        appCount: Int,
        screenWidth: CGFloat = 1728,
        gap: CGFloat = 10,
        margin: CGFloat = 12,
        barHeight: CGFloat = 46,
        bottomMargin: CGFloat = 8
    ) -> IslandLayoutSolver.IslandLayout {
        IslandLayoutSolver.layout(
            screenWidth: screenWidth,
            mode: .split4, widgetOrder: BarSection.canonicalOrder, widgetWidths: [:],
            tileStride: 46,
            appCount: appCount,
            weatherWidth: 200,
            clockWidth: 100,
            clusterWidth: 140,
            gap: gap,
            margin: margin,
            barHeight: barHeight,
            bottomMargin: bottomMargin
        )
    }

    func testSplitModesExposeExpectedIslands() {
        let windowsLayout = IslandLayoutSolver.layout(
            screenWidth: 1728,
            mode: .windows, widgetOrder: BarSection.canonicalOrder, widgetWidths: [:],
            tileStride: 46,
            appCount: 9,
            weatherWidth: 200,
            clockWidth: 100,
            clusterWidth: 140,
            gap: 10,
            margin: 12,
            barHeight: 46,
            bottomMargin: 8
        )
        XCTAssertEqual(windowsLayout.islands.count, 1)

        let split3 = split3Layout(appCount: 9)
        XCTAssertEqual(split3.islands.count, 3)

        let split4 = split4Layout(appCount: 9)
        XCTAssertEqual(split4.islands.count, 4)

        let centeredLayout = IslandLayoutSolver.layout(
            screenWidth: 1728,
            mode: .centered, widgetOrder: BarSection.canonicalOrder, widgetWidths: [:],
            tileStride: 46,
            appCount: 9,
            weatherWidth: 200,
            clockWidth: 100,
            clusterWidth: 140,
            gap: 10,
            margin: 12,
            barHeight: 46,
            bottomMargin: 8
        )
        XCTAssertEqual(centeredLayout.islands.count, 1)
    }

    func testEverySectionLivesInSomeIsland() {
        for mode in BarLayoutMode.allCases {
            let layout = IslandLayoutSolver.layout(
                screenWidth: 1728,
                mode: mode, widgetOrder: BarSection.canonicalOrder, widgetWidths: [:],
                tileStride: 46,
                appCount: 9,
                weatherWidth: 200,
                clockWidth: 100,
                clusterWidth: 140,
                gap: 10,
                margin: 12,
                barHeight: 46,
                bottomMargin: 8
            )
            let covered = Set(layout.islands.flatMap { $0.sections })
            XCTAssertEqual(covered, Set(BarSection.allCases), "Mode \(mode) missed sections")
        }
    }

    func testSplitIslandsStayInsideTheScreen() {
        let layout = split3Layout(appCount: 9)
        XCTAssertEqual(layout.islands.count, 3)
        XCTAssertFalse(layout.showsOverflow)
        XCTAssertEqual(layout.visibleAppTiles, 9)

        for island in layout.islands {
            XCTAssertGreaterThanOrEqual(island.frame.minX, 0)
            XCTAssertLessThanOrEqual(island.frame.maxX, 1728)
            XCTAssertEqual(island.frame.minY, 8)
            XCTAssertEqual(island.frame.height, 46)
        }

        let ordered = layout.islands.sorted { $0.frame.minX < $1.frame.minX }
        XCTAssertEqual(ordered[0].sections, [.launcher, .weather])
        XCTAssertEqual(ordered[1].sections, [.apps, .media])
        XCTAssertEqual(ordered[2].sections, [.clock, .widgets])

        XCTAssertTrue(IslandLayoutSolver.validate(layout: layout, screenWidth: 1728, expectedBarHeight: 46))
    }

    func testSplit4IslandsStayInsideTheScreen() {
        let layout = split4Layout(appCount: 9)
        // 4U-A: split4 detaches media → 4 groups.
        XCTAssertEqual(layout.islands.count, 4)
        XCTAssertFalse(layout.showsOverflow)
        XCTAssertEqual(layout.visibleAppTiles, 9)

        for island in layout.islands {
            XCTAssertGreaterThanOrEqual(island.frame.minX, 0)
            XCTAssertLessThanOrEqual(island.frame.maxX, 1728)
            XCTAssertEqual(island.frame.minY, 8)
            XCTAssertEqual(island.frame.height, 46)
        }

        let ordered = layout.islands.sorted { $0.frame.minX < $1.frame.minX }
        XCTAssertEqual(ordered[0].sections, [.launcher, .weather])
        XCTAssertEqual(ordered[1].sections, [.apps])
        XCTAssertEqual(ordered[2].sections, [.media])
        XCTAssertEqual(ordered[3].sections, [.clock, .widgets])
        

        XCTAssertTrue(IslandLayoutSolver.validate(layout: layout, screenWidth: 1728, expectedBarHeight: 46))
    }

    func testCrowdedAppsShrinkWithOverflowFlag() {
        let layout = split3Layout(appCount: 40, screenWidth: 1200)
        XCTAssertTrue(layout.showsOverflow)
        XCTAssertLessThan(layout.visibleAppTiles, 40)
        XCTAssertGreaterThanOrEqual(layout.visibleAppTiles, 1)

        for island in layout.islands {
            XCTAssertLessThanOrEqual(island.frame.maxX, 1200)
            XCTAssertGreaterThanOrEqual(island.frame.minX, 0)
        }
        XCTAssertTrue(IslandLayoutSolver.validate(layout: layout, screenWidth: 1200, expectedBarHeight: 46))
    }

    func testWindowsModeProducesSingleFullWidthIsland() {
        let layout = IslandLayoutSolver.layout(
            screenWidth: 1728,
            mode: .windows, widgetOrder: BarSection.canonicalOrder, widgetWidths: [:],
            tileStride: 46,
            appCount: 10,
            weatherWidth: 200,
            clockWidth: 100,
            clusterWidth: 140,
            gap: 10,
            margin: 12,
            barHeight: 46,
            bottomMargin: 8
        )
        XCTAssertEqual(layout.islands.count, 1)
        XCTAssertFalse(layout.showsOverflow)
        let island = layout.islands[0]
        XCTAssertEqual(island.sections, BarSection.canonicalOrder)
        XCTAssertEqual(island.frame.minX, 12)
        XCTAssertEqual(island.frame.width, 1728 - 24)
        XCTAssertEqual(island.frame.minY, 8)
        XCTAssertEqual(island.frame.height, 46)
        XCTAssertTrue(IslandLayoutSolver.validate(layout: layout, screenWidth: 1728, expectedBarHeight: 46))
    }

    func testCenteredModeProducesCenteredIsland() {
        let layout = IslandLayoutSolver.layout(
            screenWidth: 1728,
            mode: .centered, widgetOrder: BarSection.canonicalOrder, widgetWidths: [:],
            tileStride: 46,
            appCount: 5,
            weatherWidth: 200,
            clockWidth: 100,
            clusterWidth: 140,
            gap: 10,
            margin: 12,
            barHeight: 46,
            bottomMargin: 8,
            centeredWidth: 720
        )
        XCTAssertEqual(layout.islands.count, 1)
        let island = layout.islands[0]
        XCTAssertEqual(island.sections, BarSection.canonicalOrder)
        XCTAssertEqual(island.frame.minY, 8)
        XCTAssertEqual(island.frame.height, 46)

        // Must be centered within screen
        let center = island.frame.midX
        XCTAssertEqual(center, 1728 / 2, accuracy: 1.0)
        XCTAssertTrue(IslandLayoutSolver.validate(layout: layout, screenWidth: 1728, expectedBarHeight: 46))
    }

    func testCenteredWidthExtremes() {
        // Very small user width expands to fit intrinsic content
        let smallWidthLayout = IslandLayoutSolver.layout(
            screenWidth: 1728,
            mode: .centered, widgetOrder: BarSection.canonicalOrder, widgetWidths: [:],
            tileStride: 46,
            appCount: 8,
            weatherWidth: 200,
            clockWidth: 100,
            clusterWidth: 140,
            gap: 10,
            margin: 12,
            barHeight: 46,
            bottomMargin: 8,
            centeredWidth: 100
        )
        XCTAssertGreaterThan(smallWidthLayout.islands[0].frame.width, 100)

        // Huge user width clamps to screen minus margins
        let hugeWidthLayout = IslandLayoutSolver.layout(
            screenWidth: 1728,
            mode: .centered, widgetOrder: BarSection.canonicalOrder, widgetWidths: [:],
            tileStride: 46,
            appCount: 5,
            weatherWidth: 200,
            clockWidth: 100,
            clusterWidth: 140,
            gap: 10,
            margin: 12,
            barHeight: 46,
            bottomMargin: 8,
            centeredWidth: 5000
        )
        XCTAssertEqual(hugeWidthLayout.islands[0].frame.width, 1728 - 24)
        XCTAssertEqual(hugeWidthLayout.islands[0].frame.minX, 12)
    }

    func testMinimumHalfPointGapEnforced() {
        let tinyGapLayout = split3Layout(appCount: 5, gap: 0.1)
        let sorted = tinyGapLayout.islands.sorted { $0.frame.minX < $1.frame.minX }
        for i in 0..<(sorted.count - 1) {
            let gapBetween = sorted[i + 1].frame.minX - sorted[i].frame.maxX
            XCTAssertGreaterThanOrEqual(gapBetween, 0.5 - 0.001, "Gap between islands must be at least 0.5pt")
        }
    }

    func testGoldenScreenWithNonZeroScreenOrigin() {
        // Multi-display secondary screen positioned at x = 1920, y = 100
        let layout = split3Layout(
            appCount: 8,
            screenWidth: 1728,
            screenOriginX: 1920,
            screenMinY: 100
        )
        XCTAssertEqual(layout.islands.count, 3)
        for island in layout.islands {
            XCTAssertGreaterThanOrEqual(island.frame.minX, 1920)
            XCTAssertLessThanOrEqual(island.frame.maxX, 1920 + 1728)
            XCTAssertEqual(island.frame.minY, 108)
        }
        XCTAssertTrue(IslandLayoutSolver.validate(
            layout: layout,
            screenWidth: 1728,
            screenOriginX: 1920,
            expectedBarHeight: 46
        ))
    }

    /// Regression for the cut-off clock pill (2026-10-11): a stale stored
    /// `clock = 40` override starved FlipClockChip's 2×32 tiles while the
    /// island math stayed in-bounds — so the pill clipped *inside* a valid
    /// frame. Stored widths are floored at the intrinsic minimum.
    func testStaleClockOverrideFloorsAtIntrinsicMinimum() {
        let layout = IslandLayoutSolver.layout(
            screenWidth: 1728,
            mode: .split3, widgetOrder: BarSection.canonicalOrder,
            widgetWidths: [.clock: 40],
            tileStride: 46,
            appCount: 9,
            weatherWidth: 200,
            clockWidth: 100,
            clusterWidth: 140,
            gap: 10,
            margin: 12,
            barHeight: 46,
            bottomMargin: 8
        )
        let clock = layout.islands.first { $0.sections.contains(.clock) }
        XCTAssertNotNil(clock)
        XCTAssertGreaterThanOrEqual(clock!.frame.width, BarSection.clock.minimumWidgetWidth)
    }

    func testSplit5IslandsStayInsideTheScreenInOrder() {
        let layout = IslandLayoutSolver.layout(
            screenWidth: 1728, mode: .split5, widgetOrder: BarSection.canonicalOrder, widgetWidths: [:],
            tileStride: 46, appCount: 9, clusterWidth: 140,
            gap: 10, margin: 12, barHeight: 46, bottomMargin: 8,
            screenOriginX: 0
        )
        XCTAssertEqual(layout.islands.count, 5)
        let ordered = layout.islands.sorted { $0.frame.minX < $1.frame.minX }
        XCTAssertEqual(ordered.map(\.sections), [[.launcher], [.weather], [.apps, .media], [.clock], [.widgets]])
        for island in ordered {
            XCTAssertGreaterThanOrEqual(island.frame.minX, 0)
            XCTAssertLessThanOrEqual(island.frame.maxX, 1728)
        }
        XCTAssertTrue(IslandLayoutSolver.validate(layout: layout, screenWidth: 1728, expectedBarHeight: 46))
    }

    // MARK: - Phase 11a: chrome-true widths + overlap resolution

    func testFixedIslandWidthIncludesStripChrome() {
        // launcher 40 + weather 150 at native scale: 2×16 inset + one 9 pt divider (Phase 41c).
        let width = IslandChrome.fixedIslandWidth(contentWidth: 190, sectionCount: 2, scale: 1)
        XCTAssertEqual(width, 190 + 32 + 9)
        XCTAssertEqual(IslandChrome.fixedIslandWidth(contentWidth: 0, sectionCount: 0, scale: 1), 0)
    }

    /// Phase 41c: the end inset is one plate corner radius and never less — that is the whole
    /// reason the number exists, because the island clips its content to a rounded rectangle.
    func testContentInsetClearsThePlateCorner() {
        XCTAssertGreaterThanOrEqual(IslandChrome.contentInset, DockShape.panelCornerRadius,
                                    "a chip inset past the corner arc would be clipped")
    }

    /// Phase 41b: the solver caps a rail's app tiles with the rail's own stride, not the bottom
    /// bar's 54 pt one — otherwise a rail drops a chip it has room to show.
    func testRailChipStrideIsTheRailTilesOwnPitch() {
        for barHeight: CGFloat in [32, 54, 90] {
            let scale = barHeight / 54
            XCTAssertEqual(IslandChrome.railChipStride(barHeight: barHeight),
                           (BarSection.railTileSize + IslandChrome.railChipSpacing) * scale, accuracy: 0.001,
                           "\(barHeight)")
            XCTAssertLessThan(IslandChrome.railChipStride(barHeight: barHeight),
                              IslandLayoutSolver.tileStride(barHeight: barHeight),
                              "\(barHeight): a rail is denser than the bottom bar")
        }
    }

    /// Phase 42 (owner: "use the mac dock spacing"): a rail packs at the native Dock's own pitch and
    /// keeps the Dock's tight ends. The numbers come from the Dock's accessibility tree on the owner's
    /// side dock — `tilesize 36` lays a 38 pt tile box (2 pt between two icons) and keeps 3.45 pt at the
    /// list's ends — and 2 pt is already what the bottom bar leaves between icons.
    func testRailSpacingMatchesTheNativeDock() {
        XCTAssertEqual(IslandChrome.railChipSpacing, 2)
        XCTAssertEqual(IslandChrome.railChipSpacing, ChipPillMetrics.chipSpacing,
                       "both axes pack at one pitch")
        XCTAssertEqual(IslandChrome.railContentInset, 4)
        XCTAssertLessThan(IslandChrome.railContentInset, IslandChrome.contentInset,
                          "the rail's ends are the Dock's, not the bar's plate radius")
    }

    /// The rail's end inset reaches the solver: a fixed island is 2 × (16 − 4) shorter on a rail than
    /// the bottom bar's chrome would make it, and that is exactly what the strip now draws.
    func testRailFixedIslandsUseTheRailEndInset() {
        func width(_ inset: CGFloat) -> CGFloat {
            IslandLayoutSolver.layout(
                screenWidth: 1710, mode: .split3, tileStride: 42, appCount: 8,
                weatherWidth: 150, clockWidth: 160, clusterWidth: 120,
                gap: 10, margin: 12, barHeight: 54, bottomMargin: 8,
                contentInset: inset).islands[0].frame.width
        }
        XCTAssertEqual(width(IslandChrome.contentInset) - width(IslandChrome.railContentInset),
                       2 * (IslandChrome.contentInset - IslandChrome.railContentInset), accuracy: 0.001)
    }

    func testSplitFixedIslandsMatchTheWidthTheStripDraws() {
        let layout = IslandLayoutSolver.layout(
            screenWidth: 1710, mode: .split3, tileStride: 55, appCount: 8,
            weatherWidth: 150, clockWidth: 160, clusterWidth: 120,
            gap: 10, margin: 12, barHeight: 54, bottomMargin: 8)
        let left = layout.islands[0]
        XCTAssertEqual(left.sections, [.launcher, .weather])
        XCTAssertEqual(left.frame.width, 40 + 150 + 32 + 9, accuracy: 0.001)
    }

    func testExtremeSettingsNeverOverlapOrLeaveTheScreen() {
        let widthSets: [[BarSection: CGFloat]] = [
            [:],
            [.weather: 230, .clock: 210, .media: 240],
            [.weather: 400, .clock: 400, .media: 400],
        ]
        for screenWidth: CGFloat in [1024, 1440, 1710] {
            for barHeight: CGFloat in [32, 54, 90] {
                for gap: CGFloat in [0.5, 40] {
                    for margin: CGFloat in [0, 80] {
                        for widths in widthSets {
                            for mode in [BarLayoutMode.split3, .split4, .split5] {
                                let layout = IslandLayoutSolver.layout(
                                    screenWidth: screenWidth, mode: mode, widgetWidths: widths,
                                    tileStride: IslandLayoutSolver.tileStride(barHeight: barHeight),
                                    appCount: 14, weatherWidth: 150, clockWidth: 160, clusterWidth: barHeight * 3,
                                    gap: gap, margin: margin, barHeight: barHeight, bottomMargin: 8)
                                XCTAssertTrue(
                                    IslandLayoutSolver.validate(layout: layout, screenWidth: screenWidth,
                                                                expectedBarHeight: barHeight),
                                    "\(mode) w=\(screenWidth) h=\(barHeight) gap=\(gap) margin=\(margin) widths=\(widths)")
                            }
                        }
                    }
                }
            }
        }
    }

    func testLopsidedGroupsSlideAppsInsteadOfDroppingTiles() {
        // Everything on the right: the apps island may leave screen centre but keeps its tiles.
        let layout = IslandLayoutSolver.layout(
            screenWidth: 1440, mode: .split3,
            widgetOrder: [.apps, .launcher, .weather, .media, .clock, .widgets],
            widgetWidths: [.weather: 230, .clock: 210],
            tileStride: 55, appCount: 8, weatherWidth: 150, clockWidth: 160, clusterWidth: 120,
            gap: 10, margin: 12, barHeight: 54, bottomMargin: 8)
        XCTAssertFalse(layout.showsOverflow)
        let apps = layout.islands.first { $0.sections.contains(.apps) }!
        XCTAssertLessThan(apps.frame.midX, 720, "apps slid off centre toward the empty side")
        XCTAssertTrue(IslandLayoutSolver.validate(layout: layout, screenWidth: 1440, expectedBarHeight: 54))
    }

    func testModeAwareWidgetBudgetReservesIslandChrome() {
        let plain = WidgetLayout.widgetBudget(screenWidth: 1440, margin: 12, gap: 10, tileStride: 55)
        let split5 = WidgetLayout.widgetBudget(screenWidth: 1440, margin: 12, gap: 10, tileStride: 55,
                                               mode: .split5, barHeight: 54)
        XCTAssertLessThan(split5, plain)
    }

    func testWidgetWidthsScaleWithBarHeight() {
        func leftWidth(_ h: CGFloat) -> CGFloat {
            IslandLayoutSolver.layout(
                screenWidth: 1710, mode: .split3, tileStride: IslandLayoutSolver.tileStride(barHeight: h),
                appCount: 4, weatherWidth: 150, clockWidth: 160, clusterWidth: 120,
                gap: 10, margin: 12, barHeight: h, bottomMargin: 8).islands[0].frame.width
        }
        // launcher 40 + weather 150 + chrome 41 (2×16 inset + a 9 pt divider), all × (h / 54).
        XCTAssertEqual(leftWidth(108), 2 * 231, accuracy: 0.001)
        XCTAssertEqual(leftWidth(27), 231 / 2, accuracy: 0.001)
    }
}
