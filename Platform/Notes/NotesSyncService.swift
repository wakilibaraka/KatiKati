import Foundation

/// Coalesces sync-pass requests (Phase 7A-7c): one pass runs after `delay` of quiet; requests made
/// while a pass is in flight collapse into a single follow-up pass. No timers run while idle.
@MainActor
final class SyncPassScheduler {
    private let delay: TimeInterval
    private let schedule: NotesController.Scheduler
    private let perform: (_ done: @escaping @Sendable () -> Void) -> Void
    private var cancelTimer: NotesController.Cancel?
    private var running = false
    private var rerun = false

    var isRunning: Bool { running }

    init(delay: TimeInterval, schedule: @escaping NotesController.Scheduler,
         perform: @escaping (_ done: @escaping @Sendable () -> Void) -> Void) {
        self.delay = delay
        self.schedule = schedule
        self.perform = perform
    }

    func request() {
        if running { rerun = true; return }
        cancelTimer?()
        cancelTimer = schedule(delay) { [weak self] in self?.start() }
    }

    func cancel() {
        cancelTimer?()
        cancelTimer = nil
        rerun = false
    }

    private func start() {
        cancelTimer = nil
        running = true
        perform { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.running = false
                if self.rerun { self.rerun = false; self.request() }
            }
        }
    }
}

/// Keeps the local notes and the iCloud-Drive folder in step while sync is enabled: a pass on start,
/// after local edits (debounced), and when the folder changes (file-system event, no polling).
@MainActor
final class NotesSyncService {
    private let controller: NotesController
    private let store: NotesStore
    private let indexStore: NotesSyncIndexStore
    private let folder: NotesSyncFolder
    private let conflictSuffix: String
    private var scheduler: SyncPassScheduler!
    private var watcher: DispatchSourceFileSystemObject?
    private(set) var lastReport: NotesSyncRunner.Report?

    init(controller: NotesController, store: NotesStore, indexStore: NotesSyncIndexStore = NotesSyncIndexStore(url: NotesSyncIndexStore.defaultURL()),
         folder: NotesSyncFolder = NotesSyncFolder(url: NotesSyncFolder.defaultICloudURL()), conflictSuffix: String) {
        self.controller = controller
        self.store = store
        self.indexStore = indexStore
        self.folder = folder
        self.conflictSuffix = conflictSuffix
        self.scheduler = SyncPassScheduler(delay: 1.5, schedule: NotesController.timerScheduler) { [weak self] done in
            self?.runPass(done: done) ?? done()
        }
    }

    func start() {
        do { try folder.createIfNeeded() } catch { return }
        controller.onLocalChange = { [weak self] in self?.scheduler.request() }
        watchFolder()
        scheduler.request()
    }

    func stop() {
        scheduler.cancel()
        controller.onLocalChange = nil
        watcher?.cancel()
        watcher = nil
    }

    private func watchFolder() {
        guard watcher == nil else { return }
        let fd = open(folder.url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.scheduler.request() } }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    private func runPass(done: @escaping @Sendable () -> Void) {
        controller.flush()
        let runner = NotesSyncRunner(store: store, folder: folder, conflictSuffix: conflictSuffix)
        let indexStore = self.indexStore
        let index = indexStore.load()
        let job = PassJob(runner: runner, index: index, done: done)
        Task.detached(priority: .utility) {
            let result = job.runner.run(index: job.index)
            await MainActor.run {
                try? indexStore.save(result.index)
                self.lastReport = result.report
                let changed = result.report.pulled + result.report.adopted + result.report.conflicts + result.report.deletedLocal
                if changed > 0 { self.controller.reload() }
                job.done()
            }
        }
    }
}

/// Carries the runner (value type over thread-safe file IO) and completion to the sync queue and back.
private struct PassJob: @unchecked Sendable {
    let runner: NotesSyncRunner
    let index: NotesSyncIndex
    let done: () -> Void
}
