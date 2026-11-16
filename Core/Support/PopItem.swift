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

    /// Mirrors the stashed apps (`DrawerStore`, the authority for app placement) into the pop: app items
    /// no longer stashed leave, newly stashed apps join at the end. Files and folders are untouched.
    /// Not capped: a stash from the strip already happened, and the pop must show it.
    static func syncingApps(_ items: [PopItem], drawerBundleIDs: [String]) -> [PopItem] {
        let stashed = Set(drawerBundleIDs)
        var result = items.filter { $0.kind != .app || stashed.contains($0.reference) }
        let present = Set(result.filter { $0.kind == .app }.map(\.reference))
        var seen = Set<String>()
        for id in drawerBundleIDs where !id.isEmpty && !present.contains(id) && seen.insert(id).inserted {
            result.append(.app(id))
        }
        return result
    }

    /// Classifies a dropped URL: application bundles become app items (by bundle id; one whose id
    /// cannot be read is kept as a plain file, never browsed as a folder), directories become folders,
    /// everything else is a file. The disk facts are passed in so this stays pure.
    static func item(forPath path: String, isDirectory: Bool, isApplication: Bool, bundleID: String?) -> PopItem? {
        guard !path.isEmpty else { return nil }
        if isApplication {
            if let bundleID, !bundleID.isEmpty { return .app(bundleID) }
            return .file(path)
        }
        return isDirectory ? .folder(path) : .file(path)
    }
}

// MARK: - Drawer Layout & Drop Target Math (Slice D-1)

/// Visual layout style supported by the Drawer popover toggle.
enum DrawerLayoutStyle: String, Codable, CaseIterable, Sendable {
    case grid
    case list

    var toggled: DrawerLayoutStyle { self == .grid ? .list : .grid }
}

/// Typed payload representing an external or custom item targeted for the Drawer.
enum DrawerItemPayload: Equatable, Hashable, Sendable {
    case application(url: URL, bundleID: String?)
    case file(url: URL)
    case folder(url: URL)
    case customShortcut(name: String, target: URL)

    /// Classifies a file system URL using pre-read disk facts so validation stays pure.
    static func classify(url: URL, isDirectory: Bool, isApplication: Bool, bundleID: String?) -> DrawerItemPayload? {
        guard url.isFileURL, !url.path.isEmpty else { return nil }
        if isApplication { return .application(url: url, bundleID: bundleID) }
        return isDirectory ? .folder(url: url) : .file(url: url)
    }

    /// Converts this payload into a persistable `PopItem` when representable.
    var popItem: PopItem? {
        switch self {
        case let .application(url, bundleID):
            return PopPolicy.item(forPath: url.path, isDirectory: false, isApplication: true, bundleID: bundleID)
        case let .file(url):
            return PopPolicy.item(forPath: url.path, isDirectory: false, isApplication: false, bundleID: nil)
        case let .folder(url):
            return PopPolicy.item(forPath: url.path, isDirectory: true, isApplication: false, bundleID: nil)
        case let .customShortcut(_, target):
            guard !target.path.isEmpty else { return nil }
            return target.hasDirectoryPath ? .folder(target.path) : .file(target.path)
        }
    }
}

/// Ordering strategies for organizing items shown in the Drawer.
enum DrawerSortOrder: String, Codable, CaseIterable, Sendable {
    case manual
    case nameAscending
    case groupedFoldersFirst
}

/// Pure drop validation, deduplication, capacity enforcement, and folder grouping for the Drawer.
enum DrawerDropTargetPolicy {
    struct ValidationResult: Equatable, Sendable {
        var accepted: [PopItem]
        var duplicatesSkipped: Int
        var rejectedForCapacity: Int
        var invalidSkipped: Int
    }

    struct GroupedItems: Equatable, Sendable {
        var folders: [PopItem]
        var apps: [PopItem]
        var files: [PopItem]
    }

    /// Validates incoming payloads against existing items, filtering duplicates and enforcing capacity.
    static func validateDrop(payloads: [DrawerItemPayload], existing: [PopItem], capacity: Int = PopPolicy.capacity) -> ValidationResult {
        var seen = Set(existing.map(\.id))
        var accepted: [PopItem] = []
        var duplicatesSkipped = 0, rejectedForCapacity = 0, invalidSkipped = 0
        var remaining = max(0, capacity - existing.count)

        for payload in payloads {
            guard let candidate = payload.popItem else { invalidSkipped += 1; continue }
            guard seen.insert(candidate.id).inserted else { duplicatesSkipped += 1; continue }
            guard remaining > 0 else { rejectedForCapacity += 1; continue }
            accepted.append(candidate)
            remaining -= 1
        }
        return ValidationResult(accepted: accepted, duplicatesSkipped: duplicatesSkipped,
                                rejectedForCapacity: rejectedForCapacity, invalidSkipped: invalidSkipped)
    }

    /// Partitions drawer items by semantic kind while preserving relative order inside each group.
    static func groupItems(_ items: [PopItem]) -> GroupedItems {
        GroupedItems(folders: items.filter { $0.kind == .folder },
                     apps: items.filter { $0.kind == .app },
                     files: items.filter { $0.kind == .file })
    }

    /// Orders drawer items using the given sort mode and display-name provider.
    static func sort(_ items: [PopItem], by order: DrawerSortOrder, displayName: (PopItem) -> String) -> [PopItem] {
        let byName: (PopItem, PopItem) -> Bool = {
            displayName($0).localizedStandardCompare(displayName($1)) == .orderedAscending
        }
        switch order {
        case .manual: return items
        case .nameAscending: return items.sorted(by: byName)
        case .groupedFoldersFirst:
            let g = groupItems(items)
            return g.folders.sorted(by: byName) + g.apps.sorted(by: byName) + g.files.sorted(by: byName)
        }
    }
}
