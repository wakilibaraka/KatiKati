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

    /// Type-to-search: every whitespace-separated word of `query` must appear in the title or app name.
    static func matches(query: String, title: String, appName: String) -> Bool {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let haystack = (title + " " + appName).lowercased()
        return words.allSatisfy { haystack.contains($0) }
    }

    /// Grid column count for `count` tiles: one row up to `maxColumns`, then balanced rows.
    static func columns(count: Int, maxColumns: Int = 6) -> Int {
        guard count > 0 else { return 1 }
        guard count > maxColumns else { return count }
        let rows = Int((Double(count) / Double(maxColumns)).rounded(.up))
        return Int((Double(count) / Double(rows)).rounded(.up))
    }

    /// Up/Down: one row at a time, staying put at the first and last row (Left/Right wrap, rows do not).
    static func rowStep(selection: Int, count: Int, columns: Int, down: Bool) -> Int {
        guard count > 0 else { return 0 }
        let next = selection + (down ? columns : -columns)
        return next >= 0 && next < count ? next : selection
    }
}

// MARK: - Numbered Window Switcher Model (Slice 3.1: SC-AltTabNumbered)

/// Pure digit-based direct navigation and shortcut actions for Window Switcher.
enum NumberedWindowSwitcherModel {
    /// Returns 1-based digit badge for index 0...8 ("1"..."9"); nil for index >= 9.
    static func digitBadge(for index: Int) -> String? {
        guard index >= 0, index < 9 else { return nil }
        return "\(index + 1)"
    }

    /// Resolves target selection index from digit (1...9), clamped to available count.
    static func index(forDigit digit: Int, count: Int) -> Int? {
        guard digit >= 1, digit <= 9, count > 0 else { return nil }
        let idx = digit - 1
        return idx < count ? idx : nil
    }

    /// Maps standard macOS ANSI number row key codes (1-9) to integer digits.
    static func digit(fromKeyCode keyCode: UInt16) -> Int? {
        switch keyCode {
        case 18: return 1 // 1
        case 19: return 2 // 2
        case 20: return 3 // 3
        case 21: return 4 // 4
        case 23: return 5 // 5
        case 22: return 6 // 6
        case 26: return 7 // 7
        case 28: return 8 // 8
        case 25: return 9 // 9
        default: return nil
        }
    }
}
