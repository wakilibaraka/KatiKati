import XCTest

final class FolderContentsLoaderTests: XCTestCase {
    private func entry(
        _ name: String,
        isDirectory: Bool = false,
        added: TimeInterval? = nil,
        modified: TimeInterval? = nil
    ) -> FolderContentsLoader.Entry {
        FolderContentsLoader.Entry(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            name: name,
            isDirectory: isDirectory,
            dateAdded: added.map { Date(timeIntervalSince1970: $0) },
            dateModified: modified.map { Date(timeIntervalSince1970: $0) }
        )
    }

    func testSortedByDateAddedNewestFirst() {
        let sorted = FolderContentsLoader.sortedByDateAdded([
            entry("old", added: 100),
            entry("new", added: 300),
            entry("mid", added: 200),
        ])
        XCTAssertEqual(sorted.map(\.name), ["new", "mid", "old"])
    }

    func testMissingDateAddedFallsBackToModificationDate() {
        let sorted = FolderContentsLoader.sortedByDateAdded([
            entry("added-early", added: 100),
            entry("network-volume", added: nil, modified: 500),
        ])
        XCTAssertEqual(sorted.map(\.name), ["network-volume", "added-early"])
    }

    func testEqualDatesTieBreakByLocalizedName() {
        let sorted = FolderContentsLoader.sortedByDateAdded([
            entry("b.txt", added: 100),
            entry("a.txt", added: 100),
            entry("file10.txt", added: 100),
            entry("file2.txt", added: 100),
        ])
        // localizedStandardCompare：数字按数值序（file2 < file10）。
        XCTAssertEqual(sorted.map(\.name), ["a.txt", "b.txt", "file2.txt", "file10.txt"])
    }

    func testEntriesWithNoDatesSortStablyByName() {
        let sorted = FolderContentsLoader.sortedByDateAdded([
            entry("zeta"),
            entry("alpha"),
        ])
        XCTAssertEqual(sorted.map(\.name), ["alpha", "zeta"])
    }
}

/// `DirectoryWatcher.start` 的契约：fd 在后台开、watcher（打不开就是 nil）回主队列。
/// 回归 48a walk 的首启冻屏 —— 调用线程永远不进可能阻塞的 `open()`。
final class DirectoryWatcherStartTests: XCTestCase {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testStartDeliversLiveWatcherOnMainForRealDirectory() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let done = expectation(description: "watcher delivered")
        var deliveredOnMain = false
        var delivered: DirectoryWatcher?
        var held: DirectoryWatcher?
        DirectoryWatcher.start(
            path: dir.path,
            onChange: {},
            completion: { watcher in
                deliveredOnMain = Thread.isMainThread
                delivered = watcher
                held = watcher
                done.fulfill()
            }
        )
        wait(for: [done], timeout: 5)
        XCTAssertTrue(deliveredOnMain)
        XCTAssertNotNil(delivered)
        _ = held
    }

    func testStartCompletesNilForMissingPath() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("katikati-no-such-dir-\(UUID().uuidString)").path
        let done = expectation(description: "nil delivered")
        var calls = 0
        var delivered: DirectoryWatcher?
        DirectoryWatcher.start(
            path: missing,
            onChange: { XCTFail("no watcher, so no callback expected") },
            completion: { watcher in
                calls += 1
                delivered = watcher
                done.fulfill()
            }
        )
        wait(for: [done], timeout: 5)
        XCTAssertEqual(calls, 1)
        XCTAssertNil(delivered)
    }

    func testLiveWatcherFiresWhenDirectoryChanges() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let ready = expectation(description: "watcher delivered")
        let changed = expectation(description: "onChange fired")
        var held: DirectoryWatcher?
        DirectoryWatcher.start(
            path: dir.path,
            debounce: 0.05,
            onChange: { changed.fulfill() },
            completion: { watcher in
                held = watcher
                ready.fulfill()
            }
        )
        wait(for: [ready], timeout: 5)
        XCTAssertNotNil(held)
        try "x".write(to: dir.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
        wait(for: [changed], timeout: 5)
        _ = held
    }
}
