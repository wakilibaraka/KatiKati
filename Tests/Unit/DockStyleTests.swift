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

    func testFreshInstallValuesReadAsWide() {
        // DP-7: a fresh install opens as Wide — mode, bar height, spacing and hugging gap all come from
        // `DockStyle.freshInstall`, so the welcome guide pre-selects the card the bar already is.
        let style = DockStyle.matching(mode: DockStyle.freshInstall.mode,
                                       barHeight: DockStyle.freshInstall.size.barHeight,
                                       gap: AppSettingsStore.defaultIslandGap,
                                       margin: AppSettingsStore.defaultIslandMargin,
                                       bottomGap: DockStyle.freshInstall.bottomGap)
        XCTAssertEqual(style?.id, DockStyle.wide.id)
        XCTAssertEqual(DockStyle.freshInstall.id, DockStyle.wide.id)
        XCTAssertEqual(AppSettingsStore.defaultIslandGap, DockSpacing.compact.gap)
        XCTAssertEqual(AppSettingsStore.defaultIslandMargin, DockSpacing.compact.margin)
    }

    /// DP-7: Wide leads the cards, `Classic` reads as Floating while keeping its persisted id.
    func testWideLeadsTheCardsAndClassicReadsAsFloating() {
        XCTAssertEqual(DockStyle.builtIns.map(\.id),
                       [DockStyle.wide.id, DockStyle.classic.id, DockStyle.islands.id,
                        DockStyle.minimal.id, DockStyle.sideRail.id])
        XCTAssertEqual(DockStyle.classic.localizedTitle, String(localized: "Floating"))
        XCTAssertEqual(DockStyle.classic.id, "style.classic")
    }

    /// Owner 2026-10-16: a style card must not lift the bar off the edge — every built-in hugs, the
    /// way a fresh install and the one-shot migration (`forceNewLayoutDefaults`) already do.
    func testEveryBuiltInHugsTheBottomEdge() {
        for style in DockStyle.builtIns {
            XCTAssertEqual(style.bottomGap, PanelLayoutMetrics.huggingBottomGap, "\(style.id) floats")
        }
    }

    /// DP-5: Minimal is a widget set, not "whatever the user had visible" — the presets that used to
    /// leave every wide widget on a centered island whose width is `min(centeredWidth, content)`.
    func testMinimalWritesAWidgetSetThatKeepsTheNarrowOnes() {
        guard let id = DockStyle.minimal.widgetPresetID,
              let preset = WidgetPresets.builtIns.first(where: { $0.id == id }) else {
            return XCTFail("Minimal no longer writes a widget set")
        }
        let visible = Set(preset.layout.visibleOrder)
        XCTAssertTrue(visible.contains(.apps))
        XCTAssertTrue(visible.contains(.clock))
        XCTAssertTrue(visible.contains(.utilities))
        XCTAssertFalse(visible.contains(.weather), "Minimal was still inheriting Weather")
        XCTAssertFalse(visible.contains(.media), "Minimal was still inheriting Now Playing")
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
            let fitted = DockStyleFit.resolve(style, screenWidth: 1440, widgetOrder: BarSection.defaultOrder)
            XCTAssertEqual(fitted, style, "\(style.id) should fit 1440 pt as authored")
        }
    }

    func testANarrowScreenStepsSizeThenSpacingDown() {
        var big = DockStyle.islands
        big.size = .large
        big.spacing = .airy
        let fitted = DockStyleFit.resolve(big, screenWidth: 800, widgetOrder: BarSection.defaultOrder,
                                          widgetWidths: [.weather: 230, .clock: 210, .media: 240])
        XCTAssertLessThan(fitted.size.barHeight, big.size.barHeight)
        XCTAssertEqual(fitted.mode, big.mode, "fitting never changes the layout mode")
    }

    func testMaximumBarHeightIsCappedByWhatFits() {
        let roomy = DockStyleFit.maximumBarHeight(
            mode: .split3, gap: 10, margin: 12, bottomGap: 8, screenWidth: 2560,
            widgetOrder: BarSection.defaultOrder, range: 32...90)
        XCTAssertEqual(roomy, 90)
        let tight = DockStyleFit.maximumBarHeight(
            mode: .split5, gap: 40, margin: 80, bottomGap: 8, screenWidth: 1024,
            widgetOrder: BarSection.defaultOrder, range: 32...90)
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

