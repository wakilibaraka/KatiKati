import XCTest

final class DesktopManagedStorageTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("katikati-managed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testCopyFirstVerifiedMigrationPreservesSourceAndMatchesManifest() throws {
        let source = tempRoot.appendingPathComponent("SourceFolder", isDirectory: true)
        let sub = source.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        let payloadA = Data("hello world".utf8)
        let payloadB = Data(repeating: 42, count: 512)
        try payloadA.write(to: source.appendingPathComponent("a.txt"))
        try payloadB.write(to: sub.appendingPathComponent("b.bin"))

        let managedRoot = tempRoot.appendingPathComponent("ManagedBoxes", isDirectory: true)
        let boxID = UUID()
        let report = try DesktopManagedStorage.migrateToManagedStorage(
            from: source,
            boxID: boxID,
            rootURL: managedRoot
        )

        XCTAssertTrue(report.sourcePreserved)
        XCTAssertEqual(report.verifiedFileCount, 2)
        XCTAssertEqual(report.verifiedTotalBytes, Int64(payloadA.count + payloadB.count))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("a.txt").path))
        XCTAssertEqual(try Data(contentsOf: report.destinationURL.appendingPathComponent("a.txt")), payloadA)
        XCTAssertEqual(try Data(contentsOf: report.destinationURL.appendingPathComponent("Nested/b.bin")), payloadB)
    }

    func testOverlapSourceAndDestinationThrowsInvalidTargetOverlap() throws {
        let source = tempRoot.appendingPathComponent("Outer", isDirectory: true)
        let nestedRoot = source.appendingPathComponent("ManagedBoxes", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedRoot, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try DesktopManagedStorage.migrateToManagedStorage(from: source, boxID: UUID(), rootURL: nestedRoot)
        ) { error in
            XCTAssertEqual(error as? DesktopMigrationError, .invalidTargetOverlap)
        }
    }

    func testExportManagedBoxCopiesAndCleanupRemovesOnlyStaging() throws {
        let managedRoot = tempRoot.appendingPathComponent("Managed", isDirectory: true)
        let boxDir = try DesktopManagedStorage.createManagedBoxDirectory(rootURL: managedRoot)
        let noteURL = boxDir.appendingPathComponent("note.md")
        try Data("# Memo".utf8).write(to: noteURL)

        let staging = managedRoot.appendingPathComponent("abc.staging-123", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        DesktopManagedStorage.cleanupOrphanedStagingDirectories(in: managedRoot)

        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: boxDir.path))

        let exportParent = tempRoot.appendingPathComponent("Exports", isDirectory: true)
        let report = try DesktopManagedStorage.exportManagedBox(from: boxDir, to: exportParent)
        XCTAssertEqual(report.verifiedFileCount, 1)
        XCTAssertEqual(try Data(contentsOf: report.destinationURL.appendingPathComponent("note.md")), Data("# Memo".utf8))
    }
}
