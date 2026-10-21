import CoreGraphics
import XCTest
@testable import KatiKati

/// 57b: the launcher's three panel shapes, checked without opening a window.
final class LauncherPresentationTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1710, height: 1112)
    private let visible = CGRect(x: 0, y: 70, width: 1710, height: 1017)

    func testStoredValueFallsBackToFullscreen() {
        XCTAssertEqual(LauncherPresentation.parse(nil), .fullscreen)
        XCTAssertEqual(LauncherPresentation.parse("nonsense"), .fullscreen)
        XCTAssertEqual(LauncherPresentation.parse("centred"), .centred)
        XCTAssertEqual(LauncherPresentation.parse("popover"), .popover)
    }

    func testFullscreenIsExactlyTheScreen() {
        XCTAssertEqual(LauncherPanelFrame.rect(mode: .fullscreen, screen: screen, visible: visible, anchor: .zero), screen)
    }

    func testCentredIsEightyPercentCappedAtTheMaximum() {
        let rect = LauncherPanelFrame.rect(mode: .centred, screen: screen, visible: visible, anchor: nil)
        XCTAssertEqual(rect.width, LauncherPanelFrame.centredMax.width, "1368 pt of screen is capped at 1200")
        XCTAssertEqual(rect.height, LauncherPanelFrame.centredMax.height, "813.6 pt of screen is capped at 760")
        XCTAssertEqual(rect.midX, visible.midX)
        XCTAssertEqual(rect.midY, visible.midY)
        XCTAssertTrue(visible.contains(rect))
    }

    func testCentredShrinksWithTheScreen() {
        let small = CGRect(x: 0, y: 25, width: 800, height: 600)
        let rect = LauncherPanelFrame.rect(mode: .centred, screen: small, visible: small, anchor: nil)
        XCTAssertEqual(rect.width, 640)
        XCTAssertEqual(rect.height, 480)
        XCTAssertEqual(rect.midX, small.midX)
        XCTAssertEqual(rect.midY, small.midY)
    }

    func testPopoverHangsUnderTheAnchorAndStaysOnScreen() {
        let pointer = CGPoint(x: 1700, y: 900)  // well above the bottom edge, hard against the right one
        let rect = LauncherPanelFrame.rect(mode: .popover, screen: screen, visible: visible, anchor: pointer)
        XCTAssertEqual(rect.width, LauncherPanelFrame.popoverSize.width)
        XCTAssertEqual(rect.height, LauncherPanelFrame.popoverSize.height)
        XCTAssertEqual(rect.maxY, pointer.y - LauncherPanelFrame.popoverGap, "it hangs under the pointer")
        XCTAssertTrue(visible.contains(rect), "\(rect) must stay inside \(visible)")
        XCTAssertEqual(rect.maxX, visible.maxX - LauncherPanelFrame.margin, "pulled back from the right edge")

        // An anchor at the bottom of the screen has no room below it: the card moves up, still inside.
        let low = LauncherPanelFrame.rect(mode: .popover, screen: screen, visible: visible,
                                          anchor: CGPoint(x: 400, y: 40))
        XCTAssertEqual(low.minY, visible.minY + LauncherPanelFrame.margin)
        XCTAssertTrue(visible.contains(low))
    }

    func testPopoverCentresOnATopAnchor() {
        let rect = LauncherPanelFrame.rect(mode: .popover, screen: screen, visible: visible,
                                           anchor: CGPoint(x: visible.midX, y: visible.maxY))
        XCTAssertEqual(rect.midX, visible.midX)
        XCTAssertEqual(rect.maxY, visible.maxY - LauncherPanelFrame.popoverGap, "it keeps its gap under the anchor")
    }

    func testPopoverFitsATinyScreen() {
        let tiny = CGRect(x: 0, y: 0, width: 400, height: 300)
        let rect = LauncherPanelFrame.rect(mode: .popover, screen: tiny, visible: tiny, anchor: .zero)
        XCTAssertEqual(rect.width, 400 - 2 * LauncherPanelFrame.margin)
        XCTAssertEqual(rect.height, 300 - 2 * LauncherPanelFrame.margin)
        XCTAssertTrue(tiny.contains(rect))
    }
}
