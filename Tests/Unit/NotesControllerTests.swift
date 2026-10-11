import XCTest
@testable import KatiKati

@MainActor
final class NotesControllerTests: XCTestCase {
    private var dir: URL!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var pending: [(delay: TimeInterval, work: () -> Void, cancelled: Bool)] = []
    private let provider = InMemoryNoteKeyProvider()

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("NotesController-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func makeController() throws -> NotesController {
        let store = try NotesStore(directory: dir, keyProvider: provider)
        return NotesController(store: store, now: { [unowned self] in self.clock }, schedule: { [unowned self] delay, work in
            let index = self.pending.count
            self.pending.append((delay, work, false))
            return { self.pending[index].cancelled = true }
        })
    }

    private func fire(delay: TimeInterval) {
        for i in pending.indices where pending[i].delay == delay && !pending[i].cancelled {
            pending[i].cancelled = true
            pending[i].work()
        }
    }

    private func diskNotes() throws -> [Note] { try NotesStore(directory: dir, keyProvider: provider).loadAll().notes }

    func testCreateWritesImmediatelyAndNewestSortsFirst() throws {
        let c = try makeController()
        let a = c.create(body: "first")
        clock.addTimeInterval(5)
        let b = c.create(body: "second")
        XCTAssertEqual(c.notes.map(\.id), [b.id, a.id], "newest on top")
        XCTAssertEqual(try diskNotes().count, 2)
    }

    func testEditIsDebouncedThenFlushed() throws {
        let c = try makeController()
        let n = c.create()
        clock.addTimeInterval(1)
        c.edit(id: n.id, body: "h")
        c.edit(id: n.id, body: "hello")
        XCTAssertEqual(c.note(id: n.id)?.body, "hello", "in-memory immediately")
        XCTAssertEqual(try diskNotes().first?.body, "", "disk not written yet")
        fire(delay: NotesController.autosaveDelay)
        XCTAssertEqual(try diskNotes().first?.body, "hello")
        XCTAssertEqual(try diskNotes().first?.modified, Note.wholeSeconds(clock))
    }

    func testFlushWritesPendingEditsAndNotifiesOnce() throws {
        let c = try makeController()
        let n = c.create()
        var changes = 0
        c.onLocalChange = { changes += 1 }
        c.edit(id: n.id, body: "x")
        c.flush()
        XCTAssertEqual(try diskNotes().first?.body, "x")
        XCTAssertEqual(changes, 1)
        c.flush()
        XCTAssertEqual(changes, 1, "nothing pending → no notification")
    }

    func testNoOpEditDoesNotDirtyTheNote() throws {
        let c = try makeController()
        let n = c.create(body: "same")
        let modified = c.note(id: n.id)?.modified
        clock.addTimeInterval(30)
        c.edit(id: n.id, body: "same")
        XCTAssertEqual(c.note(id: n.id)?.modified, modified)
    }

    func testDeleteThenUndoRestoresSameIdentity() throws {
        let c = try makeController()
        let n = c.create(body: "keep me")
        c.delete(id: n.id)
        XCTAssertTrue(c.notes.isEmpty)
        XCTAssertTrue(try diskNotes().isEmpty)
        XCTAssertEqual(c.undoableDeletion?.id, n.id)
        c.undoDelete()
        XCTAssertEqual(c.notes.map(\.id), [n.id])
        XCTAssertEqual(try diskNotes().first?.body, "keep me")
        XCTAssertNil(c.undoableDeletion)
    }

    func testUndoWindowExpires() throws {
        let c = try makeController()
        let n = c.create()
        c.delete(id: n.id)
        fire(delay: NotesController.undoWindow)
        XCTAssertNil(c.undoableDeletion)
        c.undoDelete()
        XCTAssertTrue(c.notes.isEmpty, "expired undo is a no-op")
    }

    func testPinMovesNoteToTopAndPersists() throws {
        let c = try makeController()
        let a = c.create(body: "a"); clock.addTimeInterval(5)
        let b = c.create(body: "b")
        XCTAssertEqual(c.notes.first?.id, b.id)
        c.togglePin(id: a.id)
        XCTAssertEqual(c.notes.first?.id, a.id)
        XCTAssertEqual(try diskNotes().first?.id, a.id)
        XCTAssertTrue(try diskNotes().first?.pinned ?? false)
    }

    func testDeletingWithPendingEditDoesNotResurrectIt() throws {
        let c = try makeController()
        let n = c.create()
        c.edit(id: n.id, body: "edit")
        c.delete(id: n.id)
        c.flush()
        XCTAssertTrue(try diskNotes().isEmpty)
    }

    func testReloadPicksUpExternalChangesAndReportsUnreadable() throws {
        let c = try makeController()
        let other = try NotesStore(directory: dir, keyProvider: provider)
        try other.save(Note(id: "ext", body: "from sync"))
        c.reload()
        XCTAssertEqual(c.notes.map(\.id), ["ext"])
        XCTAssertNil(c.lastError)
        let bad = try NotesStore(directory: dir, keyProvider: InMemoryNoteKeyProvider())
        let c2 = NotesController(store: bad)
        XCTAssertTrue(c2.notes.isEmpty)
        XCTAssertNotNil(c2.lastError)
    }
}
