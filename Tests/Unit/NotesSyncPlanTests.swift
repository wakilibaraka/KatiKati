import XCTest
@testable import KatiKati

final class NotesSyncPlanTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
    private func note(_ id: String, mod: TimeInterval = 0) -> Note { Note(id: id, body: id, created: t0, modified: at(mod)) }
    private func file(_ name: String, id: String?, declared: TimeInterval = 0, fileMod: TimeInterval = 0) -> NotesSyncPlan.RemoteFile {
        .init(fileName: name, noteID: id, declaredModified: id == nil ? .distantPast : at(declared), fileModified: at(fileMod))
    }
    private func index(_ id: String, name: String, synced: TimeInterval = 0, fileMod: TimeInterval = 0) -> NotesSyncIndex {
        NotesSyncIndex(entries: [id: .init(fileName: name, syncedModified: at(synced), fileModified: at(fileMod))])
    }
    private func plan(_ notes: [Note], _ remote: [NotesSyncPlan.RemoteFile], unresolved: Set<String> = [],
                      _ idx: NotesSyncIndex = NotesSyncIndex()) -> [NotesSyncPlan.Action] {
        NotesSyncPlan.actions(notes: notes, remote: remote, unresolved: unresolved, index: idx)
    }

    func testNewLocalNotePushes() {
        XCTAssertEqual(plan([note("a")], []), [.push(noteID: "a", existingFileName: nil)])
    }

    func testNewRemoteIdentifiedFilePulls() {
        XCTAssertEqual(plan([], [file("a.md", id: "a")]), [.pull(fileName: "a.md")])
    }

    func testFileWithoutIdentityIsAdopted() {
        XCTAssertEqual(plan([], [file("phone.md", id: nil)]), [.adopt(fileName: "phone.md")])
    }

    func testUnchangedBothSidesDoesNothing() {
        XCTAssertTrue(plan([note("a", mod: 5)], [file("a.md", id: "a", declared: 5, fileMod: 5)], index("a", name: "a.md", synced: 5, fileMod: 5)).isEmpty)
    }

    func testLocalEditPushesToExistingName() {
        XCTAssertEqual(plan([note("a", mod: 9)], [file("renamed.md", id: "a", fileMod: 5)], index("a", name: "a.md", synced: 5, fileMod: 5)),
                       [.push(noteID: "a", existingFileName: "renamed.md")])
    }

    func testRemoteEditPulls() {
        XCTAssertEqual(plan([note("a", mod: 5)], [file("a.md", id: "a", declared: 5, fileMod: 9)], index("a", name: "a.md", synced: 5, fileMod: 5)),
                       [.pull(fileName: "a.md")])
    }

    func testBothChangedIsAConflictNewerWins() {
        let idx = index("a", name: "a.md", synced: 5, fileMod: 5)
        XCTAssertEqual(plan([note("a", mod: 20)], [file("a.md", id: "a", declared: 10, fileMod: 10)], idx),
                       [.conflict(noteID: "a", fileName: "a.md", localWins: true)])
        XCTAssertEqual(plan([note("a", mod: 8)], [file("a.md", id: "a", declared: 10, fileMod: 10)], idx),
                       [.conflict(noteID: "a", fileName: "a.md", localWins: false)])
    }

    func testSameEditSeenTwiceIsNotAConflict() {
        XCTAssertTrue(plan([note("a", mod: 10)], [file("a.md", id: "a", declared: 10, fileMod: 10)], index("a", name: "a.md", synced: 5, fileMod: 5)).isEmpty)
    }

    func testLostIndexWithMatchingTimestampReindexes() {
        XCTAssertEqual(plan([note("a", mod: 5)], [file("a.md", id: "a", declared: 5, fileMod: 5)]),
                       [.reindex(noteID: "a", fileName: "a.md")])
    }

    func testLostIndexWithDifferentTimestampIsAConflict() {
        XCTAssertEqual(plan([note("a", mod: 5)], [file("a.md", id: "a", declared: 9, fileMod: 9)]),
                       [.conflict(noteID: "a", fileName: "a.md", localWins: false)])
    }

    func testRemoteDeletionDeletesLocalOnlyWhenReadable() {
        let idx = index("a", name: "a.md")
        XCTAssertEqual(plan([note("a")], [], idx), [.deleteLocal(noteID: "a")])
        XCTAssertTrue(plan([note("a")], [], unresolved: ["a.md"], idx).isEmpty, "unreadable ≠ deleted")
    }

    func testLocalDeletionDeletesRemote() {
        XCTAssertEqual(plan([], [file("a.md", id: "a")], index("a", name: "a.md")), [.deleteRemote(fileName: "a.md")])
    }

    func testDuplicateIdentityKeepsIndexedHomeAndAdoptsTheCopy() {
        let remote = [file("a.md", id: "a", fileMod: 1), file("a copy.md", id: "a", fileMod: 9)]
        let idx = index("a", name: "a.md", synced: 0, fileMod: 1)
        let actions = plan([note("a")], remote, idx)
        XCTAssertEqual(actions, [.adopt(fileName: "a copy.md")])
    }

    func testDuplicateIdentityWithoutIndexKeepsNewestAndNeverPullsTwice() {
        let remote = [file("x.md", id: "n", fileMod: 1), file("y.md", id: "n", fileMod: 9)]
        XCTAssertEqual(plan([], remote), [.adopt(fileName: "x.md"), .pull(fileName: "y.md")])
    }
}
