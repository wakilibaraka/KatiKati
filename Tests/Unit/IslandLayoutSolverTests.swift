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
            mode: .split3, widgetOrder: [.weather, .apps, .clock], widgetWidths: [:],
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
            mode: .split4, widgetOrder: [.weather, .apps, .clock], widgetWidths: [:],
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
            mode: .windows, widgetOrder: [.weather, .apps, .clock], widgetWidths: [:],
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
        XCTAssertEqual(split4.islands.count, 3)

        let centeredLayout = IslandLayoutSolver.layout(
            screenWidth: 1728,
            mode: .centered, widgetOrder: [.weather, .apps, .clock], widgetWidths: [:],
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
                mode: mode, widgetOrder: [.weather, .apps, .clock], widgetWidths: [:],
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
        XCTAssertEqual(ordered[0].sections, [.weather])
        XCTAssertEqual(ordered[1].sections, [.apps])
        XCTAssertEqual(ordered[2].sections, [.clock])

        XCTAssertTrue(IslandLayoutSolver.validate(layout: layout, screenWidth: 1728, expectedBarHeight: 46))
    }

    func testSplit4IslandsStayInsideTheScreen() {
        let layout = split4Layout(appCount: 9)
        // Decision 8b: `.tray` removed → the split-4 rule yields 3 groups.
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
        XCTAssertEqual(ordered[0].sections, [.weather])
        XCTAssertEqual(ordered[1].sections, [.apps])
        XCTAssertEqual(ordered[2].sections, [.clock])

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
            mode: .windows, widgetOrder: [.weather, .apps, .clock], widgetWidths: [:],
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
        XCTAssertEqual(island.sections, [.weather, .apps, .clock])
        XCTAssertEqual(island.frame.minX, 12)
        XCTAssertEqual(island.frame.width, 1728 - 24)
        XCTAssertEqual(island.frame.minY, 8)
        XCTAssertEqual(island.frame.height, 46)
        XCTAssertTrue(IslandLayoutSolver.validate(layout: layout, screenWidth: 1728, expectedBarHeight: 46))
    }

    func testCenteredModeProducesCenteredIsland() {
        let layout = IslandLayoutSolver.layout(
            screenWidth: 1728,
            mode: .centered, widgetOrder: [.weather, .apps, .clock], widgetWidths: [:],
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
        XCTAssertEqual(island.sections, [.weather, .apps, .clock])
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
            mode: .centered, widgetOrder: [.weather, .apps, .clock], widgetWidths: [:],
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
            mode: .centered, widgetOrder: [.weather, .apps, .clock], widgetWidths: [:],
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
}
