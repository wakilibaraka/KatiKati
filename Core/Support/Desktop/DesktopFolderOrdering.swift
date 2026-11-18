import Foundation

/// Pure ordering and block-reorder rules for desktop folder boxes.
enum DesktopFolderOrdering {
    /// Reconciles live folder entries with persisted manual order.
    /// Call only after a successful directory read so temporary permission/unmount gaps never prune saved order.
    static func reconcile(
        entries: [FolderContentsLoader.Entry],
        manualOrder: [String],
        sortMode: DesktopSortMode
    ) -> (ordered: [FolderContentsLoader.Entry], updatedManualOrder: [String]) {
        switch sortMode {
        case .rule(let order):
            return (FolderContentsLoader.sorted(entries, by: order), manualOrder)
        case .manual:
            var byFilename: [String: FolderContentsLoader.Entry] = [:]
            for entry in entries {
                byFilename[entry.url.lastPathComponent] = entry
            }

            var ordered: [FolderContentsLoader.Entry] = []
            var seen: Set<String> = []
            for filename in manualOrder where !seen.contains(filename) {
                if let entry = byFilename[filename] {
                    ordered.append(entry)
                    seen.insert(filename)
                }
            }

            let unseen = FolderContentsLoader.sortedByDateAdded(
                entries.filter { !seen.contains($0.url.lastPathComponent) }
            )
            ordered.append(contentsOf: unseen)
            return (ordered, ordered.map { $0.url.lastPathComponent })
        }
    }

    /// Moves `moving` filenames as an order-preserving block to `targetIndex` in the original list.
    static func reorder(manualOrder: [String], moving: [String], toIndex targetIndex: Int) -> [String] {
        let movingSet = Set(moving)
        let movingBlock = manualOrder.filter { movingSet.contains($0) }
        guard !movingBlock.isEmpty else { return manualOrder }

        var remaining: [String] = []
        var removedBeforeTarget = 0
        for (index, item) in manualOrder.enumerated() {
            if movingSet.contains(item) {
                if index < targetIndex { removedBeforeTarget += 1 }
            } else {
                remaining.append(item)
            }
        }
        let adjustedIndex = min(max(0, targetIndex - removedBeforeTarget), remaining.count)
        remaining.insert(contentsOf: movingBlock, at: adjustedIndex)
        return remaining
    }
}
