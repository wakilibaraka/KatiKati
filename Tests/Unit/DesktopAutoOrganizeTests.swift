import XCTest

final class DesktopAutoOrganizeTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("katikati-organize-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testBuildPlanSkipsDotfilesAndFoldersWhenDisabled() {
        let source = URL(fileURLWithPath: "/tmp/Desktop", isDirectory: true)
        let dest = URL(fileURLWithPath: "/tmp/Organized", isDirectory: true)
        let entries = [
            FolderContentsLoader.Entry(url: source.appendingPathComponent(".DS_Store"), name: ".DS_Store", isDirectory: false, dateAdded: nil, dateModified: nil),
            FolderContentsLoader.Entry(url: source.appendingPathComponent("Subdir"), name: "Subdir", isDirectory: true, dateAdded: nil, dateModified: nil),
            FolderContentsLoader.Entry(url: source.appendingPathComponent("shot.png"), name: "shot.png", isDirectory: false, dateAdded: nil, dateModified: nil),
            FolderContentsLoader.Entry(url: source.appendingPathComponent("notes.pdf"), name: "notes.pdf", isDirectory: false, dateAdded: nil, dateModified: nil),
            FolderContentsLoader.Entry(url: source.appendingPathComponent("song.mp3"), name: "song.mp3", isDirectory: false, dateAdded: nil, dateModified: nil)
        ]

        var enabled = Set(DesktopAutoStackCategory.allCases)
        enabled.remove(.audio)

        let plan = DesktopAutoOrganizeEngine.buildPlan(
            entries: entries,
            options: DesktopOrganizeOptions(
                sourceDirectory: source,
                destinationRoot: dest,
                includeFolders: false,
                enabledCategories: enabled
            )
        )

        XCTAssertEqual(plan.totalFileCount, 2)
        XCTAssertEqual(plan.buckets.map(\.category), [.documents, .images])
        XCTAssertEqual(Set(plan.skippedNames), [".DS_Store", "Subdir", "song.mp3"])
    }

    func testScanApplyAndUndoRoundTripRestoresAllFilesAndCleansEmptyDirs() throws {
        let source = tempRoot.appendingPathComponent("SourceDesktop", isDirectory: true)
        let dest = tempRoot.appendingPathComponent("Organized", isDirectory: true)
        let undoURL = tempRoot.appendingPathComponent("undo.json")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        try Data("img".utf8).write(to: source.appendingPathComponent("photo.png"))
        try Data("doc".utf8).write(to: source.appendingPathComponent("spec.pdf"))
        // Existing conflict in destination to test non-destructive unique naming.
        let imagesBucket = dest.appendingPathComponent(DesktopAutoStackCategory.images.localizedTitle, isDirectory: true)
        try FileManager.default.createDirectory(at: imagesBucket, withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: imagesBucket.appendingPathComponent("photo.png"))

        let plan = try DesktopAutoOrganizeExecutor.scanAndPlan(
            options: DesktopOrganizeOptions(sourceDirectory: source, destinationRoot: dest)
        )
        XCTAssertEqual(plan.totalFileCount, 2)

        let record = try DesktopAutoOrganizeExecutor.apply(plan, undoRecordURL: undoURL)
        XCTAssertEqual(record.moves.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.appendingPathComponent("photo.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: imagesBucket.appendingPathComponent("photo 2.png").path))
        XCTAssertNotNil(DesktopAutoOrganizeExecutor.loadLastUndoRecord(from: undoURL))

        let undone = DesktopAutoOrganizeExecutor.undo(record, undoRecordURL: undoURL)
        XCTAssertEqual(undone.restoredCount, 2)
        XCTAssertTrue(undone.failedPaths.isEmpty)
        XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent("photo.png")), Data("img".utf8))
        XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent("spec.pdf")), Data("doc".utf8))
        XCTAssertNil(DesktopAutoOrganizeExecutor.loadLastUndoRecord(from: undoURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent(DesktopAutoStackCategory.documents.localizedTitle).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: imagesBucket.appendingPathComponent("photo.png").path), "pre-existing destination file untouched")
    }
}
