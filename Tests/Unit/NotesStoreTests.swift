import CryptoKit
import XCTest
@testable import KatiKati

final class NoteCipherTests: XCTestCase {
    func testRoundTrip() throws {
        let c = NoteCipher(key: NoteCipher.generateKey())
        let blob = try c.seal(Data("hello".utf8))
        XCTAssertEqual(try c.open(blob), Data("hello".utf8))
    }

    func testEachSealUsesAFreshNonce() throws {
        let c = NoteCipher(key: NoteCipher.generateKey())
        XCTAssertNotEqual(try c.seal(Data("x".utf8)), try c.seal(Data("x".utf8)))
    }

    func testPlaintextIsNotVisibleInTheBlob() throws {
        let c = NoteCipher(key: NoteCipher.generateKey())
        let blob = try c.seal(Data("super secret body".utf8))
        XCTAssertNil(blob.range(of: Data("secret".utf8)))
    }

    func testTamperedBlobAndWrongKeyFailAuthentication() throws {
        let c = NoteCipher(key: NoteCipher.generateKey())
        var blob = try c.seal(Data("data".utf8))
        let wrong = NoteCipher(key: NoteCipher.generateKey())
        XCTAssertThrowsError(try wrong.open(blob)) { XCTAssertEqual($0 as? NoteCipher.CipherError, .authenticationFailed) }
        blob[blob.count - 1] ^= 0xFF
        XCTAssertThrowsError(try c.open(blob)) { XCTAssertEqual($0 as? NoteCipher.CipherError, .authenticationFailed) }
        XCTAssertThrowsError(try c.open(Data([1, 2, 3]))) { XCTAssertEqual($0 as? NoteCipher.CipherError, .malformed) }
    }
}

final class NotesStoreTests: XCTestCase {
    private var dir: URL!
    private let provider = InMemoryNoteKeyProvider()

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("NotesStoreTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func store() throws -> NotesStore { try NotesStore(directory: dir, keyProvider: provider) }

    func testSaveLoadRoundTripAndSortOrder() throws {
        let s = try store()
        let a = Note(id: "a", body: "A", created: Date(timeIntervalSince1970: 100), order: 2)
        let b = Note(id: "b", body: "B", created: Date(timeIntervalSince1970: 200), pinned: true, order: 9)
        let c = Note(id: "c", body: "C", created: Date(timeIntervalSince1970: 300), order: 1)
        for n in [a, b, c] { try s.save(n) }
        let loaded = s.loadAll()
        XCTAssertEqual(loaded.notes.map(\.id), ["b", "c", "a"], "pinned first, then order")
        XCTAssertEqual(loaded.notes.first { $0.id == "a" }, a)
        XCTAssertTrue(loaded.unreadable.isEmpty)
    }

    func testFilesOnDiskAreEncrypted() throws {
        let s = try store()
        try s.save(Note(id: "a", body: "private words"))
        let raw = try Data(contentsOf: dir.appendingPathComponent("a.note"))
        XCTAssertNil(raw.range(of: Data("private".utf8)))
    }

    func testSaveOverwritesAndDeleteRemoves() throws {
        let s = try store()
        try s.save(Note(id: "a", body: "one"))
        try s.save(Note(id: "a", body: "two"))
        XCTAssertEqual(s.loadAll().notes.map(\.body), ["two"])
        try s.delete(id: "a")
        try s.delete(id: "a")   // idempotent
        XCTAssertTrue(s.loadAll().notes.isEmpty)
    }

    func testWrongKeyReportsUnreadableAndKeepsTheFile() throws {
        try store().save(Note(id: "a", body: "x"))
        let other = try NotesStore(directory: dir, keyProvider: InMemoryNoteKeyProvider())
        let result = other.loadAll()
        XCTAssertTrue(result.notes.isEmpty)
        XCTAssertEqual(result.unreadable, ["a.note"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("a.note").path), "never deleted")
    }

    func testMissingDirectoryLoadsEmptyAndIdsAreSanitized() throws {
        XCTAssertTrue(try store().loadAll().notes.isEmpty)
        XCTAssertEqual(NotesStore.safeName("../../etc/passwd"), "______etc_passwd")
        XCTAssertEqual(NotesStore.safeName(""), "note")
        try store().save(Note(id: "../escape", body: "x"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["___escape.note"])
    }
}
