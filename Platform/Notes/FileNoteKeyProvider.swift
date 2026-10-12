import CryptoKit
import Foundation

/// The notes AES key as a 0600 file next to the notes, so opening Notes never shows a Keychain prompt
/// (the prompt appeared whenever the app binary changed — e.g. every ad-hoc build). Trade-off, accepted by
/// the owner: the key sits on disk beside the notes, protected by file permissions and FileVault.
///
/// Migration: an install that already has encrypted notes but no key file reads the old Keychain key
/// **once** (the legacy prompt can appear one last time), writes it to the file, and never touches the
/// Keychain again. A fresh install never touches the Keychain at all.
struct FileNoteKeyProvider: NoteKeyProviding {
    enum KeyFileError: Error { case malformed }

    let keyFile: URL
    /// Called only when notes already exist and there is no key file yet.
    let legacy: NoteKeyProviding?
    let hasExistingNotes: () -> Bool

    static func defaultKeyFile() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KatiKati", isDirectory: true)
            .appendingPathComponent("note.key")
    }

    func loadOrCreateKey() throws -> SymmetricKey {
        let fm = FileManager.default
        if let data = try? Data(contentsOf: keyFile) {
            guard data.count == 32 else { throw KeyFileError.malformed }
            return SymmetricKey(data: data)
        }
        let key: SymmetricKey
        if hasExistingNotes(), let legacy {
            key = try legacy.loadOrCreateKey()
        } else {
            key = NoteCipher.generateKey()
        }
        try fm.createDirectory(at: keyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = key.withUnsafeBytes { Data($0) }
        guard fm.createFile(atPath: keyFile.path, contents: bytes, attributes: [.posixPermissions: 0o600]) else {
            throw KeyFileError.malformed
        }
        return key
    }

    /// True when `directory` already holds at least one note file.
    static func directoryHasNotes(_ directory: URL) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.contains { ($0 as NSString).pathExtension == NotesStore.fileExtension }
    }
}
