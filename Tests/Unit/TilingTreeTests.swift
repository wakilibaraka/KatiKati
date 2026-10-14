import XCTest
@testable import KatiKati

final class TilingTreeTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 40, width: 1440, height: 860)
    private let defaultGaps = TilingGaps(inner: 8, outer: 8)

    // MARK: - Basic Operations

    func testEmptyTree() {
        let tree = TilingTree()
        XCTAssertTrue(tree.isEmpty)
        XCTAssertEqual(tree.count, 0)
        XCTAssertNil(tree.focusedID)
        XCTAssertEqual(tree.resolveTiles(in: screen), [:])
    }

    func testSingleWindowFillsWorkAreaMinusOuterGaps() {
        var tree = TilingTree()
        let w1 = WindowID(rawValue: "w1")
        tree.insert(w1)

        XCTAssertFalse(tree.isEmpty)
        XCTAssertEqual(tree.count, 1)
        XCTAssertEqual(tree.focusedID, w1)
        XCTAssertTrue(tree.contains(w1))

        let tiles = tree.resolveTiles(in: screen, gaps: defaultGaps)
        XCTAssertEqual(tiles.count, 1)

        let expected = CGRect(
            x: screen.minX + 8,
            y: screen.minY + 8,
            width: screen.width - 16,
            height: screen.height - 16
        )
        XCTAssertEqual(tiles[w1], expected)
    }

    func testTwoWindowsSplitHorizontallyWithInnerGap() {
        var tree = TilingTree()
        let w1 = WindowID(rawValue: "w1")
        let w2 = WindowID(rawValue: "w2")
        tree.insert(w1)
        tree.insert(w2)

        XCTAssertEqual(tree.count, 2)
        XCTAssertEqual(tree.focusedID, w2)

        let tiles = tree.resolveTiles(in: screen, gaps: defaultGaps)
        XCTAssertEqual(tiles.count, 2)

        guard let r1 = tiles[w1], let r2 = tiles[w2] else {
            XCTFail("Missing tile frames")
            return
        }

        // Left and right tiles
        XCTAssertEqual(r1.minX, screen.minX + 8)
        XCTAssertEqual(r2.maxX, screen.maxX - 8)
        XCTAssertEqual(r1.maxX + 8, r2.minX, "Inner gap of 8pt separates the two tiles")
        XCTAssertEqual(r1.minY, screen.minY + 8)
        XCTAssertEqual(r2.minY, screen.minY + 8)
        XCTAssertEqual(r1.height, screen.height - 16)
        XCTAssertEqual(r2.height, screen.height - 16)
        XCTAssertFalse(r1.intersects(r2), "Tiles must not overlap")
    }

    func testThreeWindowsAlternatesSplitByDepth() {
        var tree = TilingTree()
        let w1 = WindowID(rawValue: "w1")
        let w2 = WindowID(rawValue: "w2")
        let w3 = WindowID(rawValue: "w3")
        tree.insert(w1) // depth 0: root
        tree.insert(w2) // depth 1: root splits horizontally, w2 focused
        tree.insert(w3) // depth 1 split: splits w2 vertically (depth 1 is odd -> vertical)

        XCTAssertEqual(tree.count, 3)
        let tiles = tree.resolveTiles(in: screen, gaps: defaultGaps)
        XCTAssertEqual(tiles.count, 3)

        guard let r1 = tiles[w1], let r2 = tiles[w2], let r3 = tiles[w3] else {
            XCTFail("Missing tiles")
            return
        }

        // No tile should overlap any other tile
        XCTAssertFalse(r1.intersects(r2))
        XCTAssertFalse(r1.intersects(r3))
        XCTAssertFalse(r2.intersects(r3))

        // w2 and w3 share the right column
        XCTAssertEqual(r2.minX, r3.minX)
        XCTAssertEqual(r2.width, r3.width)
        // w2 (top) and w3 (bottom) are stacked with an inner gap
        XCTAssertEqual(r3.maxY + 8, r2.minY, "Vertical inner gap between stacked tiles")
    }

    // MARK: - Removal

    func testRemoveWindowExpandsSibling() {
        var tree = TilingTree()
        let w1 = WindowID(rawValue: "w1")
        let w2 = WindowID(rawValue: "w2")
        tree.insert(w1)
        tree.insert(w2)

        tree.remove(w2)
        XCTAssertEqual(tree.count, 1)
        XCTAssertEqual(tree.allWindowIDs, [w1])
        XCTAssertEqual(tree.focusedID, w1)

        let tiles = tree.resolveTiles(in: screen, gaps: defaultGaps)
        let expected = CGRect(
            x: screen.minX + 8,
            y: screen.minY + 8,
            width: screen.width - 16,
            height: screen.height - 16
        )
        XCTAssertEqual(tiles[w1], expected)
    }

    func testRemoveAllLeavesTreeEmpty() {
        var tree = TilingTree()
        let w1 = WindowID(rawValue: "w1")
        tree.insert(w1)
        XCTAssertTrue(tree.remove(w1))
        XCTAssertTrue(tree.isEmpty)
        XCTAssertNil(tree.focusedID)
    }

    // MARK: - Focus & Swap

    func testFocusCycle() {
        var tree = TilingTree()
        let w1 = WindowID(rawValue: "w1")
        let w2 = WindowID(rawValue: "w2")
        let w3 = WindowID(rawValue: "w3")
        tree.insert(w1)
        tree.insert(w2)
        tree.insert(w3)

        XCTAssertEqual(tree.focusedID, w3)
        tree.focusNext()
        XCTAssertEqual(tree.focusedID, w1)
        tree.focusNext()
        XCTAssertEqual(tree.focusedID, w2)
        tree.focusPrevious()
        XCTAssertEqual(tree.focusedID, w1)
    }

    func testSwapWindowsPreservesGeometry() {
        var tree = TilingTree()
        let w1 = WindowID(rawValue: "w1")
        let w2 = WindowID(rawValue: "w2")
        tree.insert(w1)
        tree.insert(w2)

        let before = tree.resolveTiles(in: screen, gaps: defaultGaps)
        tree.swap(w1, with: w2)
        let after = tree.resolveTiles(in: screen, gaps: defaultGaps)

        XCTAssertEqual(before[w1], after[w2])
        XCTAssertEqual(before[w2], after[w1])
    }

    // MARK: - Invariants

    func testNoOverlapAcrossFourWindows() {
        var tree = TilingTree()
        let ids = (1...4).map { WindowID(rawValue: "w\($0)") }
        ids.forEach { tree.insert($0) }

        let tiles = tree.resolveTiles(in: screen, gaps: defaultGaps)
        XCTAssertEqual(tiles.count, 4)

        for i in 0..<ids.count {
            for j in (i + 1)..<ids.count {
                let rA = tiles[ids[i]]!
                let rB = tiles[ids[j]]!
                XCTAssertFalse(rA.intersects(rB), "Windows \(ids[i].rawValue) and \(ids[j].rawValue) must not overlap")
            }
        }
    }

    func testAllTilesContainedWithinWorkArea() {
        var tree = TilingTree()
        for i in 1...6 {
            tree.insert(WindowID(rawValue: "w\(i)"))
        }

        let tiles = tree.resolveTiles(in: screen, gaps: defaultGaps)
        for (id, frame) in tiles {
            XCTAssertGreaterThanOrEqual(frame.minX, screen.minX, "\(id) within minX")
            XCTAssertGreaterThanOrEqual(frame.minY, screen.minY, "\(id) within minY")
            XCTAssertLessThanOrEqual(frame.maxX, screen.maxX, "\(id) within maxX")
            XCTAssertLessThanOrEqual(frame.maxY, screen.maxY, "\(id) within maxY")
        }
    }

    func testDuplicateInsertIsNoOp() {
        var tree = TilingTree()
        let w1 = WindowID(rawValue: "w1")
        tree.insert(w1)
        tree.insert(w1)
        XCTAssertEqual(tree.count, 1)
    }
}
