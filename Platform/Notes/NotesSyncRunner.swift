import Foundation

/// Performs one sync pass between the encrypted local `NotesStore` and the plain-`.md`
/// `NotesSyncFolder`, executing the actions `NotesSyncPlan` decides (Phase 7A-6c). Behaviour studied
/// from noty's `CloudSync` (MIT); written fresh. Errors on one note never abort the pass.
struct NotesSyncRunner {
    struct Report: Equatable {
        var pushed = 0, pulled = 0, adopted = 0, conflicts = 0, deletedLocal = 0, deletedRemote = 0
        var errors: [String] = []
        var folderMissing = false
        /// Local notes exist that cannot be decrypted (wrong key); the pass is skipped so their
        /// synced copies are never mistaken for deletions.
        var localUnreadable = false
    }

    let store: NotesStore
    let folder: NotesSyncFolder
    /// Appended to the title of a preserved conflict copy; injected so callers localize it.
    let conflictSuffix: String
    let now: () -> Date

    init(store: NotesStore, folder: NotesSyncFolder, conflictSuffix: String, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.folder = folder
        self.conflictSuffix = conflictSuffix
        self.now = now
    }

    func run(index: NotesSyncIndex) -> (index: NotesSyncIndex, report: Report) {
        var report = Report()
        var index = index
        // With no folder every file looks deleted; refuse rather than empty the deck.
        guard folder.exists else {
            report.folderMissing = true
            return (index, report)
        }
        let local = store.loadAll()
        guard local.unreadable.isEmpty else {
            report.localUnreadable = true
            return (index, report)
        }
        var notes = local.notes
        let scan = folder.scan()

        var parsed: [String: NoteDocument.Parsed] = [:]
        var remote: [NotesSyncPlan.RemoteFile] = []
        for file in scan.files {
            let p = NoteDocument.parse(file.text, fallbackTitle: NoteFileName.stem(of: file.name), fallbackDate: file.fileModified)
            parsed[file.name] = p
            remote.append(.init(fileName: file.name, noteID: p.hasIdentity ? p.note.id : nil,
                                declaredModified: p.hasDeclaredModified ? p.note.modified : .distantPast,
                                fileModified: file.fileModified))
        }
        let actions = NotesSyncPlan.actions(notes: notes, remote: remote, unresolved: scan.unresolved, index: index)
        var usedNames = Set(scan.files.map(\.name)).union(scan.unresolved)

        func note(_ id: String) -> Note? { notes.first { $0.id == id } }
        func record(_ n: Note, file name: String, fileModified: Date) {
            index.entries[n.id] = .init(fileName: name, syncedModified: n.modified, fileModified: fileModified)
        }
        func saveLocal(_ n: Note) throws {
            try store.save(n)
            if let i = notes.firstIndex(where: { $0.id == n.id }) { notes[i] = n } else { notes.append(n) }
        }
        func push(_ n: Note, existing: String?) throws {
            let name = existing ?? NoteFileName.make(title: n.displayTitle, existing: usedNames)
            let modified = try folder.write(name: name, text: NoteDocument.render(n))
            usedNames.insert(name)
            record(n, file: name, fileModified: modified)
        }
        /// Keeps the losing side of a conflict as a brand-new note (it syncs out on the next pass).
        func preserve(_ loser: Note) throws {
            var copy = loser
            copy.id = UUID().uuidString
            copy.title = (loser.displayTitle + " " + conflictSuffix).trimmingCharacters(in: .whitespaces)
            copy.modified = Note.wholeSeconds(now())
            try saveLocal(copy)
        }

        for action in actions {
            do {
                switch action {
                case let .push(id, existing):
                    guard let n = note(id) else { continue }
                    try push(n, existing: existing)
                    report.pushed += 1
                case let .pull(name):
                    guard let p = parsed[name] else { continue }
                    try saveLocal(p.note)
                    record(p.note, file: name, fileModified: folder.modificationDate(of: name))
                    report.pulled += 1
                case let .reindex(id, name):
                    guard let n = note(id) else { continue }
                    record(n, file: name, fileModified: folder.modificationDate(of: name))
                case let .adopt(name):
                    guard var p = parsed[name]?.note else { continue }
                    if notes.contains(where: { $0.id == p.id }) || index.entries[p.id] != nil { p.id = UUID().uuidString }
                    try saveLocal(p)
                    try push(p, existing: name)       // write the identity header back into the same file
                    report.adopted += 1
                case let .deleteLocal(id):
                    try store.delete(id: id)
                    notes.removeAll { $0.id == id }
                    index.entries[id] = nil
                    report.deletedLocal += 1
                case let .deleteRemote(name):
                    try folder.remove(name: name)
                    index.entries = index.entries.filter { $0.value.fileName != name }
                    report.deletedRemote += 1
                case let .conflict(id, name, localWins):
                    guard let mine = note(id), let theirs = parsed[name]?.note else { continue }
                    if localWins {
                        try preserve(theirs)
                        try push(mine, existing: name)
                    } else {
                        try preserve(mine)
                        try saveLocal(theirs)
                        record(theirs, file: name, fileModified: folder.modificationDate(of: name))
                    }
                    report.conflicts += 1
                }
            } catch {
                report.errors.append("\(action): \(error.localizedDescription)")
            }
        }
        return (index, report)
    }
}

/// Persists the sync index next to the notes (`…/KatiKati/notes-sync-index.json`). Losing it is safe:
/// the plan reindexes matching documents instead of conflicting.
struct NotesSyncIndexStore {
    let url: URL

    static func defaultURL() -> URL {
        NotesStore.defaultDirectory().deletingLastPathComponent().appendingPathComponent("notes-sync-index.json")
    }

    func load() -> NotesSyncIndex {
        guard let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode(NotesSyncIndex.self, from: data) else { return NotesSyncIndex() }
        return index
    }

    func save(_ index: NotesSyncIndex) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(index).write(to: url, options: .atomic)
    }
}
