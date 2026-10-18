import XCTest

final class StorageScanMathTests: XCTestCase {
    private func item(_ path: String, _ bytes: Int64) -> StorageItem { StorageItem(path: path, bytes: bytes) }

    func testTopSortsBiggestFirstAndDropsEmpty() {
        let top = StorageScanMath.top([item("/a", 5), item("/b", 0), item("/c", 9), item("/d", 7)], limit: 2)
        XCTAssertEqual(top.map(\.path), ["/c", "/d"])
    }

    func testTiesKeepPathOrderAndZeroLimitIsEmpty() {
        XCTAssertEqual(StorageScanMath.top([item("/b", 3), item("/a", 3)], limit: 5).map(\.path), ["/a", "/b"])
        XCTAssertTrue(StorageScanMath.top([item("/a", 3)], limit: 0).isEmpty)
    }

    func testShareIsRelativeToLargest() {
        let big = item("/big", 200)
        XCTAssertEqual(StorageScanMath.share(item("/x", 50), of: big), 0.25)
        XCTAssertEqual(StorageScanMath.share(big, of: big), 1)
        XCTAssertEqual(StorageScanMath.share(big, of: nil), 0)
    }

    func testSystemAndVirtualTreesAreNotScanned() {
        XCTAssertFalse(StorageScanMath.isScannable("/System/Library"))
        XCTAssertFalse(StorageScanMath.isScannable("/Volumes"))
        XCTAssertTrue(StorageScanMath.isScannable("/Users/me/Library"))
        XCTAssertTrue(StorageScanMath.isScannable("/SystemExtras"), "prefix match must respect the path boundary")
    }

    func testCompactLabelFitsTheClosedSlot() {
        XCTAssertEqual(StorageScanMath.compact(29_590_000_000), "29 GB")
        XCTAssertEqual(StorageScanMath.compact(1_250_000_000_000), "1.2 TB")
        XCTAssertEqual(StorageScanMath.compact(-5), "0 GB")
    }

    func testNameIsLastComponent() {
        XCTAssertEqual(item("/Users/me/Movies", 1).name, "Movies")
    }
}
