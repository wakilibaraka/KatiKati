import CryptoKit
import Darwin
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
        if fm.fileExists(atPath: keyFile.path) { return try readExistingKey() }
        let key: SymmetricKey
        if hasExistingNotes(), let legacy {
            key = try legacy.loadOrCreateKey()
        } else {
            key = NoteCipher.generateKey()
        }
        try fm.createDirectory(at: keyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = key.withUnsafeBytes { Data($0) }
        let tempURL = keyFile.deletingLastPathComponent()
            .appendingPathComponent(".note.key.\(UUID().uuidString).tmp")
        let fd = Darwin.open(tempURL.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer {
            _ = Darwin.unlink(tempURL.path)
        }
        do {
            try bytes.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { throw KeyFileError.malformed }
                var offset = 0
                while offset < raw.count {
                    let written = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                    guard written > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                    offset += written
                }
            }
            guard Darwin.fchmod(fd, mode_t(S_IRUSR | S_IWUSR)) == 0, Darwin.fsync(fd) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            Darwin.close(fd)
        } catch {
            Darwin.close(fd)
            throw error
        }
        if Darwin.link(tempURL.path, keyFile.path) != 0 {
            if errno == EEXIST { return try readExistingKey() }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return key
    }

    private func readExistingKey() throws -> SymmetricKey {
        let data = try Data(contentsOf: keyFile)
        guard data.count == 32 else { throw KeyFileError.malformed }
        return SymmetricKey(data: data)
    }

    /// True when `directory` already holds at least one note file.
    static func directoryHasNotes(_ directory: URL) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.contains { ($0 as NSString).pathExtension == NotesStore.fileExtension }
    }
}
