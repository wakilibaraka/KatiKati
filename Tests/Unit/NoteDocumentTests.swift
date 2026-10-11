import XCTest
@testable import KatiKati

final class NoteDocumentTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testRoundTripPreservesEverything() {
        let note = Note(id: "A1", title: "Groceries", body: "milk\n\n- eggs\n", created: t0,
                        modified: t0.addingTimeInterval(90), pinned: true, archived: true, order: 7)
        let parsed = NoteDocument.parse(NoteDocument.render(note), fallbackTitle: "x", fallbackDate: .distantPast)
        XCTAssertEqual(parsed.note, note)
        XCTAssertTrue(parsed.hasIdentity)
        XCTAssertTrue(parsed.hasDeclaredModified)
    }

    func testEmptyTitleIsNotFrozenIntoTheHeader() {
        let note = Note(id: "A2", body: "First line\nmore", created: t0)
        let text = NoteDocument.render(note)
        XCTAssertFalse(text.contains("title:"))
        XCTAssertEqual(NoteDocument.parse(text, fallbackTitle: "x", fallbackDate: t0).note.displayTitle, "First line")
    }

    func testMultilineTitleFoldsToOneLine() {
        let note = Note(id: "A3", title: "a\nb", body: "x", created: t0)
        XCTAssertTrue(NoteDocument.render(note).contains("title: a b"))
    }

    func testFileWithoutHeaderHasNoIdentityAndKeepsWholeBody() {
        let p = NoteDocument.parse("just text\nmore", fallbackTitle: "From phone", fallbackDate: t0)
        XCTAssertFalse(p.hasIdentity)
        XCTAssertFalse(p.hasDeclaredModified)
        XCTAssertEqual(p.note.body, "just text\nmore")
        XCTAssertEqual(p.note.modified, t0)
    }

    func testEmptyFileUsesFallbackTitle() {
        let p = NoteDocument.parse("", fallbackTitle: "Untitled file", fallbackDate: t0)
        XCTAssertEqual(p.note.displayTitle, "Untitled file")
    }

    func testToleratesCRLFAndUnknownKeysAndBadValues() {
        let text = "---\r\nkatikati-id: Z\r\nmodified: not-a-date\r\nfuture-key: 1\r\norder: nope\r\n---\r\n\r\nbody"
        let p = NoteDocument.parse(text, fallbackTitle: "t", fallbackDate: t0)
        XCTAssertEqual(p.note.id, "Z")
        XCTAssertEqual(p.note.order, 0)
        XCTAssertEqual(p.note.modified, t0, "unparseable stamp falls back")
        XCTAssertFalse(p.hasDeclaredModified)
        XCTAssertEqual(p.note.body, "body")
    }

    func testUnclosedHeaderIsTreatedAsBody() {
        let p = NoteDocument.parse("---\nkatikati-id: Q\nno close", fallbackTitle: "t", fallbackDate: t0)
        XCTAssertFalse(p.hasIdentity)
    }

    func testDatesAreWholeSeconds() {
        let n = Note(created: Date(timeIntervalSince1970: 100.9))
        XCTAssertEqual(n.created.timeIntervalSince1970, 100)
    }
}
