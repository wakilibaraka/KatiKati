import CoreGraphics
import XCTest
@testable import KatiKati

final class DockStyleTests: XCTestCase {
    func testBuiltInsAreDistinct() {
        let styles = DockStyle.builtIns
        XCTAssertEqual(Set(styles.map(\.id)).count, styles.count)
        for (i, a) in styles.enumerated() {
            for b in styles[(i + 1)...] {
                XCTAssertFalse(
                    a.mode == b.mode && a.size == b.size && a.spacing == b.spacing && a.bottomGap == b.bottomGap
                        && a.widgetPresetID == b.widgetPresetID && a.placement == b.placement,
                    "\(a.id) and \(b.id) would look identical")
            }
        }
    }

    func testFreshInstallValuesReadAsIslands() {
        // Fresh install: split3, native 54 pt, the Comfortable spacing (8/10 since Phase 41c),
        // the hugging bottom gap — and those defaults come from `DockSpacing.comfortable` and
        // `PanelLayoutMetrics` themselves, so this cannot drift into "Custom" on a fresh install again.
        let style = DockStyle.matching(mode: .split3, barHeight: 54,
                                       gap: DockSpacing.comfortable.gap,
                                       margin: DockSpacing.comfortable.margin,
                                       bottomGap: PanelLayoutMetrics.huggingBottomGap)
        XCTAssertEqual(style?.id, DockStyle.islands.id)
        XCTAssertEqual(AppSettingsStore.defaultIslandGap, DockSpacing.comfortable.gap)
        XCTAssertEqual(AppSettingsStore.defaultIslandMargin, DockSpacing.comfortable.margin)
    }

    /// Owner 2026-10-16: a style card must not lift the bar off the edge — every built-in hugs, the
    /// way a fresh install and the one-shot migration (`forceNewLayoutDefaults`) already do.
    func testEveryBuiltInHugsTheBottomEdge() {
        for style in DockStyle.builtIns {
            XCTAssertEqual(style.bottomGap, PanelLayoutMetrics.huggingBottomGap, "\(style.id) floats")
        }
    }

    func testHandTunedValuesReadAsCustom() {
        XCTAssertNil(DockStyle.matching(mode: .split3, barHeight: 54, gap: 9.5, margin: 10, bottomGap: 2))
        // Hand-tuned height with otherwise fresh values: the height alone is enough to read Custom.
        XCTAssertNil(DockStyle.matching(mode: .split3, barHeight: 61, gap: 8, margin: 10, bottomGap: 2))
    }

    func testSizeAndSpacingSteps() {
        XCTAssertEqual(DockSizeClass.nearest(to: 54), .medium)
        XCTAssertEqual(DockSizeClass.nearest(to: 32), .small)
        XCTAssertEqual(DockSizeClass.nearest(to: 90), .large)
        XCTAssertEqual(DockSpacing.matching(gap: 18, margin: 24), .airy)
        XCTAssertNil(DockSpacing.matching(gap: 18, margin: 12))
        for size in DockSizeClass.allCases {
            XCTAssertTrue((DockPanelHeight.minimum...DockPanelHeight.maximum).contains(size.barHeight))
        }
    }

    func testStylesFitALaptopScreenUnchanged() {
        for style in DockStyle.builtIns {
            let fitted = DockStyleFit.resolve(style, screenWidth: 1440, widgetOrder: BarSection.canonicalOrder)
            XCTAssertEqual(fitted, style, "\(style.id) should fit 1440 pt as authored")
        }
    }

    func testANarrowScreenStepsSizeThenSpacingDown() {
        var big = DockStyle.islands
        big.size = .large
        big.spacing = .airy
        let fitted = DockStyleFit.resolve(big, screenWidth: 800, widgetOrder: BarSection.canonicalOrder,
                                          widgetWidths: [.weather: 230, .clock: 210, .media: 240])
        XCTAssertLessThan(fitted.size.barHeight, big.size.barHeight)
        XCTAssertEqual(fitted.mode, big.mode, "fitting never changes the layout mode")
    }

    func testMaximumBarHeightIsCappedByWhatFits() {
        let roomy = DockStyleFit.maximumBarHeight(
            mode: .split3, gap: 10, margin: 12, bottomGap: 8, screenWidth: 2560,
            widgetOrder: BarSection.canonicalOrder, range: 32...90)
        XCTAssertEqual(roomy, 90)
        let tight = DockStyleFit.maximumBarHeight(
            mode: .split5, gap: 40, margin: 80, bottomGap: 8, screenWidth: 1024,
            widgetOrder: BarSection.canonicalOrder, range: 32...90)
        XCTAssertLessThan(tight, 90)
        XCTAssertGreaterThanOrEqual(tight, 32)
    }

    func testSideRailIsMatchedOnlyOnItsEdge() {
        let rail = DockStyle.sideRail
        XCTAssertEqual(DockStyle.matching(mode: rail.mode, barHeight: rail.size.barHeight, gap: rail.spacing.gap,
                                          margin: rail.spacing.margin, bottomGap: rail.bottomGap,
                                          placement: .left)?.id, rail.id)
        XCTAssertEqual(DockStyle.matching(mode: rail.mode, barHeight: rail.size.barHeight, gap: rail.spacing.gap,
                                          margin: rail.spacing.margin, bottomGap: rail.bottomGap,
                                          placement: .bottom)?.id, DockStyle.islands.id,
                       "same values on the bottom read as Islands")
    }
}

