import XCTest
@testable import KatiKati

// Phase 8a — recently-closed ordering, dedupe, cap and exclusion.

final class RecentlyClosedListTests: XCTestCase {
    func testNewestFirstAndDeduped() {
        var l = RecentlyClosedList()
        l.noteClosed("a"); l.noteClosed("b"); l.noteClosed("a")
        XCTAssertEqual(l.bundleIDs, ["a", "b"])
    }

    func testCappedAtCapacityDroppingOldest() {
        var l = RecentlyClosedList()
        for i in 0..<12 { l.noteClosed("app\(i)") }
        XCTAssertEqual(l.bundleIDs.count, RecentlyClosedList.capacity)
        XCTAssertEqual(l.bundleIDs.first, "app11")
        XCTAssertFalse(l.bundleIDs.contains("app0"))
    }

    func testLaunchRemovesAndEmptyIDsIgnored() {
        var l = RecentlyClosedList(bundleIDs: ["a", "b", "c"])
        l.noteLaunched("b"); l.noteClosed("")
        XCTAssertEqual(l.bundleIDs, ["a", "c"])
    }

    func testRestoredListIsSanitised() {
        let l = RecentlyClosedList(bundleIDs: ["a", "", "a", "b"])
        XCTAssertEqual(l.bundleIDs, ["a", "b"])
    }

    func testVisibleExcludesRunningOrBlocked() {
        let l = RecentlyClosedList(bundleIDs: ["a", "b", "c"])
        XCTAssertEqual(l.visible(excluding: ["b"]), ["a", "c"])
    }
}
