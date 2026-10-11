import XCTest
@testable import KatiKati

final class WindowLiftRecoveryTests: XCTestCase {
    private func entry(_ pid: Int32 = 42) -> WindowLiftRecoveryEntry {
        WindowLiftRecoveryEntry(
            pid: pid, windowID: 7, startSeconds: 1_700_000_000, startMicroseconds: 12,
            nativeAppKit: .init(x: 0, y: 0, width: 1728, height: 1074),
            targetAppKit: .init(x: 0, y: 56, width: 1728, height: 1018),
            nativeQuartz: .init(x: 0, y: 38, width: 1728, height: 1074),
            targetQuartz: .init(x: 0, y: 38, width: 1728, height: 1018),
            primaryScreenHeight: 1112
        )
    }

    private func tempStore() -> WindowLiftRecoveryStore {
        WindowLiftRecoveryStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("lift-recovery-\(UUID().uuidString)/r.json"))
    }

    func testRoundTrip() {
        let store = tempStore()
        store.save([entry(1), entry(2)])
        XCTAssertEqual(store.load(), [entry(1), entry(2)])
        store.clear()
    }

    func testEmptySaveDeletesFile() {
        let store = tempStore()
        store.save([entry()])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url.path))
        store.save([])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
        XCTAssertTrue(store.load().isEmpty)
    }

    func testCorruptOrWrongVersionLoadsEmpty() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: store.url)
        XCTAssertTrue(store.load().isEmpty)
        var snapshot = WindowLiftRecoverySnapshot(entries: [entry()])
        snapshot.version = 99
        try snapshot.encoded()!.write(to: store.url)
        XCTAssertTrue(store.load().isEmpty)
        store.clear()
    }

    func testRectConversion() {
        let r = CGRect(x: 1, y: 2, width: 3, height: 4)
        XCTAssertEqual(WindowLiftRecoveryRect(r).cgRect, r)
    }
}
