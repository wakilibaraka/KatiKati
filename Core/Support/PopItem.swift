import Foundation

// DockPops-style drawer — the pure model and policy. `PopStore` (app layer) owns persistence; every
// decision (capacity, dedupe, ordering, migration from the app-only drawer) lives here and is unit-tested.
// Dual-compiled.

/// One thing held in a pop: an app (by bundle id) or a file / folder (by path).
struct PopItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case app
        case file
        case folder
    }

    var kind: Kind
    /// Bundle id for `.app`, absolute path for `.file` / `.folder`.
    var reference: String

    var id: String { "\(kind.rawValue):\(reference)" }

    static func app(_ bundleID: String) -> PopItem { PopItem(kind: .app, reference: bundleID) }
    static func file(_ path: String) -> PopItem { PopItem(kind: .file, reference: path) }
    static func folder(_ path: String) -> PopItem { PopItem(kind: .folder, reference: path) }
}

enum PopPolicy {
    /// DockPops' limit: a pop holds at most 25 items.
    static let capacity = 25

    /// Outcome of an add: the new list, and how many requested items did not fit.
    struct AddResult: Equatable {
        var items: [PopItem]
        var rejectedForCapacity: Int
    }

    /// Appends new items in order, skipping empties and duplicates (an item already in the pop stays
    /// where it is). Items past `capacity` are dropped and counted, never silently evict older ones.
    static func adding(_ new: [PopItem], to items: [PopItem], capacity: Int = capacity) -> AddResult {
        var result = items
        var seen = Set(items.map(\.id))
        var rejected = 0
        for item in new where !item.reference.isEmpty && seen.insert(item.id).inserted {
            if result.count >= capacity { rejected += 1; continue }
            result.append(item)
        }
        return AddResult(items: result, rejectedForCapacity: rejected)
    }

    static func removing(_ id: String, from items: [PopItem]) -> [PopItem] {
        items.filter { $0.id != id }
    }

    /// Moves `draggedID` before or after `targetID`. Unknown ids or a self-drop leave the list as is.
    static func reordering(_ items: [PopItem], draggedID: String, relativeTo targetID: String, after: Bool) -> [PopItem] {
        guard draggedID != targetID, let from = items.firstIndex(where: { $0.id == draggedID }) else { return items }
        var next = items
        let moved = next.remove(at: from)
        guard let target = next.firstIndex(where: { $0.id == targetID }) else { return items }
        next.insert(moved, at: after ? target + 1 : target)
        return next
    }

    /// First launch after the drawer became a pop: the old app-only drawer (`drawerBundleIDs`, already in
    /// `drawerDisplayOrder` order when one is stored) becomes the pop's apps. Nothing is dropped for
    /// capacity here: a user who stashed more than 25 apps keeps all of them and simply cannot add more.
    static func migrating(legacyBundleIDs: [String], legacyOrder: [String]) -> [PopItem] {
        let members = Set(legacyBundleIDs)
        var ordered = legacyOrder.filter { members.contains($0) }
        let known = Set(ordered)
        ordered += legacyBundleIDs.filter { !known.contains($0) }
        var seen = Set<String>()
        return ordered.filter { !$0.isEmpty && seen.insert($0).inserted }.map(PopItem.app)
    }

    /// Classifies a dropped URL: `.app` bundles become app items (by bundle id when it can be read),
    /// directories become folders, everything else is a file. `bundleID` is passed in so this stays pure.
    static func item(forPath path: String, isDirectory: Bool, bundleID: String?) -> PopItem? {
        guard !path.isEmpty else { return nil }
        if path.hasSuffix(".app") || path.hasSuffix(".app/") {
            if let bundleID, !bundleID.isEmpty { return .app(bundleID) }
            return .file(path)
        }
        return isDirectory ? .folder(path) : .file(path)
    }
}
