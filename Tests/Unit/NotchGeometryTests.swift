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

    func testClosedCapsuleGrowsOnlyWhenShowingActivity() {
        let m = NotchMetrics(closedSize: CGSize(width: 185, height: 32), hasHardwareNotch: true)
        XCTAssertEqual(NotchGeometry.closedCapsuleSize(m, showsActivity: false).width, 185)
        XCTAssertEqual(NotchGeometry.closedCapsuleSize(m, showsActivity: true).width, 185 + NotchGeometry.sneakSide * 2)
    }
}
