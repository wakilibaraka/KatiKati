import Foundation

/// Phase 20c — pure ordering and selection rules for the Option+Tab window switcher.
/// Windows are listed most-recently-used first; the first press selects the *previous* window (index 1),
/// as AltTab / the system app switcher do, so a quick Option+Tab flips between the last two windows.
enum WindowSwitcherModel {
    static let mruLimit = 64

    /// Moves `active` to the front of the MRU list and drops windows that no longer exist.
    static func updatedMRU(_ mru: [String], active: String?, alive: Set<String>) -> [String] {
        var next = mru.filter { alive.contains($0) && $0 != active }
        if let active, alive.contains(active) { next.insert(active, at: 0) }
        return Array(next.prefix(mruLimit))
    }

    /// Candidates ordered by MRU position; windows the MRU has not seen keep their incoming order after it.
    static func order(candidates: [String], mru: [String]) -> [String] {
        let rank = Dictionary(mru.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let known = candidates.filter { rank[$0] != nil }.sorted { rank[$0]! < rank[$1]! }
        let unknown = candidates.filter { rank[$0] == nil }
        return known + unknown
    }

    /// Selection when the switcher opens: the previous window, or the last one when going backwards.
    static func initialSelection(count: Int, reverse: Bool) -> Int {
        guard count > 1 else { return 0 }
        return reverse ? count - 1 : 1
    }

    /// Steps the selection by one with wraparound.
    static func step(selection: Int, count: Int, reverse: Bool) -> Int {
        guard count > 0 else { return 0 }
        return (selection + (reverse ? count - 1 : 1)) % count
    }

    /// Grid column count for `count` tiles: one row up to `maxColumns`, then balanced rows.
    static func columns(count: Int, maxColumns: Int = 6) -> Int {
        guard count > 0 else { return 1 }
        guard count > maxColumns else { return count }
        let rows = Int((Double(count) / Double(maxColumns)).rounded(.up))
        return Int((Double(count) / Double(rows)).rounded(.up))
    }
}
