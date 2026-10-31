import CoreGraphics
import XCTest
@testable import KatiKati

/// 57b: the launcher's panel shapes, checked without opening a window.
final class LauncherPresentationTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1710, height: 1112)
    private let visible = CGRect(x: 0, y: 70, width: 1710, height: 1017)

    func testStoredValueFallsBackToFloatingDock() {
        XCTAssertEqual(LauncherPresentation.default, .floatingDock)
        XCTAssertEqual(LauncherPresentation.parse(nil), .floatingDock)
        XCTAssertEqual(LauncherPresentation.parse("nonsense"), .floatingDock)
        XCTAssertEqual(LauncherPresentation.parse("fullscreen"), .fullscreen)
        XCTAssertEqual(LauncherPresentation.parse("centred"), .centred)
        XCTAssertEqual(LauncherPresentation.parse("dock"), .floatingDock)
    }

    func testStoredPopoverKeepsAFloatingCard() {
        XCTAssertEqual(LauncherPresentation.parse("popover"), .floatingDock)
    }

    func testFullscreenIsExactlyTheScreen() {
        XCTAssertEqual(LauncherPanelFrame.rect(mode: .fullscreen, screen: screen, visible: visible), screen)
    }

    func testCentredIsEightyPercentCappedAtTheMaximum() {
        let rect = LauncherPanelFrame.rect(mode: .centred, screen: screen, visible: visible)
        XCTAssertEqual(rect.width, LauncherPanelFrame.centredMax.width, "1368 pt of screen is capped at 1200")
        XCTAssertEqual(rect.height, LauncherPanelFrame.centredMax.height, "813.6 pt of screen is capped at 760")
        XCTAssertEqual(rect.midX, visible.midX)
        XCTAssertEqual(rect.midY, visible.midY)
        XCTAssertTrue(visible.contains(rect))
    }

    func testCentredShrinksWithTheScreen() {
        let small = CGRect(x: 0, y: 25, width: 800, height: 600)
        let rect = LauncherPanelFrame.rect(mode: .centred, screen: small, visible: small)
        XCTAssertEqual(rect.width, 640)
        XCTAssertEqual(rect.height, 480)
        XCTAssertEqual(rect.midX, small.midX)
        XCTAssertEqual(rect.midY, small.midY)
    }

    func testFloatingDockSitsBottomCentreAboveTheBottomBar() {
        let rect = LauncherPanelFrame.rect(mode: .floatingDock, screen: screen, visible: visible, dockReserve: 64)
        XCTAssertEqual(rect.width, LauncherPanelFrame.dockSize.width)
        XCTAssertEqual(rect.height, LauncherPanelFrame.dockSize.height)
        XCTAssertEqual(rect.midX, visible.midX, accuracy: 0.5)
        XCTAssertEqual(rect.minY, visible.minY + 64 + LauncherPanelFrame.margin, "it clears the KatiKati bottom bar")
        XCTAssertTrue(visible.contains(rect))
    }

    func testFloatingDockClearsSideRails() {
        let rect = LauncherPanelFrame.rect(mode: .floatingDock, screen: screen, visible: visible,
                                           leading: 300, trailing: 300)
        XCTAssertGreaterThanOrEqual(rect.minX, visible.minX + 300 + LauncherPanelFrame.margin)
        XCTAssertLessThanOrEqual(rect.maxX, visible.maxX - 300 - LauncherPanelFrame.margin)
        XCTAssertEqual(rect.midX, visible.midX, accuracy: 0.5)
    }

    func testFloatingDockFitsATinyScreen() {
        let tiny = CGRect(x: 0, y: 0, width: 400, height: 300)
        let rect = LauncherPanelFrame.rect(mode: .floatingDock, screen: tiny, visible: tiny, dockReserve: 64)
        XCTAssertLessThanOrEqual(rect.width, tiny.width * 0.8 + 0.5)
        XCTAssertLessThanOrEqual(rect.height, (tiny.height - 64) * 0.8 + 0.5)
        XCTAssertTrue(tiny.contains(rect))
    }
}
