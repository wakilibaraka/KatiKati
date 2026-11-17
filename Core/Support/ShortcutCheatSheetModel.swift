import Foundation

/// KeyClu-style trigger mode for the Shortcut Cheat Sheet overlay.
enum ShortcutCheatSheetTrigger: String, CaseIterable, Identifiable, Sendable {
    case off
    case doubleTapCommand
    case holdCommand
    var id: String { rawValue }
}

struct ShortcutCheatSheetItem: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let shortcut: String
    let modifiers: KeyModifiers
    let category: String
    let path: [String]
}

struct ShortcutCheatSheetCategory: Equatable, Sendable, Identifiable {
    var id: String { title }
    let title: String
    let items: [ShortcutCheatSheetItem]
}

enum ShortcutCheatSheetBuilder {
    /// Converts `MenuSearchEntry` items (from `AppMenuSearchReader`) and optional KatiKati global
    /// shortcuts into ordered, categorized cheat-sheet groups.
    static func build(
        entries: [MenuSearchEntry],
        katikatiItems: [ShortcutCheatSheetItem] = []
    ) -> [ShortcutCheatSheetCategory] {
        var order: [String] = []
        var grouped: [String: [ShortcutCheatSheetItem]] = [:]

        for entry in entries {
            guard MenuSearch.isSearchable(entry),
                  let shortcut = entry.shortcut, !shortcut.isEmpty,
                  let top = entry.path.first else { continue }
            let mods = modifiers(fromAXMask: entry.modifiers)
            let subtitle = entry.path.count > 2 ? entry.path.dropFirst().dropLast().joined(separator: " › ") : ""
            let item = ShortcutCheatSheetItem(
                id: entry.id,
                title: entry.title,
                subtitle: subtitle,
                shortcut: shortcut,
                modifiers: mods,
                category: top,
                path: entry.path
            )
            if grouped[top] == nil { order.append(top) }
            grouped[top, default: []].append(item)
        }

        var categories = order.compactMap { title -> ShortcutCheatSheetCategory? in
            guard let items = grouped[title], !items.isEmpty else { return nil }
            return ShortcutCheatSheetCategory(title: title, items: items)
        }

        if !katikatiItems.isEmpty {
            categories.append(ShortcutCheatSheetCategory(title: "KatiKati", items: katikatiItems))
        }
        return categories
    }

    static func filter(
        categories: [ShortcutCheatSheetCategory],
        query: String,
        requiredModifiers: KeyModifiers
    ) -> [ShortcutCheatSheetCategory] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return categories.compactMap { cat in
            let matching = cat.items.filter { item in
                let modMatch = requiredModifiers.isEmpty || item.modifiers.isSuperset(of: requiredModifiers)
                guard modMatch else { return false }
                guard !trimmed.isEmpty else { return true }
                return item.title.lowercased().contains(trimmed)
                    || item.shortcut.lowercased().contains(trimmed)
                    || item.subtitle.lowercased().contains(trimmed)
                    || cat.title.lowercased().contains(trimmed)
            }
            return matching.isEmpty ? nil : ShortcutCheatSheetCategory(title: cat.title, items: matching)
        }
    }

    static func exportMarkdown(appName: String, categories: [ShortcutCheatSheetCategory]) -> String {
        var lines: [String] = ["# \(appName) Keyboard Shortcuts", ""]
        for cat in categories {
            lines.append("## \(cat.title)")
            lines.append("")
            lines.append("| Action | Shortcut |")
            lines.append("| :--- | :--- |")
            for item in cat.items {
                let label = item.subtitle.isEmpty ? item.title : "\(item.subtitle) › \(item.title)"
                let escaped = label.replacingOccurrences(of: "|", with: "\\|")
                lines.append("| \(escaped) | `\(item.shortcut)` |")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// `AXMenuItemCmdModifiers`: bit 0 = ⇧, bit 1 = ⌥, bit 2 = ⌃, bit 3 = drops ⌘.
    static func modifiers(fromAXMask mask: Int) -> KeyModifiers {
        var mods: KeyModifiers = []
        if mask & 1 != 0 { mods.insert(.shift) }
        if mask & 2 != 0 { mods.insert(.option) }
        if mask & 4 != 0 { mods.insert(.control) }
        if mask & 8 == 0 { mods.insert(.command) }
        return mods
    }
}
