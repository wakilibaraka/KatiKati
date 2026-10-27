import Foundation

/// Port plan #3 (2026-10-27): search the frontmost app's menu bar from the command bar (`m ` / `menu `).
/// Pure: the Platform reader (`AppMenuSearchReader`) walks the AX tree into these values, and this decides
/// what matches and in which order — so ranking and shortcut glyphs are testable without Accessibility.
/// Behaviour follows Tinycast's menu-search spec (design reference only; its code is AGPL and not used).

/// One menu item, addressed by its title path from the menu bar down ("File", "Export", "PDF…").
struct MenuSearchEntry: Equatable, Sendable, Identifiable {
    var path: [String]
    /// `AXMenuItemCmdChar`, lowercased; nil when the item has no key equivalent.
    var commandKey: String?
    /// `AXMenuItemCmdModifiers`: 0 is ⌘ alone; bit 0 adds ⇧, bit 1 ⌥, bit 2 ⌃, bit 3 drops ⌘.
    var modifiers: Int
    var isEnabled: Bool

    var id: String { path.joined(separator: "\u{1F}") }
    var title: String { path.last ?? "" }
    /// "File › Export" — where the item lives, shown under its title.
    var breadcrumb: String { path.dropLast().joined(separator: " › ") }
    var shortcut: String? { MenuSearch.shortcutGlyphs(commandKey: commandKey, modifiers: modifiers) }
}

enum MenuSearch {
    /// Walk bounds: deep enough for File › Export › Format, small enough that one walk of a large app
    /// (Xcode, Photoshop) stays under a second at the reader's 0.35 s per-element timeout.
    static let maxDepth = 4
    static let maxItems = 1500
    static let resultLimit = 40

    /// ⌃⌥⇧⌘ order, as macOS draws menus. Nil for no key equivalent.
    static func shortcutGlyphs(commandKey: String?, modifiers: Int) -> String? {
        guard let key = commandKey?.trimmingCharacters(in: .whitespaces), !key.isEmpty else { return nil }
        var glyphs = ""
        if modifiers & 4 != 0 { glyphs += "⌃" }
        if modifiers & 2 != 0 { glyphs += "⌥" }
        if modifiers & 1 != 0 { glyphs += "⇧" }
        if modifiers & 8 == 0 { glyphs += "⌘" }
        return glyphs + key.uppercased()
    }

    /// Titles that are never worth a row: separators come through as empty titles, and the Apple menu
    /// (About This Mac, Restart…) belongs to the system, not to the app being searched.
    static func isSearchable(_ entry: MenuSearchEntry) -> Bool {
        guard let first = entry.path.first, !entry.title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return first != "Apple" && first != ""
    }

    /// Best first. The leaf title is scored on its own; a match only in the path ("export" finding
    /// File › Export › PDF…) ranks below any title match. Disabled items sink to the end, and ties keep
    /// the app's own menu order. An empty query lists the menus in order.
    static func rank(_ query: String, in entries: [MenuSearchEntry], limit: Int = resultLimit) -> [MenuSearchEntry] {
        let searchable = entries.filter(isSearchable)
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            return Array((searchable.filter(\.isEnabled) + searchable.filter { !$0.isEnabled }).prefix(limit))
        }
        let scored: [(offset: Int, entry: MenuSearchEntry, score: Int)] = searchable.enumerated().compactMap { offset, entry in
            if let s = LauncherSearch.score(query: q, name: entry.title) { return (offset, entry, s + 1000) }
            if let s = LauncherSearch.score(query: q, name: entry.path.joined(separator: " ")) { return (offset, entry, s) }
            return nil
        }
        return scored.sorted { a, b in
            if a.entry.isEnabled != b.entry.isEnabled { return a.entry.isEnabled }
            if a.score != b.score { return a.score > b.score }
            return a.offset < b.offset
        }
        .prefix(limit)
        .map(\.entry)
    }
}
