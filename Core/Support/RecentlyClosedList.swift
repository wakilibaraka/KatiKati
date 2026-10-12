import Foundation

// Phase 8a — pure "recently closed apps" list behind the drawer/taskbar menu's restore entry.
//
// Newest first, deduplicated, capped. Launching an app (by any route) removes it; apps that must never
// be offered (KatiKati itself, the Finder, anything already running) are filtered by the caller via
// `visible(excluding:)`. Pure and dual-compiled so ordering, dedupe and the cap are unit-tested; the
// NSWorkspace observation lives in the app-only `RecentlyClosedStore`.

struct RecentlyClosedList: Equatable {
    static let capacity = 8
    private(set) var bundleIDs: [String]

    init(bundleIDs: [String] = []) {
        var seen = Set<String>()
        self.bundleIDs = bundleIDs.filter { !$0.isEmpty && seen.insert($0).inserted }
        self.bundleIDs = Array(self.bundleIDs.prefix(Self.capacity))
    }

    /// An app quit: it moves to the front.
    mutating func noteClosed(_ id: String) {
        guard !id.isEmpty else { return }
        bundleIDs.removeAll { $0 == id }
        bundleIDs.insert(id, at: 0)
        if bundleIDs.count > Self.capacity { bundleIDs.removeLast(bundleIDs.count - Self.capacity) }
    }

    /// An app started: it is no longer "closed".
    mutating func noteLaunched(_ id: String) {
        bundleIDs.removeAll { $0 == id }
    }

    func visible(excluding excluded: Set<String>) -> [String] {
        bundleIDs.filter { !excluded.contains($0) }
    }
}
