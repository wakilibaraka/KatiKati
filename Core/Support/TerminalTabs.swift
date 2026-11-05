import Foundation

/// Dictionary + Terminal step 1: the tab model of the terminal panel. Pure value type — no SwiftTerm, no AppKit —
/// so add / close / select, titles and the tab cap are unit-tested without a shell. The panel owns one
/// `TerminalSession` per `Tab.id`; this only decides which tabs exist and which one is selected.
struct TerminalTabs: Equatable, Sendable {
    struct Tab: Equatable, Identifiable, Sendable {
        let id: UUID
        /// Last title the shell set (OSC 0/2); empty until it sets one.
        var title: String
        /// Last working directory the shell reported; nil until known. Used to open a sibling tab in place.
        var directory: String?

        /// Tab label: the shell's title, else the directory's last component, else "Shell".
        var displayTitle: String {
            if !title.isEmpty { return title }
            if let directory, !directory.isEmpty {
                let name = (directory as NSString).lastPathComponent
                return name.isEmpty ? directory : name
            }
            return "Shell"
        }
    }

    /// Most tabs one panel holds; a further `add` is refused (the caller keeps the current tab).
    static let maxTabs = 8

    private(set) var tabs: [Tab]
    private(set) var selectedID: UUID

    /// A panel always has at least one tab.
    init(first: Tab = Tab(id: UUID(), title: "", directory: nil)) {
        tabs = [first]
        selectedID = first.id
    }

    var selected: Tab { tabs.first { $0.id == selectedID } ?? tabs[0] }
    var canAdd: Bool { tabs.count < Self.maxTabs }

    /// Appends a tab right after the selected one and selects it. The new tab inherits the selected tab's
    /// directory. Returns the new tab, or nil at the cap.
    @discardableResult
    mutating func add(id: UUID = UUID()) -> Tab? {
        guard canAdd else { return nil }
        let tab = Tab(id: id, title: "", directory: selected.directory)
        let index = tabs.firstIndex { $0.id == selectedID }.map { $0 + 1 } ?? tabs.count
        tabs.insert(tab, at: index)
        selectedID = tab.id
        return tab
    }

    /// Closes a tab and selects its neighbour (the one now at the same slot, else the last). Closing the only
    /// tab returns false and changes nothing — the caller hides the panel and keeps the session instead.
    @discardableResult
    mutating func close(_ id: UUID) -> Bool {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
        tabs.remove(at: index)
        if selectedID == id { selectedID = tabs[min(index, tabs.count - 1)].id }
        return true
    }

    mutating func select(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    /// ⌃Tab-style cycling; wraps. `step` is +1 / -1.
    mutating func cycle(_ step: Int) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == selectedID }) else { return }
        let next = ((index + step) % tabs.count + tabs.count) % tabs.count
        selectedID = tabs[next].id
    }

    mutating func setTitle(_ title: String, for id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func setDirectory(_ directory: String?, for id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].directory = directory
    }
}
