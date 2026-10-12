import XCTest
@testable import KatiKati

final class ShelfPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func item(_ p: String, pinned: Bool = false, age: TimeInterval = 0) -> ShelfItem {
        ShelfItem(path: p, isPinned: pinned, addedAt: t0.addingTimeInterval(-age))
    }

    func testOrderPinnedFirstThenNewest() {
        let items = [item("/old", age: 100), item("/pin", pinned: true, age: 500), item("/new", age: 1)]
        XCTAssertEqual(ShelfPolicy.ordered(items).map(\.path), ["/pin", "/new", "/old"])
    }

    func testStashDedupesAndRefreshesButKeepsPin() {
        let base = [item("/a", pinned: true, age: 900)]
        let out = ShelfPolicy.stashing(base, adding: [("/a", false), ("/b", false), ("/b", false), ("", false)], now: t0)
        XCTAssertEqual(out.map(\.path), ["/a", "/b"])
        XCTAssertTrue(out[0].isPinned)
        XCTAssertEqual(out[0].addedAt, t0)
    }

    func testTogglePinAndRemove() {
        let a = item("/a"), b = item("/b")
        let pinned = ShelfPolicy.togglingPin([a, b], id: a.id)
        XCTAssertTrue(pinned[0].isPinned); XCTAssertFalse(pinned[1].isPinned)
        XCTAssertEqual(ShelfPolicy.removing(pinned, path: "/a").map(\.path), ["/b"])
    }

    func testExpiryDropsOnlyOldUnpinned() {
        let day: TimeInterval = 86_400
        let items = [item("/fresh", age: day / 2), item("/stale", age: 2 * day), item("/pinned-stale", pinned: true, age: 9 * day)]
        let r = ShelfPolicy.expired(items, now: t0, days: 1)
        XCTAssertEqual(r.kept.map(\.path), ["/fresh", "/pinned-stale"])
        XCTAssertEqual(r.dropped.map(\.path), ["/stale"])
    }

    func testClearUnpinnedKeepsPinned() {
        let r = ShelfPolicy.clearingUnpinned([item("/a"), item("/b", pinned: true)])
        XCTAssertEqual(r.kept.map(\.path), ["/b"]); XCTAssertEqual(r.dropped.map(\.path), ["/a"])
    }

    func testMigrationKeepsNewestFirstOrder() {
        let m = ShelfPolicy.migrated(paths: ["/newest", "/older", "/oldest"], now: t0)
        XCTAssertEqual(ShelfPolicy.ordered(m).map(\.path), ["/newest", "/older", "/oldest"])
        XCTAssertTrue(m.allSatisfy { !$0.isPinned })
    }
}
