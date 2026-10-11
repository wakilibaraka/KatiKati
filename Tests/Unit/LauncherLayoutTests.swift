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
}
