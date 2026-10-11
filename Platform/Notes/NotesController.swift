import Combine
import Foundation

/// State + editing rules for the notes bar (Phase 7A-7a): the published note list, a debounced
/// autosave, and a single-level undo for deletes. UI-free so it is unit-tested; the bar's views and
/// popup (7A-7b) only bind to it.
@MainActor
final class NotesController: ObservableObject {
    /// Cancels a scheduled callback.
    typealias Cancel = () -> Void
    typealias Scheduler = (TimeInterval, @escaping () -> Void) -> Cancel

    static let autosaveDelay: TimeInterval = 0.25
    static let undoWindow: TimeInterval = 10

    @Published private(set) var notes: [Note] = []
    /// The most recently deleted note, restorable for `undoWindow` seconds.
    @Published private(set) var undoableDeletion: Note?
    @Published private(set) var lastError: String?

    private let store: NotesStore
    private let now: () -> Date
    private let schedule: Scheduler
    /// Called after local notes change on disk (a sync pass can be scheduled).
    var onLocalChange: (() -> Void)?

    private var dirty: Set<String> = []
    private var cancelAutosave: Cancel?
    private var cancelUndo: Cancel?

    init(store: NotesStore, now: @escaping () -> Date = Date.init, schedule: @escaping Scheduler = NotesController.timerScheduler) {
        self.store = store
        self.now = now
        self.schedule = schedule
        reload()
    }

    static let timerScheduler: Scheduler = { delay, work in
        let timer = Timer(timeInterval: delay, repeats: false) { _ in MainActor.assumeIsolated { work() } }
        RunLoop.main.add(timer, forMode: .common)
        return { timer.invalidate() }
    }

    func reload() {
        flush()
        let result = store.loadAll()
        notes = result.notes
        lastError = result.unreadable.isEmpty ? nil : result.unreadable.joined(separator: ", ")
    }

    func note(id: String) -> Note? { notes.first { $0.id == id } }

    // MARK: Editing

    @discardableResult
    func create(body: String = "") -> Note {
        let top = notes.filter { !$0.pinned }.map(\.order).min() ?? 1
        let note = Note(body: body, created: now(), order: top - 1)
        notes = (notes + [note]).inListOrder()
        persist(note)
        return note
    }

    /// Applies an edit immediately in memory; the disk write is debounced.
    func edit(id: String, title: String? = nil, body: String? = nil) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        var note = notes[i]
        if let title { note.title = title }
        if let body { note.body = body }
        guard note != notes[i] else { return }
        note.modified = Note.wholeSeconds(now())
        notes[i] = note
        dirty.insert(id)
        cancelAutosave?()
        cancelAutosave = schedule(Self.autosaveDelay) { [weak self] in self?.flush() }
    }

    func togglePin(id: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].pinned.toggle()
        notes[i].modified = Note.wholeSeconds(now())
        let changed = notes[i]
        notes = notes.inListOrder()
        persist(changed)
    }

    func setArchived(id: String, _ archived: Bool) {
        guard let i = notes.firstIndex(where: { $0.id == id }), notes[i].archived != archived else { return }
        notes[i].archived = archived
        notes[i].modified = Note.wholeSeconds(now())
        persist(notes[i])
    }

    /// Writes every pending edit now (call before quitting / closing the editor).
    func flush() {
        cancelAutosave?()
        cancelAutosave = nil
        let pending = dirty
        dirty = []
        for id in pending { if let n = note(id: id) { persist(n, notify: false) } }
        if !pending.isEmpty { onLocalChange?() }
    }

    // MARK: Delete + undo

    func delete(id: String) {
        guard let note = note(id: id) else { return }
        dirty.remove(id)
        do { try store.delete(id: id) } catch { lastError = error.localizedDescription; return }
        notes.removeAll { $0.id == id }
        undoableDeletion = note
        cancelUndo?()
        cancelUndo = schedule(Self.undoWindow) { [weak self] in self?.undoableDeletion = nil }
        onLocalChange?()
    }

    /// Restores the last deleted note (its original id, so a synced copy re-links).
    func undoDelete() {
        guard var note = undoableDeletion else { return }
        cancelUndo?()
        cancelUndo = nil
        undoableDeletion = nil
        note.modified = Note.wholeSeconds(now())
        notes = (notes + [note]).inListOrder()
        persist(note)
    }

    // MARK: Disk

    private func persist(_ note: Note, notify: Bool = true) {
        do {
            try store.save(note)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            return
        }
        if notify { onLocalChange?() }
    }
}
