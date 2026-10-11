import CryptoKit
import XCTest
@testable import KatiKati

final class NoteFileNameTests: XCTestCase {
    func testSanitizesAndTruncates() {
        XCTAssertEqual(NoteFileName.make(title: "a/b:c\\d", existing: []), "a b c d.md")
        XCTAssertEqual(NoteFileName.make(title: "  ", existing: []), "Note.md")
        XCTAssertEqual(NoteFileName.make(title: ".hidden", existing: []), "hidden.md")
        XCTAssertEqual(NoteFileName.sanitizedStem(String(repeating: "x", count: 200), fallback: "n").count, NoteFileName.maxStemLength)
    }

    func testUniquenessIsCaseInsensitive() {
        XCTAssertEqual(NoteFileName.make(title: "Todo", existing: ["todo.md"]), "Todo 2.md")
        XCTAssertEqual(NoteFileName.make(title: "Todo", existing: ["Todo.md", "Todo 2.md"]), "Todo 3.md")
        XCTAssertEqual(NoteFileName.stem(of: "Groceries.md"), "Groceries")
    }
}

final class NotesSyncRunnerTests: XCTestCase {
    private var root: URL!
    private var cloud: URL!
    private let key = NoteCipher.generateKey()
    private let suffix = "(conflict)"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("NotesSync-\(UUID().uuidString)")
        cloud = root.appendingPathComponent("cloud")
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// One "device": its own encrypted store + index, sharing the cloud folder.
    private final class Device {
        let store: NotesStore
        let folder: NotesSyncFolder
        var index = NotesSyncIndex()
        let suffix: String
        init(name: String, root: URL, cloud: URL, key: SymmetricKeyBox, suffix: String) throws {
            store = try NotesStore(directory: root.appendingPathComponent(name), keyProvider: InMemoryNoteKeyProvider(key: key.value))
            folder = NotesSyncFolder(url: cloud)
            self.suffix = suffix
        }
        @discardableResult func sync() -> NotesSyncRunner.Report {
            let r = NotesSyncRunner(store: store, folder: folder, conflictSuffix: suffix).run(index: index)
            index = r.index
            return r.report
        }
    }
    struct SymmetricKeyBox { let value: SymmetricKey }

    private func device(_ name: String) throws -> Device {
        try Device(name: name, root: root, cloud: cloud, key: SymmetricKeyBox(value: key), suffix: suffix)
    }

    func testMissingFolderDoesNothing() throws {
        let d = try device("a")
        try d.store.save(Note(id: "n", body: "x"))
        let gone = NotesSyncFolder(url: root.appendingPathComponent("nope"))
        let r = NotesSyncRunner(store: d.store, folder: gone, conflictSuffix: suffix).run(index: NotesSyncIndex())
        XCTAssertTrue(r.report.folderMissing)
        XCTAssertEqual(d.store.loadAll().notes.count, 1)
    }

