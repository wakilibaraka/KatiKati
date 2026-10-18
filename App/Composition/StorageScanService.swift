import Foundation

/// Walks the disk for the notch Storage page. Runs only while that page is on screen (`scan()` on appear,
/// `cancel()` on disappear), off the main thread, and publishes the running top list as folders finish.
/// Whole-disk reach needs Full Disk Access; `hasFullDiskAccess` probes a TCC-protected folder and the page
/// shows a door to System Settings rather than ever prompting from code.
@MainActor
final class StorageScanService: ObservableObject {
    static let shared = StorageScanService()

    enum State: Equatable { case idle, scanning, done }

    @Published private(set) var items: [StorageItem] = []
    @Published private(set) var state: State = .idle
    @Published private(set) var hasFullDiskAccess = true
    private var task: Task<Void, Never>?

    static let listLimit = 5

    func scan() {
        guard state != .scanning else { return }
        hasFullDiskAccess = Self.probeFullDiskAccess()
        state = .scanning
        items = []
        task = Task.detached(priority: .utility) { [weak self] in
            var found: [StorageItem] = []
            for path in Self.candidates() where !Task.isCancelled {
                found.append(StorageItem(path: path, bytes: Self.size(of: path)))
                let top = StorageScanMath.top(found, limit: Self.listLimit)
                await MainActor.run { self?.items = top }
            }
            let finished = !Task.isCancelled
            await MainActor.run { self?.state = finished ? .done : .idle }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if state == .scanning { state = .idle }
    }

    /// Free bytes on the startup volume, counting what macOS can purge ("available" in Finder's sense).
    nonisolated static func freeBytes() -> Int64 {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    /// `~/Library/Safari` is TCC-protected: it lists only when Full Disk Access is on.
    nonisolated static func probeFullDiskAccess() -> Bool {
        let probe = NSHomeDirectory() + "/Library/Safari"
        return (try? FileManager.default.contentsOfDirectory(atPath: probe)) != nil
    }

    /// Children of the owner's home, the other user folders, /Applications, /Library and /opt, with
    /// ~/Library opened one level further because that is where most of the weight hides.
    nonisolated static func candidates() -> [String] {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        func children(_ dir: String) -> [String] {
            ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).map { (dir as NSString).appendingPathComponent($0) }
        }
        var paths = children(home).filter { $0 != home + "/Library" }
        paths += children(home + "/Library")
        paths += children("/Users").filter { $0 != home && !$0.hasSuffix("/Shared") }
        paths += children("/Applications") + children("/Library") + children("/opt")
        return paths.filter(StorageScanMath.isScannable)
    }

    /// Allocated bytes under `path` (a file counts as itself). Symlinks are not followed.
    nonisolated static func size(of path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            if Task.isCancelled { return total }
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        if total == 0, let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           (attrs[.type] as? FileAttributeType) == .typeRegular {
            total = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        }
        return total
    }
}
