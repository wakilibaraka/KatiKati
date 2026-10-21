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

    /// Short free-space label for the closed notch's narrow slot: "30 GB", "1.2 TB", "0 GB".
    static func compact(_ bytes: Int64) -> String {
        let gb = Double(max(0, bytes)) / 1_000_000_000
        return gb >= 1000 ? String(format: "%.1f TB", gb / 1000) : "\(Int(gb)) GB"
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

/// What kind of personal file an item is, by extension. Only the kinds the Files half of the Storage page
/// lists; anything else (code, app data, system files) is not an owner's "file" and returns nil.
enum StorageCategory: CaseIterable, Sendable {
    case photos, video, music, documents, archives

    static func of(path: String) -> StorageCategory? {
        let ext = (path as NSString).pathExtension.lowercased()
        return allCases.first { $0.extensions.contains(ext) }
    }

    var extensions: Set<String> {
        switch self {
        case .photos: return ["jpg", "jpeg", "png", "heic", "heif", "raw", "cr2", "nef", "arw", "dng", "tiff", "gif", "psd"]
        case .video: return ["mov", "mp4", "m4v", "mkv", "avi", "webm"]
        case .music: return ["mp3", "m4a", "aac", "flac", "wav", "aiff", "alac"]
        case .documents: return ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "epub"]
        case .archives: return ["zip", "dmg", "iso", "tar", "gz", "7z", "rar", "pkg"]
        }
    }

    var symbol: String {
        switch self {
        case .photos: return "photo"
        case .video: return "film"
        case .music: return "music.note"
        case .documents: return "doc.text"
        case .archives: return "archivebox"
        }
    }
}

/// 55d: one cache/log folder the cleaner may offer. Direct children only, so a whole cache tree moves as a
/// unit and the Trash is still a single Put Back.
struct CleanupCandidate: Equatable, Identifiable, Sendable {
    var path: String
    var bytes: Int64
    var lastModified: Date

    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
}

/// 55d: which folders a review-first cleaner may list. Caches and logs only, never documents, and only
/// entries that are both stale and big enough to be worth a decision. The service moves them to the Trash;
/// nothing here ever unlinks.
enum CleanupPlan {
    static let minAgeDays = 7
    static let minBytes: Int64 = 50_000_000

    /// Roots whose direct children are rebuildable. The app's own caches are filtered out per entry.
    static func roots(home: String) -> [String] {
        [home + "/Library/Caches", home + "/Library/Logs", home + "/Library/Developer/Xcode/DerivedData",
         home + "/.cache", home + "/.npm", home + "/.gradle"]
    }

    /// Apple's own caches belong to running system services, ours would be recreated under us, and a
    /// `noindex` entry is a marker, not data.
    static func isExcluded(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent.lowercased()
        guard !name.isEmpty else { return true }
        if name.hasPrefix("com.apple.") || name.hasPrefix("com.katikati.") { return true }
        return name.hasSuffix(".noindex")
    }

    /// The list the confirmation shows: stale, big enough, not excluded, biggest first.
    static func candidates(from entries: [CleanupCandidate], now: Date = Date()) -> [CleanupCandidate] {
        let cutoff = now.addingTimeInterval(-Double(minAgeDays) * 86_400)
        return entries
            .filter { $0.bytes >= minBytes && $0.lastModified <= cutoff && !isExcluded($0.path) }
            .sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.path < $1.path }
    }

    static func totalBytes(_ candidates: [CleanupCandidate]) -> Int64 {
        candidates.reduce(0) { $0 + max(0, $1.bytes) }
    }
}

extension StorageScanMath {
    /// Folders the Files half walks: where a person keeps their own things.
    static func personalRoots(home: String) -> [String] {
        ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music"].map { home + "/" + $0 }
    }

    /// Known space hogs for the Developer & Cache half: caches, Xcode and simulator data, package-manager
    /// caches, the Trash. Fixed paths, so this half needs no deep walk to find them.
    static func developerTargets(home: String) -> [String] {
        [
            "/Library/Caches", "/.Trash", "/Library/Developer/Xcode/DerivedData",
            "/Library/Developer/Xcode/Archives", "/Library/Developer/Xcode/iOS DeviceSupport",
            "/Library/Developer/CoreSimulator", "/Library/Logs", "/Library/Application Support/MobileSync/Backup",
            "/Library/Containers/com.docker.docker", "/.npm", "/.cache", "/.gradle", "/.cargo", "/.m2", "/.pnpm-store",
            "/Library/Application Support/Code/CachedData",
        ].map { home + $0 }
    }
}
