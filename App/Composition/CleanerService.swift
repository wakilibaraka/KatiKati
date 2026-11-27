import AppKit
import Foundation

/// 55d: the review-first cache cleaner. Nothing is deleted automatically and there is no timer: `scan()`
/// builds a list from `CleanupPlan`, the notch page shows it in a confirmation, and only then does `clean`
/// move the chosen folders to the Trash (`trashItem`, never `unlink`). Caches only, never personal files.
@MainActor
final class CleanerService: ObservableObject {
    static let shared = CleanerService()

    struct Outcome: Equatable {
        var moved: Int
        var failed: Int
        var bytes: Int64
    }

    @Published private(set) var candidates: [CleanupCandidate] = []
    @Published private(set) var leftoverCandidates: [CleanupCandidate] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isScanningLeftovers = false

    func scan(completion: (() -> Void)? = nil) {
        guard !isScanning else { return }
        isScanning = true
        Task.detached(priority: .utility) { [weak self] in
            let home = NSHomeDirectory()
            var found: [CleanupCandidate] = []
            let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey]
            for root in CleanupPlan.roots(home: home) {
                let children = (try? FileManager.default.contentsOfDirectory(
                    at: URL(fileURLWithPath: root), includingPropertiesForKeys: Array(keys),
                    options: [.skipsHiddenFiles]
                )) ?? []
                for child in children {
                    guard let values = try? child.resourceValues(forKeys: keys),
                          values.isDirectory == true, let modified = values.contentModificationDate,
                          !CleanupPlan.isExcluded(child.path) else { continue }
                    let bytes = StorageScanService.size(of: child.path)
                    found.append(CleanupCandidate(path: child.path, bytes: bytes, lastModified: modified))
                }

            }
            let plan = CleanupPlan.candidates(from: found)
            await MainActor.run {
                self?.candidates = plan
                self?.isScanning = false
                completion?()
            }
        }

    }

    func scanLeftovers(forAppAt appURL: URL, completion: (() -> Void)? = nil) {
        guard !isScanningLeftovers,
              let bundle = Bundle(url: appURL),
              let bundleID = bundle.bundleIdentifier,
              !AppLeftoverScanPlan.isProtected(bundleID: bundleID) else { return }
        let appName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
        isScanningLeftovers = true
        leftoverCandidates = []
        Task.detached(priority: .utility) { [weak self] in
            let home = NSHomeDirectory()
            let existing = AppLeftoverScanPlan.targetDirectories(home: home).flatMap { root in
                (try? FileManager.default.contentsOfDirectory(atPath: root))?.map {
                    (root as NSString).appendingPathComponent($0)
                } ?? []
            }
            let paths = AppLeftoverScanPlan.candidatePaths(
                home: home, existingPaths: existing, bundleID: bundleID, appName: appName)
            let keys: Set<URLResourceKey> = [.contentModificationDateKey]
            let found = paths.compactMap { path -> CleanupCandidate? in
                let url = URL(fileURLWithPath: path)
                guard let modified = try? url.resourceValues(forKeys: keys).contentModificationDate else { return nil }
                return CleanupCandidate(path: path, bytes: StorageScanService.size(of: path), lastModified: modified)
            }.filter { $0.bytes > 0 }
            await MainActor.run {
                self?.leftoverCandidates = found.sorted {
                    $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.path < $1.path
                }
                self?.isScanningLeftovers = false
                completion?()
            }
        }
    }

    /// Moves each candidate to the Trash. A failure is counted, never retried with a permanent delete.
    func clean(_ selected: [CleanupCandidate]) -> Outcome {
        var outcome = Outcome(moved: 0, failed: 0, bytes: 0)
        var failedPaths = Set<String>()
        let home = NSHomeDirectory()
        let allowedRoots = CleanupPlan.roots(home: home).map { URL(fileURLWithPath: $0, isDirectory: true) }
            + [URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("Library", isDirectory: true)]
        for candidate in selected {
            let url = URL(fileURLWithPath: candidate.path)
            guard AppRemovalPlanner.isWithinAllowedBoundary(url, allowedRoots: allowedRoots) else {
                outcome.failed += 1
                failedPaths.insert(candidate.path)
                continue
            }
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                outcome.moved += 1
                outcome.bytes += candidate.bytes
            } catch {
                outcome.failed += 1
                failedPaths.insert(candidate.path)
            }
        }
        let selectedPaths = Set(selected.map(\.path))
        candidates.removeAll { selectedPaths.contains($0.path) && !failedPaths.contains($0.path) }
        return outcome
    }
}
