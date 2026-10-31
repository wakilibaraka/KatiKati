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

    func testScanFindsNestedAndMenuBarAppsWithoutEnteringBundles() throws {
        let root = tempURL().deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: root) }
        func makeApp(_ path: String, id: String, agent: Bool = false, background: Bool = false) throws {
            let contents = root.appendingPathComponent(path).appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let info: [String: Any] = ["CFBundleIdentifier": id, "CFBundlePackageType": "APPL",
                                       "LSUIElement": agent, "LSBackgroundOnly": background]
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
        }
        try makeApp("Vendor/Tool.app", id: "test.tool", agent: true)
        try makeApp("Vendor/Helper.app", id: "test.helper", background: true)
        try makeApp("Vendor/Tool.app/Contents/Nested.app", id: "test.nested")
        let ids = Set(LauncherIndexer.scanDirectories(roots: [root.path]).map(\.bundleID))
        XCTAssertEqual(ids, ["test.tool"])
    }

    func testOldFileWithoutHiddenAndOrderStillLoads() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"usage":{},"pinned":["a"]}"#.utf8).write(to: url)
        XCTAssertEqual(LauncherStore(url: url).load(), LauncherState(pinned: ["a"]))
    }

    func testHiddenAndOrderRoundTrip() throws {
        let url = tempURL()
        let store = LauncherStore(url: url)
        try store.save(LauncherState(hidden: ["x"], order: ["b", "a"]))
        XCTAssertEqual(store.load().hidden, ["x"])
        XCTAssertEqual(store.load().order, ["b", "a"])
    }
}
