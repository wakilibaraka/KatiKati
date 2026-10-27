import XCTest

/// 笔记备份的密码信封：往返、错误密码、坏数据、迭代次数上限。
final class NotesBackupEnvelopeTests: XCTestCase {
    /// Few iterations: the tests are about the format, not the cost of the derivation.
    private let fast = 1_000
    private let notes = [Data(#"{"id":"a","body":"one"}"#.utf8), Data(#"{"id":"b","body":"two"}"#.utf8)]

    func testRoundTrip() throws {
        let sealed = try NotesBackupEnvelope.seal(notes: notes, password: "correct horse", iterations: fast)
        XCTAssertEqual(try NotesBackupEnvelope.open(sealed, password: "correct horse"), notes)
    }

    func testEmptyNoteListRoundTrips() throws {
        let sealed = try NotesBackupEnvelope.seal(notes: [], password: "pw", iterations: fast)
        XCTAssertEqual(try NotesBackupEnvelope.open(sealed, password: "pw"), [])
    }

    func testWrongPasswordIsReportedAsSuch() throws {
        let sealed = try NotesBackupEnvelope.seal(notes: notes, password: "right", iterations: fast)
        XCTAssertThrowsError(try NotesBackupEnvelope.open(sealed, password: "wrong")) {
            XCTAssertEqual($0 as? NotesBackupEnvelope.EnvelopeError, .wrongPassword)
        }
    }

    func testPlaintextDoesNotAppearInTheEnvelope() throws {
        let sealed = try NotesBackupEnvelope.seal(notes: notes, password: "pw", iterations: fast)
        XCTAssertNil(sealed.range(of: Data("one".utf8)))
    }

    func testTwoSealsOfTheSameNotesDiffer() throws {
        let a = try NotesBackupEnvelope.seal(notes: notes, password: "pw", iterations: fast)
        let b = try NotesBackupEnvelope.seal(notes: notes, password: "pw", iterations: fast)
        XCTAssertNotEqual(a, b, "fresh salt and nonce every time")
    }

    func testGarbageIsMalformed() {
        for bad in [Data(), Data("nope".utf8), Data(repeating: 0, count: 64)] {
            XCTAssertThrowsError(try NotesBackupEnvelope.open(bad, password: "pw")) {
                XCTAssertEqual($0 as? NotesBackupEnvelope.EnvelopeError, .malformed)
            }
        }
    }

    func testTamperedCiphertextFailsAuthentication() throws {
        var sealed = try NotesBackupEnvelope.seal(notes: notes, password: "pw", iterations: fast)
        sealed[sealed.count - 1] ^= 0xFF
        XCTAssertThrowsError(try NotesBackupEnvelope.open(sealed, password: "pw")) {
            XCTAssertEqual($0 as? NotesBackupEnvelope.EnvelopeError, .wrongPassword)
        }
    }

    func testNewerVersionIsRefused() throws {
        var sealed = try NotesBackupEnvelope.seal(notes: notes, password: "pw", iterations: fast)
        sealed[4] = NotesBackupEnvelope.currentVersion + 1
        XCTAssertThrowsError(try NotesBackupEnvelope.open(sealed, password: "pw")) {
            XCTAssertEqual($0 as? NotesBackupEnvelope.EnvelopeError, .newerVersion)
        }
    }

    func testAbsurdIterationCountIsRefusedWithoutDerivingAKey() throws {
        var sealed = try NotesBackupEnvelope.seal(notes: notes, password: "pw", iterations: fast)
        sealed.replaceSubrange(5..<9, with: [0xFF, 0xFF, 0xFF, 0xFF])
        XCTAssertThrowsError(try NotesBackupEnvelope.open(sealed, password: "pw")) {
            XCTAssertEqual($0 as? NotesBackupEnvelope.EnvelopeError, .malformed)
        }
    }

    func testUnicodePasswordWorks() throws {
        let sealed = try NotesBackupEnvelope.seal(notes: notes, password: "pässwörd🔑", iterations: fast)
        XCTAssertEqual(try NotesBackupEnvelope.open(sealed, password: "pässwörd🔑"), notes)
    }
}
