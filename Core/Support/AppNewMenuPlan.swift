import Foundation

/// The "new window / new tab" rows a chip's right-click menu offers, taken from the app's own menu bar.
/// Pure: the Platform reader hands in what the AX tree says, and this decides what deserves a row — so
/// the rule is testable without a single Accessibility call.
enum AppNewMenuPlan {
    struct Entry: Equatable, Sendable {
        var title: String
        /// The menu item's ⌘ character, lowercased ("n", "t"); nil when it has no shortcut.
        var commandKey: String?
        /// `AXMenuItemCmdModifiers`: 0 is ⌘ on its own, so ⇧⌘N (New Folder) is not a new window.
        var modifiers: Int
        var isEnabled: Bool
    }

    /// The macOS Dock lists one or two of these, not the whole File menu.
    static let limit = 3

    /// A row is a "new" action when it is enabled, carries ⌘ alone, and either names a ⌘N/⌘T shortcut or
    /// says "New …" in its own words. The modifier test is what keeps ⇧⌘N's New Folder out; the title
    /// test is what catches an app whose shortcut is not N or T. Neither test reads the language bar,
    /// so a translated app still works.
    static func isNewAction(_ entry: Entry) -> Bool {
        guard entry.isEnabled, !entry.title.isEmpty, entry.modifiers == 0 else { return false }
        if let key = entry.commandKey, key == "n" || key == "t" { return true }
        return entry.title.lowercased().hasPrefix("new ")
    }

    /// Duplicate titles (a File menu that repeats "New Window") collapse; order stays the app's own.
    static func items(from entries: [Entry]) -> [Entry] {
        var seen = Set<String>()
        return Array(entries.filter(isNewAction).filter { seen.insert($0.title).inserted }.prefix(limit))
    }
}
