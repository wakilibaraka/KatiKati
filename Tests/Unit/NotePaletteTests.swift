import XCTest
@testable import KatiKati

final class NotePaletteTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testPaletteIsFrozenAndWraps() {
        XCTAssertEqual(NotePalette.all.map(\.name), ["Lemon", "Peach", "Rose", "Lilac", "Sky", "Mint", "Sand", "Slate"])
        XCTAssertEqual(NotePalette.entry(at: 8).name, "Lemon")
        XCTAssertEqual(NotePalette.entry(at: -1).name, "Slate")
        XCTAssertEqual(NotePalette.entry(at: 0).paper, 0xFCE795)
    }

    func testNextIndexRotatesFromTheNewestNote() {
        XCTAssertEqual(NotePalette.nextIndex(after: []), 0)
        let notes = [Note(id: "a", created: t0, color: 2), Note(id: "b", created: t0.addingTimeInterval(10), color: 7)]
        XCTAssertEqual(NotePalette.nextIndex(after: notes), 0, "wraps after the last colour")
        XCTAssertEqual(NotePalette.nextIndex(after: [Note(id: "a", created: t0, color: 2)]), 3)
    }

    func testColorRoundTripsThroughTheDocument() {
        let note = Note(id: "n", title: "T", body: "b", created: t0, color: 5)
        let text = NoteDocument.render(note)
        XCTAssertTrue(text.contains("color: 5"))
        XCTAssertEqual(NoteDocument.parse(text, fallbackTitle: "x", fallbackDate: t0).note.color, 5)
        XCTAssertEqual(NoteDocument.parse("---\nkatikati-id: Q\ncolor: nope\n---\n\nx", fallbackTitle: "x", fallbackDate: t0).note.color, 0)
    }

    func testNotesSavedBeforeColorsStillDecode() throws {
        let legacy = #"{"id":"a","title":"","body":"old","created":1800000000,"modified":1800000000,"pinned":false,"archived":false,"order":3}"#
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        let n = try d.decode(Note.self, from: Data(legacy.utf8))
        XCTAssertEqual(n.color, 0)
        XCTAssertEqual(n.order, 3)
    }

    // MARK: Reorder

    private func list(_ ids: [String]) -> [Note] { ids.enumerated().map { Note(id: $1, order: $0 * 10) } }

    func testReorderMovesDownAndRewritesOrdersDensely() {
        let changed = NoteOrdering.reorder(list(["a", "b", "c", "d"]), id: "a", by: 2)
        // new order b, c, a, d → ranks 0,1,2,3; only notes whose stored order differs are returned
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: changed.map { ($0.id, $0.order) }), ["b": 0, "c": 1, "a": 2, "d": 3])
    }

    func testReorderClampsAndIgnoresNoOps() {
        XCTAssertTrue(NoteOrdering.reorder(list(["a", "b"]), id: "a", by: 0).isEmpty)
        XCTAssertTrue(NoteOrdering.reorder(list(["a", "b"]), id: "zzz", by: 1).isEmpty)
        XCTAssertTrue(NoteOrdering.reorder(list(["a", "b"]), id: "b", by: 5).isEmpty, "already last")
        let up = NoteOrdering.reorder(list(["a", "b", "c"]), id: "c", by: -9)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: up.map { ($0.id, $0.order) })["c"], 0)
    }

    func testAlreadyDenseOrdersOnlyReportTheMovedPair() {
        let dense = ["a", "b", "c"].enumerated().map { Note(id: $1, order: $0) }
        let changed = NoteOrdering.reorder(dense, id: "a", by: 1)
        XCTAssertEqual(Set(changed.map(\.id)), ["a", "b"])
    }
}
