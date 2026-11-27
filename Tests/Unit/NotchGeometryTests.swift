import XCTest
@testable import KatiKati

// Phase 8b-7 — pure notch geometry: real notch, fake notch, odd inputs, panel placement.

final class NotchGeometryTests: XCTestCase {
    func testRealNotchWidthComesFromAuxiliaryAreas() {
        let m = NotchGeometry.metrics(screenWidth: 1512, safeAreaTop: 32, auxLeftWidth: 664, auxRightWidth: 664, menuBarHeight: 37)
        XCTAssertTrue(m.hasHardwareNotch)
        XCTAssertEqual(m.closedSize.width, 1512 - 664 - 664 + 4)
        XCTAssertEqual(m.closedSize.height, 32, "notch height = safe-area inset")
    }

    func testNotchlessDisplayGetsFakeNotchAtMenuBarHeight() {
        let m = NotchGeometry.metrics(screenWidth: 1920, safeAreaTop: 0, auxLeftWidth: nil, auxRightWidth: nil, menuBarHeight: 24)
        XCTAssertFalse(m.hasHardwareNotch)
        XCTAssertEqual(m.closedSize, CGSize(width: NotchGeometry.fallbackNotchWidth, height: 24))
    }

    func testUnknownMenuBarHeightFallsBack() {
        let m = NotchGeometry.metrics(screenWidth: 1920, safeAreaTop: 0, auxLeftWidth: nil, auxRightWidth: nil, menuBarHeight: 0)
        XCTAssertEqual(m.closedSize.height, NotchGeometry.fallbackHeight)
    }

    /// Nonsense auxiliary areas (overlapping, negative) must not produce a zero/negative width.
    func testBadAuxiliaryAreasFallBackToDefaultWidth() {
        for (l, r) in [(1000.0, 1000.0), (-5.0, 100.0)] {
            let m = NotchGeometry.metrics(screenWidth: 1500, safeAreaTop: 30, auxLeftWidth: l, auxRightWidth: r, menuBarHeight: 30)
            XCTAssertEqual(m.closedSize.width, NotchGeometry.fallbackNotchWidth, "\(l),\(r)")
        }
    }

    func testPanelIsTopCentredOnTheScreen() {
        let screen = CGRect(x: 100, y: 50, width: 1000, height: 700)
        let f = NotchGeometry.panelFrame(size: CGSize(width: 200, height: 30), in: screen)
        XCTAssertEqual(f, CGRect(x: 500, y: 720, width: 200, height: 30))
        XCTAssertEqual(f.maxY, screen.maxY, "flush with the top edge")
    }

    func testExpandedIslandFitsNarrowExternalDisplay() {
        let screen = CGRect(x: 0, y: 0, width: 600, height: 900)
        let metrics = NotchMetrics(closedSize: CGSize(width: 185, height: 24), hasHardwareNotch: false)
        let frame = NotchGeometry.stageFrame(
            for: .dynamicIsland, isExpanded: true, isWide: false, metrics: metrics,
            closedSize: metrics.closedSize, openSize: NotchGeometry.dynamicIslandOpenSize,
            screenBounds: screen, topInset: 0, menuBarHeight: 24
        )
        XCTAssertEqual(frame.width, 576)
        XCTAssertEqual(frame.minX, 12)
    }

    /// The Settings/guide demo draws the real silhouette: the skin's open panel, or the closed capsule.
    func testPreviewSizeFollowsTheSkinAndTheExpandedState() {
        XCTAssertEqual(NotchGeometry.openSize(for: .dynamicIsland), NotchGeometry.openSize)
        XCTAssertEqual(NotchGeometry.previewSize(for: .boring, expanded: true), NotchGeometry.openSize)
        XCTAssertEqual(NotchGeometry.previewSize(for: .dynamicIsland, expanded: true), NotchGeometry.openSize)
        XCTAssertEqual(NotchGeometry.previewSize(for: .classic, expanded: true), NotchGeometry.classicOpenSize)
        let closed = NotchGeometry.previewSize(for: .boring, expanded: false)
        XCTAssertEqual(closed, CGSize(width: NotchDesignSpec.fallbackClosedWidth, height: NotchDesignSpec.fallbackClosedHeight))
        XCTAssertEqual(closed, NotchGeometry.previewSize(for: .classic, expanded: false), "the closed capsule does not depend on the skin")
        XCTAssertLessThan(closed.height, NotchGeometry.previewSize(for: .boring, expanded: true).height)
    }

    func testClosedCapsuleGrowsOnlyWhenShowingActivity() {
        let m = NotchMetrics(closedSize: CGSize(width: 185, height: 32), hasHardwareNotch: true)
        XCTAssertEqual(NotchGeometry.closedCapsuleSize(m, showsActivity: false).width, 185)
        XCTAssertEqual(NotchGeometry.closedCapsuleSize(m, showsActivity: true).width, 185 + NotchGeometry.sneakSide * 2)
    }

    func testStageSizeShrinksLiquidAndDynamicIslandWhenClosed() {
        let notched = NotchMetrics(closedSize: CGSize(width: 185, height: 38), hasHardwareNotch: true)
        let flat = NotchMetrics(closedSize: CGSize(width: 185, height: 24), hasHardwareNotch: false)
        let closedCapsule = NotchGeometry.closedCapsuleSize(notched, showsActivity: true)

        let liquidIdle = NotchGeometry.stageSize(
            for: .liquid, isExpanded: false, isWide: false, metrics: notched,
            closedSize: closedCapsule, openSize: NotchGeometry.liquidOpenSize, hasCompactActivity: false
        )
        let liquidCompact = NotchGeometry.stageSize(
            for: .liquid, isExpanded: false, isWide: false, metrics: notched,
            closedSize: closedCapsule, openSize: NotchGeometry.liquidOpenSize, hasCompactActivity: true
        )
        let liquidExpanded = NotchGeometry.stageSize(
            for: .liquid, isExpanded: true, isWide: false, metrics: notched,
            closedSize: closedCapsule, openSize: NotchGeometry.liquidOpenSize, hasCompactActivity: true
        )
        XCTAssertLessThanOrEqual(liquidIdle.height, 60)
        XCTAssertLessThanOrEqual(liquidCompact.height, 60)
        XCTAssertGreaterThanOrEqual(liquidExpanded.height, 220)
        XCTAssertLessThan(liquidIdle.width, liquidExpanded.width)

        let islandClosed = NotchGeometry.stageSize(
            for: .dynamicIsland, isExpanded: false, isWide: false, metrics: flat,
            closedSize: flat.closedSize, openSize: NotchGeometry.dynamicIslandOpenSize
        )
        let islandExpanded = NotchGeometry.stageSize(
            for: .dynamicIsland, isExpanded: true, isWide: false, metrics: flat,
            closedSize: flat.closedSize, openSize: NotchGeometry.dynamicIslandOpenSize
        )
        XCTAssertLessThanOrEqual(islandClosed.height, 60)
        XCTAssertEqual(islandExpanded.width, 704)
        XCTAssertEqual(islandExpanded.height, 240)
    }
}
