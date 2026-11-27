import XCTest
@testable import KatiKati

final class EdgeInsertIndexTests: XCTestCase {
    func testIndexForYResolvesTopMiddleBottomAndEmpty() {
        XCTAssertEqual(EdgeInsertIndex.index(forY: 12, itemMidYs: []), 0)
        let mids: [CGFloat] = [20, 60, 100]
        XCTAssertEqual(EdgeInsertIndex.index(forY: 5, itemMidYs: mids), 0)
        XCTAssertEqual(EdgeInsertIndex.index(forY: 35, itemMidYs: mids), 1)
        XCTAssertEqual(EdgeInsertIndex.index(forY: 85, itemMidYs: mids), 2)
        XCTAssertEqual(EdgeInsertIndex.index(forY: 120, itemMidYs: mids), 3)
    }

    func testCustomOrderApplyInsertAndRemoveKeepSettingsPinned() {
        let base: [EdgeItem] = [.apps, .clock, .habits, .settings]
        let reordered = EdgeCustomOrder.apply(order: ["habits", "apps"], to: base)
        XCTAssertEqual(reordered, [.habits, .apps, .clock, .settings])

        let inserted = EdgeCustomOrder.inserting(.focus, at: 1, in: reordered)
        XCTAssertEqual(inserted, [.habits, .focus, .apps, .clock, .settings])

        let moved = EdgeCustomOrder.inserting(.apps, at: 99, in: inserted)
        XCTAssertEqual(moved, [.habits, .focus, .clock, .apps, .settings])

        XCTAssertEqual(EdgeCustomOrder.removing(.focus, in: moved), [.habits, .clock, .apps, .settings])
        XCTAssertEqual(EdgeCustomOrder.removing(.settings, from: moved), moved)
    }

    func testSpotlightPolicyRespectsReduceMotionAndDimsSiblings() {
        XCTAssertEqual(EdgeSpotlightPolicy.scale(hoveredID: "habits", itemID: "habits", reduceMotion: false), 1.04)
        XCTAssertEqual(EdgeSpotlightPolicy.scale(hoveredID: "habits", itemID: "clock", reduceMotion: false), 0.98)
        XCTAssertEqual(EdgeSpotlightPolicy.scale(hoveredID: "habits", itemID: "habits", reduceMotion: true), 1.0)
        XCTAssertEqual(EdgeSpotlightPolicy.opacity(hoveredID: "habits", itemID: "clock"), 0.85)
        XCTAssertEqual(EdgeSpotlightPolicy.opacity(hoveredID: nil, itemID: "clock"), 1.0)
    }
}
