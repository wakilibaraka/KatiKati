import CoreGraphics
import Foundation
import XCTest
@testable import KatiKati

@MainActor
final class DesktopBoxStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DesktopBoxStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    func testSaveLoadRoundTripAndBakRotation() throws {
        let url = tempDir.appendingPathComponent("desktop-boxes.json")
        let store = DesktopBoxStore(storageURL: url, debounceInterval: 0.01)

        let first = DesktopWidgetItem(title: "One", backingPath: "/tmp/one")
        store.add(first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let second = DesktopWidgetItem(title: "Two", backingPath: "/tmp/two")
        store.add(second)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("bak").path))

        let reloaded = DesktopBoxStore(storageURL: url)
        XCTAssertEqual(reloaded.recoveryState, .clean)
        XCTAssertEqual(reloaded.items.map(\.title), ["One", "Two"])
    }

    func testCorruptedPrimaryRecoversFromBackupAndPreservesCorruptCopy() throws {
        let url = tempDir.appendingPathComponent("desktop-boxes.json")
        let store = DesktopBoxStore(storageURL: url)
        store.add(DesktopWidgetItem(title: "SavedOne", backingPath: "/tmp/one"))
        store.add(DesktopWidgetItem(title: "SavedTwo", backingPath: "/tmp/two"))

        // Overwrite primary with garbage; `.bak` holds `["SavedOne"]`.
        try Data("{ broken json".utf8).write(to: url, options: .atomic)

        let recovered = DesktopBoxStore(storageURL: url)
        XCTAssertEqual(recovered.recoveryState, .recoveredFromBackup)
        XCTAssertEqual(recovered.items.map(\.title), ["SavedOne"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path))
    }

    func testStarterInboxBoxCreatesFolderOnceAndReusesExisting() throws {
        let url = tempDir.appendingPathComponent("desktop-boxes.json")
        let inbox = tempDir.appendingPathComponent("KatiKati/Inbox", isDirectory: true)
        let store = DesktopBoxStore(storageURL: url)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

        let created = try store.createStarterInboxBox(at: inbox, displayUUID: "DISP-1", visibleFrame: screen)
        XCTAssertTrue(FileManager.default.fileExists(atPath: inbox.path))
        XCTAssertEqual(created.title, "Inbox")

        let reused = try store.createStarterInboxBox(at: inbox, displayUUID: "DISP-1", visibleFrame: screen)
        XCTAssertEqual(reused.id, created.id)
        XCTAssertEqual(store.items.count, 1)
    }
}
