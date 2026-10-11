import XCTest
@testable import KatiKati

final class LauncherStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("launcher-\(UUID().uuidString)/launcher.json")
    }

    func testRoundTrip() throws {
        let store = LauncherStore(url: tempURL())
        let state = LauncherState(usage: ["a": LauncherUsage(launches: 3, lastLaunched: Date(timeIntervalSince1970: 1_700_000_000))], pinned: ["a", "b"])
        try store.save(state)
        XCTAssertEqual(store.load(), state)
    }

    func testMissingFileIsEmpty() {
        XCTAssertEqual(LauncherStore(url: tempURL()).load(), LauncherState())
    }

    func testCorruptFileIsMovedAside() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: url)
        XCTAssertEqual(LauncherStore(url: url).load(), LauncherState())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("bak").path))
    }

    func testScanFindsSystemApps() {
        let apps = LauncherIndexer.scanDirectories()
        XCTAssertTrue(apps.contains { $0.bundleID == "com.apple.calculator" },
                      "found \(apps.count): \(apps.prefix(5).map(\.bundleID))")
    }
}
