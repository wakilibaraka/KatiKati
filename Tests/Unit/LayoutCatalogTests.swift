import XCTest
@testable import KatiKati

final class LayoutCatalogTests: XCTestCase {
    private let area = CGRect(x: 0, y: 40, width: 1440, height: 860)
    private let gaps = TilingGaps(inner: 8, outer: 8)
    private let ids = (1...6).map { WindowID(rawValue: "w\($0)") }

    func testSlotsPutTheFocusedWindowFirst() {
        let focused = ids[3]
        let ordered = LayoutCatalogSlots.ordered(ids, focused: focused)
        XCTAssertEqual(ordered.first, focused)
        XCTAssertEqual(ordered.count, ids.count)
        // Everything else keeps the order the windows joined in.
        XCTAssertEqual(Array(ordered.dropFirst()), ids.filter { $0 != focused })
    }

    func testSlotsWithoutAFocusedWindowKeepJoinOrder() {
        XCTAssertEqual(LayoutCatalogSlots.ordered(ids, focused: nil), ids)
        XCTAssertEqual(LayoutCatalogSlots.ordered(ids, focused: WindowID(rawValue: "absent")), ids)
    }

    func testExtraWindowsAreParkedNotTiled() {
        for layout in LayoutCatalog.allCases {
            let frames = layout.frames(for: ids, workArea: area, gaps: gaps)
            XCTAssertEqual(frames.count, layout.slots, "\(layout)")
        }
    }

    func testFewerWindowsThanSlotsStillFillTheirSlots() {
        let frames = LayoutCatalog.quarters.frames(for: Array(ids.prefix(2)), workArea: area, gaps: gaps)
        XCTAssertEqual(frames.count, 2)
    }

    func testTilesNeverOverlap() {
        for layout in LayoutCatalog.allCases {
            let rects = Array(layout.frames(for: ids, workArea: area, gaps: gaps).values)
            for i in rects.indices {
                for j in rects.indices where j > i {
                    // monocle layouts stack on purpose
                    if layout.preset == .monocle { continue }
                    XCTAssertTrue(rects[i].intersection(rects[j]).isNull || rects[i].intersection(rects[j]).isEmpty,
                                  "\(layout) overlaps")
                }
            }
        }
    }

    func testMainRightPutsTheMainWindowOnTheRight() {
        let frames = LayoutCatalog.mainRight.frames(for: Array(ids.prefix(3)), workArea: area, gaps: gaps)
        XCTAssertGreaterThan(frames[ids[0]]!.minX, frames[ids[1]]!.minX)
    }

    func testStagedLeavesSpaceAroundTheWindow() {
        let frame = LayoutCatalog.staged.frames(for: [ids[0]], workArea: area, gaps: gaps)[ids[0]]!
        XCTAssertGreaterThan(frame.minX, area.minX + 100)
    }
}
