import Foundation
import XCTest
@testable import KatiKati

final class DesktopFileOperationsTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DesktopFileOpsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    func testDropTransferModeResolvesSameVsCrossVolumeAndModifiers() {
        XCTAssertEqual(
            DesktopDropTransferMode.resolve(sourceVolume: "/Volumes/A", destinationVolume: "/Volumes/A", forceCopy: false, forceMove: false),
            .move
        )
        XCTAssertEqual(
            DesktopDropTransferMode.resolve(sourceVolume: "/Volumes/A", destinationVolume: "/Volumes/B", forceCopy: false, forceMove: false),
            .copy
        )
        XCTAssertEqual(
            DesktopDropTransferMode.resolve(sourceVolume: "/Volumes/A", destinationVolume: "/Volumes/A", forceCopy: true, forceMove: false),
            .copy
        )
        XCTAssertEqual(
            DesktopDropTransferMode.resolve(sourceVolume: "/Volumes/A", destinationVolume: "/Volumes/B", forceCopy: false, forceMove: true),
            .move
        )
    }

    func testUniqueURLAndNewFolderConflictSafety() throws {
        let folder1 = try DesktopFileOperations.createNewFolder(in: tempDir, baseName: "Untitled Folder")
        let folder2 = try DesktopFileOperations.createNewFolder(in: tempDir, baseName: "Untitled Folder")
        XCTAssertEqual(folder1.lastPathComponent, "Untitled Folder")
        XCTAssertEqual(folder2.lastPathComponent, "Untitled Folder 2")

        let file = tempDir.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: file)
        let uniqueFile = DesktopFileOperations.uniqueURL(in: tempDir, preferredName: "notes.txt")
        XCTAssertEqual(uniqueFile.lastPathComponent, "notes 2.txt")
    }

    func testRenameRejectsSlashEmptyAndDuplicateTargets() throws {
        let fileA = tempDir.appendingPathComponent("a.txt")
        let fileB = tempDir.appendingPathComponent("b.txt")
        try Data("a".utf8).write(to: fileA)
        try Data("b".utf8).write(to: fileB)

        XCTAssertThrowsError(try DesktopFileOperations.renameItem(at: fileA, to: "   "))
        XCTAssertThrowsError(try DesktopFileOperations.renameItem(at: fileA, to: "b.txt"))

        let renamed = try DesktopFileOperations.renameItem(at: fileA, to: "a/clean.txt")
        XCTAssertEqual(renamed.lastPathComponent, "a-clean.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
    }

    func testImportFilesCopiesOnForceCopyAndMovesSameVolume() throws {
        let srcDir = tempDir.appendingPathComponent("src", isDirectory: true)
        let dstDir = tempDir.appendingPathComponent("dst", isDirectory: true)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dstDir, withIntermediateDirectories: true)

        let item = srcDir.appendingPathComponent("doc.txt")
        try Data("payload".utf8).write(to: item)

        let copied = try DesktopFileOperations.importFiles([item], into: dstDir, forceCopy: true)
        XCTAssertEqual(copied.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied[0].path))

        let moved = try DesktopFileOperations.importFiles([item], into: dstDir, forceCopy: false, forceMove: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.path))
        XCTAssertEqual(moved[0].lastPathComponent, "doc 2.txt")
    }
}
