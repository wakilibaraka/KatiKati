import Foundation

/// Local, encrypted note store (Phase 7A-6b): one `<id>.note` file per note in `directory`
/// (`~/Library/Application Support/KatiKati/Notes` in production), each an AES-GCM blob of the
/// note's JSON. Plain `.md` exists only in the opt-in sync folder (see `NoteDocument`).
/// Writes are atomic; unreadable files are skipped and reported, never deleted.
final class NotesStore {
    struct LoadResult {
        var notes: [Note]
        /// File names that could not be decrypted / decoded (wrong key, corruption).
        var unreadable: [String]
    }

    static let fileExtension = "note"

    let directory: URL
    private let cipher: NoteCipher
    private let fileManager: FileManager

    init(directory: URL, keyProvider: NoteKeyProviding, fileManager: FileManager = .default) throws {
        self.directory = directory
        self.cipher = NoteCipher(key: try keyProvider.loadOrCreateKey())
        self.fileManager = fileManager
    }

    static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KatiKati", isDirectory: true)
            .appendingPathComponent("Notes", isDirectory: true)
    }

    private func url(for id: String) -> URL {
        directory.appendingPathComponent(Self.safeName(id)).appendingPathExtension(Self.fileExtension)
    }

    /// Ids are UUIDs we generate, but notes can arrive from a synced file with any `katikati-id`.
    static func safeName(_ id: String) -> String {
        let cleaned = id.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" ? Character(scalar) : "_"
        }
        let name = String(cleaned).prefix(80)
        return name.isEmpty ? "note" : String(name)
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    func save(_ note: Note) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let blob = try cipher.seal(Self.encoder().encode(note))
        try blob.write(to: url(for: note.id), options: .atomic)
    }

    func delete(id: String) throws {
        let target = url(for: id)
        if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
    }

    func loadAll() -> LoadResult {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return LoadResult(notes: [], unreadable: [])
        }
        var notes: [Note] = []
        var unreadable: [String] = []
        for name in names.sorted() where (name as NSString).pathExtension == Self.fileExtension {
            let file = directory.appendingPathComponent(name)
            do {
                let plain = try cipher.open(Data(contentsOf: file))
                notes.append(try Self.decoder().decode(Note.self, from: plain))
            } catch {
                unreadable.append(name)
            }
        }
        return LoadResult(notes: notes.inListOrder(), unreadable: unreadable)
    }

    /// Port plan #2d: every readable note as plaintext JSON, for a password-sealed backup.
    func exportPlaintext() -> [Data] {
        loadAll().notes.compactMap { try? Self.encoder().encode($0) }
    }

    /// Saves backed-up notes under this Mac's own key. A note with the same id is replaced; notes that
    /// are not in the backup stay. Documents that do not decode are skipped; returns how many were saved.
    @discardableResult
    func importPlaintext(_ documents: [Data]) throws -> Int {
        var saved = 0
        for document in documents {
            guard let note = try? Self.decoder().decode(Note.self, from: document) else { continue }
            try save(note)
            saved += 1
        }
        return saved
    }
}
