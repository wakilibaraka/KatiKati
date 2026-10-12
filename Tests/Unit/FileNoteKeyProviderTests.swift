import CryptoKit
import XCTest
@testable import KatiKati

final class FileNoteKeyProviderTests: XCTestCase {
    private var dir: URL!
    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("fnk-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private struct Counting: NoteKeyProviding {
        let key: SymmetricKey
        let calls: Box
        final class Box { var n = 0 }
        func loadOrCreateKey() throws -> SymmetricKey { calls.n += 1; return key }
    }
    private func bytes(_ k: SymmetricKey) -> Data { k.withUnsafeBytes { Data($0) } }

    func testFreshInstallNeverTouchesLegacyAndKeyIsStable() throws {
        let box = Counting.Box()
        let p = FileNoteKeyProvider(keyFile: dir.appendingPathComponent("note.key"),
                                    legacy: Counting(key: NoteCipher.generateKey(), calls: box),
                                    hasExistingNotes: { false })
        let a = try p.loadOrCreateKey(), b = try p.loadOrCreateKey()
        XCTAssertEqual(bytes(a), bytes(b))
        XCTAssertEqual(box.n, 0)
    }

    func testKeyFileIsOwnerOnly() throws {
        let file = dir.appendingPathComponent("note.key")
        _ = try FileNoteKeyProvider(keyFile: file, legacy: nil, hasExistingNotes: { false }).loadOrCreateKey()
        let perms = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
    }

    func testExistingNotesMigrateTheLegacyKeyOnceThenNeverAskAgain() throws {
        let box = Counting.Box()
        let legacyKey = NoteCipher.generateKey()
        let p = FileNoteKeyProvider(keyFile: dir.appendingPathComponent("note.key"),
                                    legacy: Counting(key: legacyKey, calls: box), hasExistingNotes: { true })
        XCTAssertEqual(bytes(try p.loadOrCreateKey()), bytes(legacyKey))
        XCTAssertEqual(bytes(try p.loadOrCreateKey()), bytes(legacyKey))
        XCTAssertEqual(box.n, 1)
    }

    func testMalformedKeyFileThrowsInsteadOfOverwriting() throws {
        let file = dir.appendingPathComponent("note.key")
        try Data([1, 2, 3]).write(to: file)
        XCTAssertThrowsError(try FileNoteKeyProvider(keyFile: file, legacy: nil, hasExistingNotes: { false }).loadOrCreateKey())
        XCTAssertEqual(try Data(contentsOf: file), Data([1, 2, 3]))
    }

    func testDirectoryHasNotes() throws {
        XCTAssertFalse(FileNoteKeyProvider.directoryHasNotes(dir))
        try Data().write(to: dir.appendingPathComponent("x.note"))
        XCTAssertTrue(FileNoteKeyProvider.directoryHasNotes(dir))
    }
}
