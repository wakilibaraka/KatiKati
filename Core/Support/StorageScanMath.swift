import Foundation

/// Pure logic for the notch Storage page (largest items on the Mac). The platform scanner feeds sizes in;
/// ranking, shares and the "which roots to walk" rule live here so they are testable without a disk.
struct StorageItem: Equatable, Identifiable, Sendable {
    var path: String
    var bytes: Int64
    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
}

enum StorageScanMath {
    /// The largest `limit` items, biggest first; zero-byte items are noise and dropped. Ties keep path order
    /// so the list does not flicker between scans.
    static func top(_ items: [StorageItem], limit: Int) -> [StorageItem] {
        guard limit > 0 else { return [] }
        return Array(items.filter { $0.bytes > 0 }
            .sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.path < $1.path }
            .prefix(limit))
    }

    /// Share (0...1) of the biggest item, for the bar lengths; 0 for an empty list.
    static func share(_ item: StorageItem, of largest: StorageItem?) -> Double {
        guard let largest, largest.bytes > 0 else { return 0 }
        return min(1, max(0, Double(item.bytes) / Double(largest.bytes)))
    }

    /// Folders the whole-disk walk starts from: system-managed or virtual trees are skipped because they
    /// are not the owner's to clear and `/System`, `/Volumes` and `/dev` would double-count or never end.
    static func isScannable(_ path: String) -> Bool {
        let skipped = ["/System", "/Volumes", "/dev", "/cores", "/private/var/vm", "/.Spotlight-V100", "/.fseventsd"]
        return !skipped.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}
