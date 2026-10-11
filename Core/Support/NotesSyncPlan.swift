import Foundation

/// What the sync runner remembers per note after a successful pass.
struct NotesSyncIndex: Equatable, Sendable, Codable {
    struct Entry: Equatable, Sendable, Codable {
        var fileName: String
        /// The note's `modified` as of the last sync.
        var syncedModified: Date
        /// The file's own modification date as of the last sync (the change *signal*).
        var fileModified: Date
    }
    var entries: [String: Entry] = [:]
}

/// Decides what one sync pass does between the local notes and the iCloud-Drive folder.
/// Pure — no file system, no clock — so the whole decision table is unit-tested and the runner
/// that performs the actions stays thin. Behaviour studied from noty's `SyncPlan` (MIT) and
/// re-derived here; no code copied.
enum NotesSyncPlan {
    struct RemoteFile: Equatable, Sendable {
        var fileName: String
        /// nil when the document has no identity header (written from scratch on a phone).
        var noteID: String?
        /// `modified` declared in the header; `.distantPast` when absent.
        var declaredModified: Date
        var fileModified: Date

        var effectiveModified: Date { max(declaredModified, fileModified) }
    }

    enum Action: Equatable, Sendable {
        case push(noteID: String, existingFileName: String?)
        case pull(fileName: String)
        /// Both sides agree; only the bookkeeping is missing.
        case reindex(noteID: String, fileName: String)
        /// A document with no (or a duplicated) identity: give it a fresh note + write the header back.
        case adopt(fileName: String)
        case deleteLocal(noteID: String)
        case deleteRemote(fileName: String)
        /// Both changed: the loser is preserved by the runner as a conflict copy.
        case conflict(noteID: String, fileName: String, localWins: Bool)
    }

    /// `unresolved` = files present in the folder whose contents could not be read this pass
    /// (iCloud placeholders, failed reads). Deletion follows from evidence a file is gone, never
    /// from not being able to read it. The caller must have established the folder exists — with
    /// no folder every file looks deleted.
    static func actions(notes: [Note], remote: [RemoteFile], unresolved: Set<String>,
                        index: NotesSyncIndex) -> [Action] {
        var out: [Action] = []
        let localIDs = Set(notes.map(\.id))

        var identified: [String: [RemoteFile]] = [:]
        var adoptions: [String] = []
        for file in remote {
            guard let id = file.noteID else { adoptions.append(file.fileName); continue }
            identified[id, default: []].append(file)
        }

        // Two documents can claim one id (duplicating a file copies its header). The indexed name
        // is the note's home; otherwise the newest wins (name as tiebreak). The rest are adopted
        // as new notes.
        var remoteByID: [String: RemoteFile] = [:]
        for id in identified.keys.sorted() {
            let files = identified[id] ?? []
            guard files.count > 1 else { remoteByID[id] = files.first; continue }
            let newest = files.max {
                $0.effectiveModified == $1.effectiveModified ? $0.fileName < $1.fileName
                                                              : $0.effectiveModified < $1.effectiveModified
            }
            let indexed = index.entries[id]?.fileName
            let keeper = files.first { $0.fileName == indexed } ?? newest ?? files[0]
            remoteByID[id] = keeper
            adoptions += files.filter { $0.fileName != keeper.fileName }.map(\.fileName)
        }
        out += adoptions.sorted().map { .adopt(fileName: $0) }

        for note in notes {
            let known = index.entries[note.id]
            guard let file = remoteByID[note.id] else {
                guard let known else { out.append(.push(noteID: note.id, existingFileName: nil)); continue }
                guard !unresolved.contains(known.fileName) else { continue }
                out.append(.deleteLocal(noteID: note.id))
                continue
            }
            // No index entry but the document declares the very timestamp the note has: same
            // version, nothing to resolve (a lost index must not turn every note into a conflict).
            if known == nil, note.modified == file.declaredModified {
                out.append(.reindex(noteID: note.id, fileName: file.fileName))
                continue
            }
            let localChanged = known.map { note.modified > $0.syncedModified } ?? true
            let remoteChanged = known.map { file.fileModified > $0.fileModified } ?? true
            switch (localChanged, remoteChanged) {
            case (false, false): break
            case (true, false): out.append(.push(noteID: note.id, existingFileName: file.fileName))
            case (false, true): out.append(.pull(fileName: file.fileName))
            case (true, true):
                let remoteDate = file.effectiveModified
                guard note.modified != remoteDate else { break }     // same edit seen twice
                out.append(.conflict(noteID: note.id, fileName: file.fileName, localWins: note.modified > remoteDate))
            }
        }

        // Identified documents with no local note: new from elsewhere (pull) or deleted here (remove).
        for file in remoteByID.values.sorted(by: { $0.fileName < $1.fileName }) {
            guard let id = file.noteID, !localIDs.contains(id) else { continue }
            out.append(index.entries[id] == nil ? .pull(fileName: file.fileName) : .deleteRemote(fileName: file.fileName))
        }
        return out
    }
}
