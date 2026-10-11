import CryptoKit
import Foundation

/// At-rest encryption for local notes (Phase 7A-6b): AES-256-GCM, random nonce per seal, the
/// combined box (nonce ‖ ciphertext ‖ tag) is the stored blob. The key lives in the Keychain
/// (`KeychainNoteKeyProvider`); this type is pure so it is fully unit-tested.
struct NoteCipher {
    enum CipherError: Error, Equatable { case malformed, authenticationFailed }

    private let key: SymmetricKey

    init(key: SymmetricKey) { self.key = key }

    static func generateKey() -> SymmetricKey { SymmetricKey(size: .bits256) }

    func seal(_ plaintext: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(plaintext, using: key).combined else { throw CipherError.malformed }
        return combined
    }

    func open(_ blob: Data) throws -> Data {
        let box: AES.GCM.SealedBox
        do { box = try AES.GCM.SealedBox(combined: blob) } catch { throw CipherError.malformed }
        do { return try AES.GCM.open(box, using: key) } catch { throw CipherError.authenticationFailed }
    }
}

/// Where the 256-bit note key comes from. Production = Keychain; tests = in-memory.
protocol NoteKeyProviding {
    func loadOrCreateKey() throws -> SymmetricKey
}

struct InMemoryNoteKeyProvider: NoteKeyProviding {
    let key: SymmetricKey
    init(key: SymmetricKey = NoteCipher.generateKey()) { self.key = key }
    func loadOrCreateKey() throws -> SymmetricKey { key }
}
