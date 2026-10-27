import XCTest
@testable import KatiKati

final class PopPolicyTests: XCTestCase {

    func testAddingAppendsInOrderAndSkipsDuplicatesAndEmpties() {
        let start: [PopItem] = [.app("com.a")]
        let result = PopPolicy.adding([.folder("/x"), .app("com.a"), .file(""), .folder("/x"), .file("/y.txt")], to: start)
        XCTAssertEqual(result.items, [.app("com.a"), .folder("/x"), .file("/y.txt")])
        XCTAssertEqual(result.rejectedForCapacity, 0)
    }

    func testSameReferenceWithDifferentKindIsADifferentItem() {
        let result = PopPolicy.adding([.file("/p"), .folder("/p")], to: [])
        XCTAssertEqual(result.items.count, 2)
    }

    func testAddingStopsAtCapacityAndCountsWhatDidNotFit() {
        let full = (0..<24).map { PopItem.file("/f\($0)") }
        let result = PopPolicy.adding([.file("/new1"), .file("/new2"), .file("/new3")], to: full)
        XCTAssertEqual(result.items.count, PopPolicy.capacity)
        XCTAssertEqual(result.items.last, .file("/new1"))
        XCTAssertEqual(result.rejectedForCapacity, 2)
    }

    func testCapacityIsTwentyFive() {
        XCTAssertEqual(PopPolicy.capacity, 25)
    }

    func testRemovingDropsOnlyThatItem() {
        let items: [PopItem] = [.app("com.a"), .folder("/x")]
        XCTAssertEqual(PopPolicy.removing(PopItem.app("com.a").id, from: items), [.folder("/x")])
    }

    func testReorderingMovesBeforeAndAfter() {
        let a = PopItem.app("a"), b = PopItem.app("b"), c = PopItem.app("c")
        XCTAssertEqual(PopPolicy.reordering([a, b, c], draggedID: a.id, relativeTo: c.id, after: true), [b, c, a])
        XCTAssertEqual(PopPolicy.reordering([a, b, c], draggedID: c.id, relativeTo: a.id, after: false), [c, a, b])
        XCTAssertEqual(PopPolicy.reordering([a, b, c], draggedID: a.id, relativeTo: a.id, after: true), [a, b, c])
        XCTAssertEqual(PopPolicy.reordering([a, b, c], draggedID: "missing", relativeTo: a.id, after: true), [a, b, c])
    }

    func testMigratingKeepsStoredOrderThenAppendsUnorderedMembers() {
        let items = PopPolicy.migrating(legacyBundleIDs: ["a", "b", "c", "", "b"], legacyOrder: ["c", "gone", "a"])
        XCTAssertEqual(items, [.app("c"), .app("a"), .app("b")])
    }

    func testMigratingDoesNotTruncateOverCapacity() {
        let ids = (0..<30).map { "app\($0)" }
        XCTAssertEqual(PopPolicy.migrating(legacyBundleIDs: ids, legacyOrder: []).count, 30)
        XCTAssertEqual(PopPolicy.adding([.app("one-more")], to: PopPolicy.migrating(legacyBundleIDs: ids, legacyOrder: [])).rejectedForCapacity, 1)
    }

    func testClassifyingDroppedPaths() {
        XCTAssertEqual(PopPolicy.item(forPath: "/Applications/Safari.app", isDirectory: true, bundleID: "com.apple.Safari"), .app("com.apple.Safari"))
        XCTAssertEqual(PopPolicy.item(forPath: "/Applications/Odd.app", isDirectory: true, bundleID: nil), .file("/Applications/Odd.app"))
        XCTAssertEqual(PopPolicy.item(forPath: "/Users/me/Projects", isDirectory: true, bundleID: nil), .folder("/Users/me/Projects"))
        XCTAssertEqual(PopPolicy.item(forPath: "/Users/me/a.pdf", isDirectory: false, bundleID: nil), .file("/Users/me/a.pdf"))
        XCTAssertNil(PopPolicy.item(forPath: "", isDirectory: false, bundleID: nil))
    }
}
