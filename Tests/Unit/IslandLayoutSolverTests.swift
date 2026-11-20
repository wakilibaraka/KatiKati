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
            mode: .split3, widgetOrder: BarSection.defaultOrder, widgetWidths: [:],
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
            mode: .split4, widgetOrder: BarSection.defaultOrder, widgetWidths: [:],
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
            mode: .windows, widgetOrder: BarSection.defaultOrder, widgetWidths: [:],
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
            mode: .centered, widgetOrder: BarSection.defaultOrder, widgetWidths: [:],
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
                mode: mode, widgetOrder: BarSection.defaultOrder, widgetWidths: [:],
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
            XCTAssertEqual(covered, Set(BarSection.defaultOrder), "Mode \(mode) missed sections")
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
        XCTAssertEqual(ordered[2].sections, [.utilities, .clock, .widgets])

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
        XCTAssertEqual(ordered[3].sections, [.utilities, .clock, .widgets])
        

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
            mode: .windows, widgetOrder: BarSection.defaultOrder, widgetWidths: [:],
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
        XCTAssertEqual(island.sections, BarSection.defaultOrder)
        XCTAssertEqual(island.frame.minX, 12)
        XCTAssertEqual(island.frame.width, 1728 - 24)
        XCTAssertEqual(island.frame.minY, 8)
        XCTAssertEqual(island.frame.height, 46)
        XCTAssertTrue(IslandLayoutSolver.validate(layout: layout, screenWidth: 1728, expectedBarHeight: 46))
    }

    func testCenteredModeProducesCenteredIsland() {
        let layout = IslandLayoutSolver.layout(
            screenWidth: 1728,
            mode: .centered, widgetOrder: BarSection.defaultOrder, widgetWidths: [:],
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
        XCTAssertEqual(island.sections, BarSection.defaultOrder)
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
            mode: .centered, widgetOrder: BarSection.defaultOrder, widgetWidths: [:],
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
            mode: .centered, widgetOrder: BarSection.defaultOrder, widgetWidths: [:],
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
            mode: .split3, widgetOrder: BarSection.defaultOrder,
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
            screenWidth: 1728, mode: .split5, widgetOrder: BarSection.defaultOrder, widgetWidths: [:],
            tileStride: 46, appCount: 9, clusterWidth: 140,
            gap: 10, margin: 12, barHeight: 46, bottomMargin: 8,
            screenOriginX: 0
        )
        XCTAssertEqual(layout.islands.count, 5)
        let ordered = layout.islands.sorted { $0.frame.minX < $1.frame.minX }
        XCTAssertEqual(ordered.map(\.sections), [[.launcher], [.weather], [.apps, .media, .utilities], [.clock], [.widgets]])
        for island in ordered {
            XCTAssertGreaterThanOrEqual(island.frame.minX, 0)
            XCTAssertLessThanOrEqual(island.frame.maxX, 1728)
        }
        XCTAssertTrue(IslandLayoutSolver.validate(layout: layout, screenWidth: 1728, expectedBarHeight: 46))
    }

    // MARK: - Phase 11a: chrome-true widths + overlap resolution

    func testFixedIslandWidthIncludesStripChrome() {
        // launcher 40 + weather 150 at native scale: 2×8 inset + one 9 pt divider (Phase 49).
        let width = IslandChrome.fixedIslandWidth(contentWidth: 190, sectionCount: 2, scale: 1)
        XCTAssertEqual(width, 190 + 16 + 9)
        XCTAssertEqual(IslandChrome.fixedIslandWidth(contentWidth: 0, sectionCount: 0, scale: 1), 0)
    }

    /// Phase 49: the 8 pt end inset plus the 7 pt cross-axis slack (`(54 - 40) / 2`) keeps a 40×40
    /// tile clear of the 16 pt plate corner arc (`(16 - 7)^2 + (16 - 8)^2 = 81 + 64 = 145 <= 256`).
    func testContentInsetClearsThePlateCorner() {
        for barHeight: CGFloat in [32, 54, 90] {
            let scale = barHeight / 54
            let radius = DockShape.panelCornerRadius * scale
            let side = (barHeight - BarSection.railTileSize * scale) / 2
            let end = IslandChrome.contentInset * scale
            let dx = radius - side
            let dy = radius - end
            XCTAssertLessThanOrEqual(dx * dx + dy * dy, radius * radius,
                                     "\(barHeight): a 40×40 end tile's corner is clipped")
        }
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

    /// Phase 42 / Phase 49: a rail packs at the native Dock's 2 pt icon pitch and uses balanced 8 pt
    /// end insets matching the horizontal bar so end tiles clear the rounded island corners.
    func testRailSpacingMatchesTheNativeDock() {
        XCTAssertEqual(IslandChrome.railChipSpacing, 2)
        XCTAssertEqual(IslandChrome.railChipSpacing, ChipPillMetrics.chipSpacing,
                       "both axes pack at one pitch")
        XCTAssertEqual(IslandChrome.railContentInset, 8)
        XCTAssertEqual(IslandChrome.railContentInset, IslandChrome.contentInset,
                       "both axes use the balanced 8 pt end inset")
    }

    /// The rail's end inset reaches the solver: passing a custom inset adjusts a fixed island's width
    /// by 2 × Δinset.
    func testRailFixedIslandsUseTheRailEndInset() {
        func width(_ inset: CGFloat) -> CGFloat {
            IslandLayoutSolver.layout(
                screenWidth: 1710, mode: .split3, tileStride: 42, appCount: 8,
                weatherWidth: 150, clockWidth: 160, clusterWidth: 120,
                gap: 10, margin: 12, barHeight: 54, bottomMargin: 8,
                contentInset: inset).islands[0].frame.width
        }
        XCTAssertEqual(width(16) - width(IslandChrome.railContentInset),
                       2 * (16 - IslandChrome.railContentInset), accuracy: 0.001)
    }

    func testSplitFixedIslandsMatchTheWidthTheStripDraws() {
        let layout = IslandLayoutSolver.layout(
            screenWidth: 1710, mode: .split3, tileStride: 55, appCount: 8,
            weatherWidth: 150, clockWidth: 160, clusterWidth: 120,
            gap: 10, margin: 12, barHeight: 54, bottomMargin: 8)
        let left = layout.islands[0]
        XCTAssertEqual(left.sections, [.launcher, .weather])
        XCTAssertEqual(left.frame.width, 40 + 150 + 16 + 9, accuracy: 0.001)
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
        // launcher 40 + weather 150 + chrome 25 (2×8 inset + a 9 pt divider), all × (h / 54).
        XCTAssertEqual(leftWidth(108), 2 * 215, accuracy: 0.001)
        XCTAssertEqual(leftWidth(27), 215 / 2, accuracy: 0.001)
    }

    func testRailDisablingMinimumWidgetWidthsPreservesCompactSizes() {
        let layout = IslandLayoutSolver.layout(
            screenWidth: 1000,
            mode: .split3,
            widgetOrder: BarSection.defaultOrder,
            widgetWidths: [.clock: 40, .weather: 40],
            tileStride: 42,
            appCount: 4,
            weatherWidth: 120,
            clockWidth: 160,
            clusterWidth: 40,
            gap: 10,
            margin: 12,
            barHeight: 54,
            bottomMargin: 8,
            contentInset: IslandChrome.railContentInset,
            enforceMinimumWidgetWidths: false
        )
        let weather = layout.islands.first { $0.sections.contains(.weather) }
        XCTAssertNotNil(weather)
        // [launcher: 40, weather: 40] + 2 * 8 inset + 9 divider = 105
        XCTAssertEqual(weather!.frame.width, 40 + 40 + 2 * IslandChrome.railContentInset + IslandChrome.dividerGap, accuracy: 0.001)
    }
}

