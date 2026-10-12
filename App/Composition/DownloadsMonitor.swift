import Foundation

// Phase 8d — watches ~/Downloads for in-progress browser downloads and publishes how many are active.
//
// Zero idle cost: a directory vnode watcher fires only when entries are created/renamed/removed, and a
// 2 s re-scan runs *only while* at least one download is active (a growing file doesn't fire a directory
// event, and "finished" is detected by the file stopping/renaming). No surface holding it = no watcher.
//
// Privacy: reading ~/Downloads can raise the system's access prompt, so the badge only retains this
// monitor once the user has opened the folder (`PinnedFolderStore.isUnopenedSeed` is false) — it never
// reads a folder nobody asked it to. No new permission, no new dependency.

@MainActor
final class DownloadsMonitor: ObservableObject {
    static let shared = DownloadsMonitor()

    @Published private(set) var activeCount = 0

    private var gate = LiveTickGate()
    private var source: DispatchSourceFileSystemObject?
    private var rescan: Timer?
    private let scanQueue = DispatchQueue(label: "com.katikati.downloads-scan", qos: .utility)

    private var directory: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    func retain() {
        if gate.retain() { start() }
    }

    func release() {
        if gate.release() { stop() }
    }

    private func start() {
        guard let dir = directory else { return }
        // `open()` on a privacy-protected folder can block while the system asks for access, so it never
        // runs on the main thread.
        scanQueue.async { [weak self] in
            let fd = open(dir.path, O_EVTONLY)
            guard fd >= 0 else { return }
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            src.setCancelHandler { close(fd) }
            DispatchQueue.main.async {
                guard let self, self.gate.isActive, self.source == nil else { src.cancel(); return }
                src.setEventHandler { [weak self] in self?.scan() }
                src.resume()
                self.source = src
                self.scan()
            }
        }
    }

    private func stop() {
        source?.cancel(); source = nil
        rescan?.invalidate(); rescan = nil
        activeCount = 0
    }

    private func scan() {
        guard let dir = directory else { return }
        scanQueue.async { [weak self] in
            let count = Self.activeDownloads(in: dir, now: Date())
            DispatchQueue.main.async { self?.apply(count) }
        }
    }

    private func apply(_ count: Int) {
        guard gate.isActive else { return }
        if count != activeCount { activeCount = count }
        if count > 0, rescan == nil {
            let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.scan() }
            }
            RunLoop.main.add(t, forMode: .common)
            rescan = t
        } else if count == 0 {
            rescan?.invalidate(); rescan = nil
        }
    }

    /// Reads the folder (off the main thread): partial entries only, newest mtime of a bundle's contents.
    nonisolated private static func activeDownloads(in dir: URL, now: Date) -> Int {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: []) else { return 0 }
        var entries: [DownloadActivity.Entry] = []
        for url in items where DownloadActivity.isPartial(url.lastPathComponent) {
            let values = try? url.resourceValues(forKeys: Set(keys))
            var modified = values?.contentModificationDate ?? .distantPast
            if values?.isDirectory == true,
               let inner = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey], options: []) {
                for child in inner {
                    if let m = (try? child.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, m > modified { modified = m }
                }
            }
            entries.append(.init(name: url.lastPathComponent, modified: modified))
        }
        return DownloadActivity.activeCount(entries, now: now)
    }
}
