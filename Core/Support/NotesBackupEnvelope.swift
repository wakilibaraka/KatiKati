import CommonCrypto
import CryptoKit
import Foundation

/// Port plan #2d (2026-10-27): the password step for backing up notes. Notes on disk are encrypted with a
/// key that lives next to them, so copying those files into a backup would put the key and the notes in the
/// same file. Instead a backup carries the notes *decrypted*, sealed under a key made from a password the
/// person chooses (PBKDF2-HMAC-SHA256 → AES-256-GCM). Restore opens the envelope with the password and
/// re-encrypts each note with the key of the Mac it lands on. Pure; dual-compiled.
///
/// Layout: `KKNB` ‖ version(1) ‖ iterations(UInt32 BE) ‖ salt(16) ‖ AES-GCM combined box.
enum NotesBackupEnvelope {
    enum EnvelopeError: Error, Equatable {
        case malformed
        case wrongPassword
        case newerVersion
    }

    static let currentVersion: UInt8 = 1
    static let defaultIterations = 600_000
    /// Upper bound honoured when opening, so a crafted file cannot make "Restore" spin for minutes.
    static let maxIterations = 5_000_000
    private static let magic = Data("KKNB".utf8)
    private static let saltLength = 16
    private static let headerLength = 4 + 1 + 4 + saltLength

    /// `notes` are the plaintext JSON documents of the notes, in any order.
    static func seal(notes: [Data], password: String, iterations: Int = defaultIterations) throws -> Data {
        let payload = try JSONEncoder().encode(notes)
        let salt = Data((0..<saltLength).map { _ in UInt8.random(in: .min ... .max) })
        guard let key = deriveKey(password: password, salt: salt, iterations: iterations) else { throw EnvelopeError.malformed }
        guard let box = try AES.GCM.seal(payload, using: key).combined else { throw EnvelopeError.malformed }
        var out = magic
        out.append(currentVersion)
        withUnsafeBytes(of: UInt32(iterations).bigEndian) { out.append(contentsOf: $0) }
        out.append(salt)
        out.append(box)
        return out
    }

    static func open(_ envelope: Data, password: String) throws -> [Data] {
        guard envelope.count > headerLength, envelope.prefix(4) == magic else { throw EnvelopeError.malformed }
        let bytes = [UInt8](envelope)
        guard bytes[4] <= currentVersion else { throw EnvelopeError.newerVersion }
        let iterations = Int(bytes[5]) << 24 | Int(bytes[6]) << 16 | Int(bytes[7]) << 8 | Int(bytes[8])
        guard iterations > 0, iterations <= maxIterations else { throw EnvelopeError.malformed }
        let salt = Data(bytes[9..<(9 + saltLength)])
        guard let key = deriveKey(password: password, salt: salt, iterations: iterations) else { throw EnvelopeError.malformed }
        let box: AES.GCM.SealedBox
        do { box = try AES.GCM.SealedBox(combined: Data(bytes[headerLength...])) } catch { throw EnvelopeError.malformed }
        let payload: Data
        do { payload = try AES.GCM.open(box, using: key) } catch { throw EnvelopeError.wrongPassword }
        guard let notes = try? JSONDecoder().decode([Data].self, from: payload) else { throw EnvelopeError.malformed }
        return notes
    }

    private static func deriveKey(password: String, salt: Data, iterations: Int) -> SymmetricKey? {
        var derived = [UInt8](repeating: 0, count: 32)
        // Raw UTF-8 bytes with an explicit length, so a password containing NUL cannot be cut short or over-read.
        let passwordBytes = Array(password.utf8).map { Int8(bitPattern: $0) }
        let status = salt.withUnsafeBytes { saltBytes in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes, passwordBytes.count,
                saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                &derived, derived.count)
        }
        return status == Int32(kCCSuccess) ? SymmetricKey(data: derived) : nil
    }
}