/// Slice DP-3: Wide spends its spare width as capped, equal gaps plus a symmetric margin, so a
/// short row cannot turn into one dead void (the two elastic dividers Wide used before).
final class WideGapPlanTests: XCTestCase {
    private let cap = WideGapPlan.gapCap

    func testNoSpareAddsNothing() {
        let plan = WideGapPlan.resolve(spare: 0, interiorGaps: 11)
        XCTAssertEqual(plan.gap, 0)
        XCTAssertEqual(plan.endPadding, 0)
        XCTAssertEqual(WideGapPlan.resolve(spare: -40, interiorGaps: 3), plan, "a negative spare is clamped")
    }

    func testGapsAreCappedAndTheRestGoesToBothEnds() {
        let plan = WideGapPlan.resolve(spare: 600, interiorGaps: 12)
        XCTAssertEqual(plan.gap, cap, "a large spare may only grow one gap to the cap")
        XCTAssertEqual(plan.endPadding, (600 - cap * 12) / 2, accuracy: 0.001,
                       "the remainder is split evenly, not poured into one end")
        XCTAssertEqual(plan.gap * 12 + plan.endPadding * 2, 600, accuracy: 0.001)
    }

    func testSmallSpareIsSharedThenCapped() {
        let plan = WideGapPlan.resolve(spare: 100, interiorGaps: 12)
        XCTAssertEqual(plan.gap, 100.0 / 14.0, accuracy: 0.001, "the ends take their share of a short surplus")
        XCTAssertLessThanOrEqual(plan.gap, cap)
        XCTAssertEqual(plan.gap * 12 + plan.endPadding * 2, 100, accuracy: 0.001)
    }