    func testPushThenPullOnSecondDeviceThenStable() throws {
        let a = try device("a"), b = try device("b")
        try a.store.save(Note(id: "n1", title: "Groceries", body: "milk", modified: Date(timeIntervalSince1970: 1_800_000_000)))
        XCTAssertEqual(a.sync().pushed, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cloud.appendingPathComponent("Groceries.md").path))
        XCTAssertEqual(b.sync().pulled, 1)
        XCTAssertEqual(b.store.loadAll().notes.first?.body, "milk")
        let again = a.sync()
        XCTAssertEqual(again.pushed + again.pulled + again.conflicts, 0, "second pass is a no-op")
        let bAgain = b.sync()
        XCTAssertEqual(bAgain.pushed + bAgain.pulled + bAgain.conflicts, 0)
    }

    func testEditOnOneDevicePropagates() throws {
        let a = try device("a"), b = try device("b")
        try a.store.save(Note(id: "n1", title: "T", body: "v1", modified: Date(timeIntervalSince1970: 1_800_000_000)))
        a.sync(); b.sync()
        var edited = b.store.loadAll().notes[0]
        edited.body = "v2"
        edited.modified = Date(timeIntervalSince1970: 1_800_000_100)
        try b.store.save(edited)
        Thread.sleep(forTimeInterval: 1.1)      // file mtime has one-second resolution
        XCTAssertEqual(b.sync().pushed, 1)
        XCTAssertEqual(a.sync().pulled, 1)
        XCTAssertEqual(a.store.loadAll().notes[0].body, "v2")
    }

    func testConflictKeepsBothVersions() throws {
        let a = try device("a"), b = try device("b")
        try a.store.save(Note(id: "n1", title: "T", body: "base", modified: Date(timeIntervalSince1970: 1_800_000_000)))
        a.sync(); b.sync()
        var ea = a.store.loadAll().notes[0]; ea.body = "from A"; ea.modified = Date(timeIntervalSince1970: 1_800_000_100); try a.store.save(ea)
        var eb = b.store.loadAll().notes[0]; eb.body = "from B"; eb.modified = Date(timeIntervalSince1970: 1_800_000_200); try b.store.save(eb)
        Thread.sleep(forTimeInterval: 1.1)
        XCTAssertEqual(b.sync().pushed, 1)
        Thread.sleep(forTimeInterval: 1.1)
        let report = a.sync()
        XCTAssertEqual(report.conflicts, 1)
        let notes = a.store.loadAll().notes
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(Set(notes.map(\.body)), ["from A", "from B"])
        XCTAssertTrue(notes.contains { $0.title.hasSuffix(suffix) })
    }

    func testRemoteDeletionRemovesLocalAndLocalDeletionRemovesRemote() throws {
        let a = try device("a"), b = try device("b")
        try a.store.save(Note(id: "n1", title: "T", body: "x", modified: Date(timeIntervalSince1970: 1_800_000_000)))
        a.sync(); b.sync()
        try b.store.delete(id: "n1")
        XCTAssertEqual(b.sync().deletedRemote, 1)
        XCTAssertEqual(a.sync().deletedLocal, 1)
        XCTAssertTrue(a.store.loadAll().notes.isEmpty)
    }

    func testIdentityLessFileIsAdoptedAndGetsAHeader() throws {
        try "typed on a phone".write(to: cloud.appendingPathComponent("Idea.md"), atomically: true, encoding: .utf8)
        let a = try device("a")
        XCTAssertEqual(a.sync().adopted, 1)
        XCTAssertEqual(a.store.loadAll().notes.first?.body, "typed on a phone")
        let text = try String(contentsOf: cloud.appendingPathComponent("Idea.md"))
        XCTAssertTrue(text.contains(NoteDocument.Key.id))
        XCTAssertEqual(a.sync().adopted, 0, "adopted once")
    }

    func testUnreadableLocalNotesSkipThePassSoRemoteCopiesSurvive() throws {
        let a = try device("a")
        try a.store.save(Note(id: "n1", title: "T", body: "x", modified: Date(timeIntervalSince1970: 1_800_000_000)))
        a.sync()
        let wrongKey = try NotesStore(directory: a.store.directory, keyProvider: InMemoryNoteKeyProvider())
        let r = NotesSyncRunner(store: wrongKey, folder: a.folder, conflictSuffix: suffix).run(index: a.index)
        XCTAssertTrue(r.report.localUnreadable)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cloud.appendingPathComponent("T.md").path))
    }

    func testEvictedPlaceholderIsUnresolvedNotDeleted() throws {
        let a = try device("a")
        try a.store.save(Note(id: "n1", title: "T", body: "x", modified: Date(timeIntervalSince1970: 1_800_000_000)))
        a.sync()
        let real = cloud.appendingPathComponent("T.md"), stub = cloud.appendingPathComponent(".T.md.icloud")
        try FileManager.default.moveItem(at: real, to: stub)
        let scan = a.folder.scan()
        XCTAssertEqual(scan.unresolved, ["T.md"])
        XCTAssertEqual(a.sync().deletedLocal, 0, "placeholder must not read as a deletion")
        XCTAssertEqual(a.store.loadAll().notes.count, 1)
        XCTAssertEqual(NotesSyncFolder.placeholderTarget(".T.md.icloud"), "T.md")
        XCTAssertNil(NotesSyncFolder.placeholderTarget("T.md"))
    }

    func testIndexStoreRoundTripAndMissingFileIsEmpty() throws {
        let store = NotesSyncIndexStore(url: root.appendingPathComponent("idx/index.json"))
        XCTAssertEqual(store.load(), NotesSyncIndex())
        let idx = NotesSyncIndex(entries: ["a": .init(fileName: "a.md", syncedModified: Date(timeIntervalSince1970: 100), fileModified: Date(timeIntervalSince1970: 200))])
        try store.save(idx)
        XCTAssertEqual(store.load(), idx)
    }
}
