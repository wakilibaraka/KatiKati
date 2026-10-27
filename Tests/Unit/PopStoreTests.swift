import XCTest
@testable import KatiKati

@MainActor
final class PopStoreTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        TestDefaults.make("test-pop-store", for: self)
    }

    func testFirstLaunchMigratesLegacyDrawerInDisplayOrderAndKeepsLegacyKeys() {
        let defaults = makeDefaults()
        defaults.set(["com.a", "com.b", "com.c"], forKey: "drawerBundleIDs")
        defaults.set(["com.c", "com.a"], forKey: "drawerDisplayOrder")

        let store = PopStore(defaults: defaults)

        XCTAssertEqual(store.items, [.app("com.c"), .app("com.a"), .app("com.b")])
        XCTAssertEqual(defaults.stringArray(forKey: "drawerBundleIDs"), ["com.a", "com.b", "com.c"])
    }

    func testStoredItemsWinOverLegacyKeysOnLaterLaunches() {
        let defaults = makeDefaults()
        let store = PopStore(defaults: defaults)
        store.add([.folder("/Users/me/Projects")])
        defaults.set(["com.late"], forKey: "drawerBundleIDs")

        XCTAssertEqual(PopStore(defaults: defaults).items, [.folder("/Users/me/Projects")])
    }

    func testAddRemoveReorderPersist() {
        let defaults = makeDefaults()
        let store = PopStore(defaults: defaults)
        store.add([.app("com.a"), .file("/x.pdf"), .folder("/y")])
        store.reorder(draggedID: PopItem.folder("/y").id, relativeTo: PopItem.app("com.a").id, after: false)
        store.remove(PopItem.file("/x.pdf").id)

        XCTAssertEqual(PopStore(defaults: defaults).items, [.folder("/y"), .app("com.a")])
    }

    func testAddPastCapacityReportsRejectedCount() {
        let store = PopStore(defaults: makeDefaults())
        store.add((0..<26).map { PopItem.file("/f\($0)") })

        XCTAssertTrue(store.isFull)
        XCTAssertEqual(store.items.count, PopPolicy.capacity)
        XCTAssertEqual(store.lastRejectedForCapacity, 1)
    }
}