    func testEveryInputAccountsForEveryPoint() {
        for gaps in [0, 1, 2, 7, 12, 20] {
            for spare in stride(from: 0.0, through: 1000.0, by: 37.0) {
                let plan = WideGapPlan.resolve(spare: spare, interiorGaps: gaps)
                XCTAssertLessThanOrEqual(plan.gap, cap + 0.001)
                XCTAssertGreaterThanOrEqual(plan.endPadding, 0)
                XCTAssertEqual(plan.gap * CGFloat(gaps) + plan.endPadding * 2, spare, accuracy: 0.001,
                               "gaps \(gaps), spare \(spare)")
            }
        }
        // A single entry has no interior gap at all: the spare is only margin.
        let single = WideGapPlan.resolve(spare: 120, interiorGaps: 0)
        XCTAssertEqual(single.gap, 0)
        XCTAssertEqual(single.endPadding, 60, accuracy: 0.001)
    }

    /// The one-window case from the plan: content plus gaps plus both margins must equal the plate,
    /// and no single gap may be wider than the cap.
    func testOneWindowRowFillsThePlateWithoutAVoid() {
        let plate: CGFloat = 1684
        let baseSpacing: CGFloat = 2
        let content: CGFloat = 34 + 150 + 215 + 160 + 112   // launcher, weather, media, clock, utilities
        let entries = 5
        let gaps = entries - 1
        let spare = plate - content - baseSpacing * CGFloat(gaps)
        let plan = WideGapPlan.resolve(spare: spare, interiorGaps: gaps)
        let filled = content + (baseSpacing + plan.gap) * CGFloat(gaps) + plan.endPadding * 2
        XCTAssertEqual(filled, plate, accuracy: 0.001)
        XCTAssertLessThanOrEqual(baseSpacing + plan.gap, cap + baseSpacing)
        XCTAssertEqual(plan.endPadding, (spare - plan.gap * CGFloat(gaps)) / 2, accuracy: 0.001)
    }

    // MARK: DP-4 — island content width

    private func dp4Split3(screenWidth: CGFloat) -> IslandLayoutSolver.IslandLayout {
        IslandLayoutSolver.layout(
            screenWidth: screenWidth,
            mode: .split3, widgetOrder: BarSection.defaultOrder, widgetWidths: [:],
            tileStride: 46,
            appCount: 8,
            weatherWidth: 200,
            clockWidth: 100,
            clusterWidth: 140,
            gap: 10,
            margin: 12,
            barHeight: 46,
            bottomMargin: 8
        )
    }

    /// A shrunk island reports the width its chips need, not the width it was given: the strip
    /// scrolls that content inside the frame (the row already lives in a `ScrollView` with the
    /// edge fade), so "reachable" is `contentWidth > frame.width` rather than a silent cut.
    func testShrunkIslandReportsContentNotFrame() {
        let roomy = dp4Split3(screenWidth: 1728)
        let tight = dp4Split3(screenWidth: 640)

        XCTAssertTrue(roomy.islands.allSatisfy { !$0.isClipping }, "a roomy bar fits its content exactly")
        XCTAssertTrue(tight.islands.contains { $0.isClipping }, "a 640 pt split3 cannot fit three islands' content")

        for index in tight.islands.indices {
            let narrow = tight.islands[index]
            if !narrow.sections.contains(.apps) {
                XCTAssertEqual(narrow.contentWidth, roomy.islands[index].contentWidth, accuracy: 0.001,
                               "a fixed island's content width is intrinsic; the span only subtracts from its frame")
            } else {
                // The apps island's content is the tiles it still has room to show.
                XCTAssertLessThanOrEqual(narrow.contentWidth, roomy.islands[index].contentWidth + 0.001)
            }
            if narrow.isClipping {
                XCTAssertGreaterThan(narrow.contentWidth, narrow.frame.width,
                                     "a clipping island still knows how much it has to scroll")
            }
        }
    }

