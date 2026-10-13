import XCTest
@testable import KatiKati

final class LauncherLayoutTests: XCTestCase {
    func testDefaultsToTopAndRejectsGarbage() {
        XCTAssertEqual(LauncherSearchPosition.default, .top)
        XCTAssertEqual(LauncherSearchPosition.parse(nil), .top)
        XCTAssertEqual(LauncherSearchPosition.parse("middle"), .top)
        XCTAssertEqual(LauncherSearchPosition.parse("bottom"), .bottom)
    }

    func testFrozenRawValues() {
        XCTAssertEqual(LauncherSearchPosition.allCases.map(\.rawValue), ["top", "bottom", "left", "right"])
    }

    func testInsetsReserveFieldAndSheet() {
        let a = LauncherSearchPosition.top.reservedInsets(sheetSide: .right)
        XCTAssertEqual(a.top, 56); XCTAssertEqual(a.trailing, 328); XCTAssertEqual(a.leading, 0)
        let b = LauncherSearchPosition.right.reservedInsets(sheetSide: .right)
        XCTAssertEqual(b.trailing, 628, "side field stacks beside the sheet on the same side")
        let c = LauncherSearchPosition.left.reservedInsets(sheetSide: .right)
        XCTAssertEqual(c.leading, 300); XCTAssertEqual(c.trailing, 328)
    }

    func testSideFieldIsNarrower() {
        XCTAssertLessThan(LauncherSearchPosition.left.fieldWidth, LauncherSearchPosition.top.fieldWidth)
    }

    func testScreenInsetsKeepClearOfNotchMenuBarAndDock() {
        let frame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let visible = CGRect(x: 0, y: 70, width: 1728, height: 1010) // dock 70 below, menu bar 37 above
        let i = LauncherScreenInsets.compute(frame: frame, visible: visible, safeTop: 32)
        XCTAssertEqual(i.top, 37); XCTAssertEqual(i.bottom, 70); XCTAssertEqual(i.leading, 0); XCTAssertEqual(i.trailing, 0)
        let notchOnly = LauncherScreenInsets.compute(frame: frame, visible: frame, safeTop: 38)
        XCTAssertEqual(notchOnly.top, 38, "notch inset wins when the menu bar is hidden")
    }

    func testScreenInsetsAreClamped() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 900)
        let i = LauncherScreenInsets.compute(frame: frame, visible: CGRect(x: 0, y: 800, width: 1000, height: 100), safeTop: 0)
        XCTAssertEqual(i.bottom, 300, "never more than a third of the screen")
    }

    /// Phase 18d: a side rail pushes the launcher grid in from its edge.
    func testSideRailReservesLeadingOrTrailingSpace() {
        let frame = CGRect(x: 0, y: 0, width: 1500, height: 900)
        let i = LauncherScreenInsets.compute(frame: frame, visible: frame, safeTop: 0, extraLeading: 70)
        XCTAssertEqual(i.leading, 70)
        XCTAssertEqual(i.trailing, 0)
        let j = LauncherScreenInsets.compute(frame: frame, visible: frame, safeTop: 0, extraTrailing: 70)
        XCTAssertEqual(j.trailing, 70)
    }
}

