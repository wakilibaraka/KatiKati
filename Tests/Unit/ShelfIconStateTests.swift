import XCTest
@testable import KatiKati

final class ShelfIconStateTests: XCTestCase {
    func testIconStatesByCount() {
        XCTAssertEqual(ShelfIconState.from(count: 0), .empty)
        XCTAssertEqual(ShelfIconState.from(count: -3), .empty)
        XCTAssertEqual(ShelfIconState.from(count: 1), .onePaper)
        XCTAssertEqual(ShelfIconState.from(count: 2), .stack)
        XCTAssertEqual(ShelfIconState.from(count: 40), .stack)
    }

    func testIntroShowsOnlyOnAnUnusedEmptyShelf() {
        XCTAssertTrue(ShelfIntro.shouldShow(introSeen: false, itemCount: 0))
        XCTAssertFalse(ShelfIntro.shouldShow(introSeen: false, itemCount: 1), "existing items count as used")
        XCTAssertFalse(ShelfIntro.shouldShow(introSeen: true, itemCount: 0), "emptied after use: stays hidden")
        XCTAssertFalse(ShelfIntro.shouldShow(introSeen: true, itemCount: 5))
    }
}