    /// The apps island is the one that keeps its tiles: its content width is the tile cluster it
    /// renders, so shrinking it is visible instead of silently pretending the row fits.
    func testAppsIslandContentWidthFollowsItsTiles() {
        let tight = dp4Split3(screenWidth: 640)
        let apps = tight.islands.first { $0.sections.contains(.apps) }
        XCTAssertNotNil(apps)
        XCTAssertGreaterThan(apps!.contentWidth, 0)
        XCTAssertLessThanOrEqual(tight.visibleAppTiles, 8)
    }

    // MARK: DP-4 — Background Apps anchor

    func testBackgroundAppsAnchorIsTheTrailingIslandInEverySplit() {
        for mode in [BarLayoutMode.split3, .split4, .split5] {
            let islands = BarSection.islands(for: mode, order: BarSection.defaultOrder)
            let apps = islands.firstIndex { $0.contains(.apps) }
            XCTAssertEqual(BackgroundAppsAnchor.hostSlot(islands: islands), islands.count - 1,
                           "\(mode) hosts the block on the trailing island")
            XCTAssertNotEqual(BackgroundAppsAnchor.hostSlot(islands: islands), apps,
                              "\(mode) left the block floating between islands")
        }
    }

    func testBackgroundAppsAnchorFallsBackToAppsWhenThereIsNoTrailingIsland() {
        for mode in [BarLayoutMode.windows, .centered] {
            let islands = BarSection.islands(for: mode, order: BarSection.defaultOrder)
            XCTAssertEqual(islands.count, 1)
            XCTAssertEqual(BackgroundAppsAnchor.hostSlot(islands: islands), 0)
        }
        // A split whose trailing group lost every section: nothing to host it but the apps island.
        let emptyTrailing: [[BarSection]] = [[.launcher, .weather], [.apps, .media], []]
        XCTAssertEqual(BackgroundAppsAnchor.hostSlot(islands: emptyTrailing), 1)
    }

    // MARK: DP-5 — rail pitch and thickness

    func testEighteenChipsFitNineHundredPointsAboveTheFloor() {
        let plan = RailPitchPlan.resolve(usable: 900, count: 18, barHeight: 54)
        XCTAssertGreaterThanOrEqual(plan.pitch, RailPitchPlan.minimumPitch)
        XCTAssertFalse(plan.overflows)
        XCTAssertLessThanOrEqual(plan.pitch * 18 + 2 * RailPitchPlan.inset, 900 + 0.001,
                                 "the pitch it chose actually fits the count it was given")
        XCTAssertLessThanOrEqual(plan.pitch, 40 + IslandChrome.railChipSpacing,
                                 "a roomy rail never stretches chips past their natural stride")
    }

    func testThirtyChipsOverflowRatherThanClip() {
        let plan = RailPitchPlan.resolve(usable: 700, count: 30, barHeight: 54)
        XCTAssertTrue(plan.overflows, "30 chips cannot fit 700 pt at the legibility floor")
        XCTAssertEqual(plan.pitch, RailPitchPlan.minimumPitch, accuracy: 0.001,
                       "the floor is where it stops shrinking; the strip scrolls from there")
    }

    func testRailThicknessIsInTheNativeRangeAndClamped() {
        XCTAssertEqual(RailPitchPlan.thickness(barHeight: 54), 48, accuracy: 0.001)
        XCTAssertTrue((42.0...48.0).contains(RailPitchPlan.thickness(barHeight: 54)))
        // Scales down with the bar, and never past 48 however tall the bar gets.
        XCTAssertEqual(RailPitchPlan.thickness(barHeight: 32), 48 * 32 / 54, accuracy: 0.001)
        XCTAssertEqual(RailPitchPlan.thickness(barHeight: 120), RailPitchPlan.maximumThickness)
    }

    func testWidgetTileFollowsThePitch() {
        let plan = RailPitchPlan.resolve(usable: 400, count: 14, barHeight: 54)
        let tile = RailPitchPlan.widgetTile(pitch: plan.pitch, barHeight: 54)
        XCTAssertEqual(tile + IslandChrome.railChipSpacing, plan.pitch, accuracy: 0.001,
                       "a widget tile plus the rail's gap is exactly one pitch")
        XCTAssertLessThan(tile, BarSection.railTileSize, "the squeezed rail shrinks its widget tiles too")
    }

    func testBackgroundAppsAnchorStaysOnTheAppsIslandForARail() {
        let islands = BarSection.islands(for: .split3, order: BarSection.defaultOrder)
        XCTAssertEqual(BackgroundAppsAnchor.hostSlot(islands: islands, isRail: true),
                       islands.firstIndex { $0.contains(.apps) },
                       "a rail hangs the block off the apps island, not the bottom of the stack")
    }
}
