import Foundation

// Phase 8d — pure "is something downloading?" rules for the Downloads chip's activity badge.
//
// Browsers write a download as an opaque partial file (`.download` Safari bundle, `.crdownload`
// Chrome/Edge/Brave, `.part` Firefox, `.opdownload` Opera). The real percentage can't be read
// reliably, so the owner-chosen design is an honest "N downloads active" pulse: a partial file counts
// as active while it was written to recently. Pure (no FileManager, no clock — callers pass entries and
// `now`) and dual-compiled so the heuristic is unit-tested.

enum DownloadActivity {
    static let partialExtensions: Set<String> = ["download", "crdownload", "part", "opdownload", "partial"]
    /// A partial untouched for longer than this is a stalled/abandoned download, not an active one.
    static let activeWindow: TimeInterval = 10

    struct Entry: Equatable {
        var name: String
        /// Newest modification time of the item (for a bundle: the newest of the bundle and its contents).
        var modified: Date
    }

    static func isPartial(_ name: String) -> Bool {
        partialExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// How many partial files were written to within `activeWindow` of `now`.
    static func activeCount(_ entries: [Entry], now: Date) -> Int {
        entries.filter { isPartial($0.name) && now.timeIntervalSince($0.modified) <= activeWindow }.count
    }
}
