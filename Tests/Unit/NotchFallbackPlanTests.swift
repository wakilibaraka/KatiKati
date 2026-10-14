import CoreGraphics
import XCTest
@testable import KatiKati

final class NotchFallbackPlanTests: XCTestCase {

    func testHardwareNotchDetection() {
        XCTAssertTrue(NotchFallbackPlan.isNotchedDisplay(safeAreaTop: 32.0))
        XCTAssertTrue(NotchFallbackPlan.isNotchedDisplay(safeAreaTop: 44.0))
        XCTAssertFalse(NotchFallbackPlan.isNotchedDisplay(safeAreaTop: 0.0))
    }

    func testFloatingTopOffsetCalculation() {
        XCTAssertEqual(NotchFallbackPlan.floatingTopOffset(menuBarHeight: 24.0), 32.0)
        XCTAssertEqual(NotchFallbackPlan.floatingTopOffset(menuBarHeight: 30.0), 38.0)
        // Fallback for zero menu bar height
        XCTAssertEqual(NotchFallbackPlan.floatingTopOffset(menuBarHeight: 0.0), 32.0)
    }

    func testUsableWingWidthWithAndWithoutHardwareKeepout() {
        // With hardware notch (160pt central keepout zone)
        let notchedWidth = NotchFallbackPlan.usableWingWidth(closedWidth: 240, hasHardwareNotch: true)
        XCTAssertEqual(notchedWidth, 40.0) // (240 - 160) / 2

        // Without hardware notch (no camera keepout zone needed on external display)
        let floatingWidth = NotchFallbackPlan.usableWingWidth(closedWidth: 240, hasHardwareNotch: false)
        XCTAssertEqual(floatingWidth, 120.0) // 240 / 2
    }

    func testPanelFramePlacementForNotchedVsExternalDisplays() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        // Case 1: Hardware notch display
        let notchedMetrics = NotchMetrics(
            closedSize: CGSize(width: 200, height: 34),
            hasHardwareNotch: true,
            cameraKeepoutBox: CGRect(x: 20, y: 0, width: 160, height: 34)
        )
        let notchedFrame = NotchFallbackPlan.panelFrame(
            metrics: notchedMetrics,
            screenBounds: screen,
            isOpen: false,
            menuBarHeight: 24
        )
        XCTAssertEqual(notchedFrame.origin.x, (1920 - 200) / 2)
        XCTAssertEqual(notchedFrame.origin.y, 0)
        XCTAssertEqual(notchedFrame.width, 200)
        XCTAssertEqual(notchedFrame.height, 34)

        // Case 2: External non-notched display (floating island)
        let externalMetrics = NotchMetrics(
            closedSize: CGSize(width: 185, height: 28),
            hasHardwareNotch: false,
            cameraKeepoutBox: .zero
        )
        let externalFrame = NotchFallbackPlan.panelFrame(
            metrics: externalMetrics,
            screenBounds: screen,
            isOpen: false,
            menuBarHeight: 24
        )
        XCTAssertEqual(externalFrame.origin.x, (1920 - 185) / 2)
        XCTAssertEqual(externalFrame.origin.y, 32.0) // 24 menu bar + 8 margin
        XCTAssertEqual(externalFrame.width, 185)
        XCTAssertEqual(externalFrame.height, 28)
    }
}
