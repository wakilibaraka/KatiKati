import Foundation

// Dropover-style shelf — the pure model and policy. `ShelfStore` (app layer) owns persistence and file
// I/O; everything that is a decision (ordering, pinning, expiry, migration) lives here and is unit-tested.
// Dual-compiled.

/// How dropped files are kept.
enum ShelfStorage: String, CaseIterable, Sendable {
    /// The shelf remembers the path; the file stays where it is (default).
    case reference
    /// The shelf copies the file into an app-owned folder so it survives the original being moved.
    case copy
}

struct ShelfItem: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var path: String
    var isPinned: Bool
    var addedAt: Date
    /// `true` when `path` is a copy owned by the shelf (deleted on removal).
    var isOwnedCopy: Bool

    init(id: UUID = UUID(), path: String, isPinned: Bool = false, addedAt: Date, isOwnedCopy: Bool = false) {
        self.id = id
        self.path = path
        self.isPinned = isPinned
        self.addedAt = addedAt
        self.isOwnedCopy = isOwnedCopy
    }
}

enum ShelfPolicy {
    static let expiryChoices = [1, 3, 7]

    /// Pinned first, then newest first. Stable for equal dates.
    static func ordered(_ items: [ShelfItem]) -> [ShelfItem] {
        items.enumerated().sorted { a, b in
            if a.element.isPinned != b.element.isPinned { return a.element.isPinned }
            if a.element.addedAt != b.element.addedAt { return a.element.addedAt > b.element.addedAt }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// Adds new paths (deduped, empties dropped). A path already on the shelf is moved to "now" and keeps
    /// its pin. Returns the items unchanged-ordered; use `ordered` for display.
    static func stashing(_ items: [ShelfItem], adding entries: [(path: String, isOwnedCopy: Bool)], now: Date) -> [ShelfItem] {
        var result = items
        var seen = Set<String>()
        for entry in entries where !entry.path.isEmpty && seen.insert(entry.path).inserted {
            if let i = result.firstIndex(where: { $0.path == entry.path }) {
                result[i].addedAt = now
            } else {
                result.append(ShelfItem(path: entry.path, addedAt: now, isOwnedCopy: entry.isOwnedCopy))
            }
        }
        return result
    }

    static func togglingPin(_ items: [ShelfItem], id: UUID) -> [ShelfItem] {
        items.map { var i = $0; if i.id == id { i.isPinned.toggle() }; return i }
    }

    static func removing(_ items: [ShelfItem], path: String) -> [ShelfItem] {
        items.filter { $0.path != path }
    }

    /// Unpinned items older than `days` are expired; pinned items never are.
    static func expired(_ items: [ShelfItem], now: Date, days: Int) -> (kept: [ShelfItem], dropped: [ShelfItem]) {
        let limit = TimeInterval(max(0, days)) * 86_400
        var kept: [ShelfItem] = [], dropped: [ShelfItem] = []
        for item in items {
            if !item.isPinned, now.timeIntervalSince(item.addedAt) > limit { dropped.append(item) } else { kept.append(item) }
        }
        return (kept, dropped)
    }

    static func clearingUnpinned(_ items: [ShelfItem]) -> (kept: [ShelfItem], dropped: [ShelfItem]) {
        (items.filter(\.isPinned), items.filter { !$0.isPinned })
    }

    /// Old installs stored a bare newest-first path list; keep that order via descending timestamps.
    static func migrated(paths: [String], now: Date) -> [ShelfItem] {
        paths.enumerated().map { ShelfItem(path: $1, addedAt: now.addingTimeInterval(-Double($0))) }
    }
}
