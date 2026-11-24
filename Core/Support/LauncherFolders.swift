import Foundation

/// Phase 13i: launcher folders. A folder lives in the All Apps grid as one cell (a pseudo `LauncherApp` whose bundle id is
/// the folder id), so paging, sorting and drag-reorder treat it like any app.
struct LauncherFolder: Equatable, Codable, Sendable, Identifiable {
    var id: String
    var name: String
    var appIDs: [String]
}

enum LauncherFolders {
    static let idPrefix = "katikati.folder."

    static func isFolderID(_ id: String) -> Bool { id.hasPrefix(idPrefix) }
    static func newID() -> String { idPrefix + UUID().uuidString }

    /// The grid cell for a folder.
    static func cell(_ folder: LauncherFolder) -> LauncherApp {
        LauncherApp(bundleID: folder.id, name: folder.name, path: "", installedAt: .distantPast, category: "")
    }

    /// New folder holding `appIDs` (each is first taken out of any folder it was in).
    static func create(_ folders: [LauncherFolder], id: String, name: String, appIDs: [String]) -> [LauncherFolder] {
        var out = stripping(folders, appIDs: Set(appIDs))
        out.append(LauncherFolder(id: id, name: name, appIDs: appIDs))
        return out
    }

    /// Moves `appID` into folder `folderID` (out of any other folder). Unknown folder = unchanged.
    static func add(_ folders: [LauncherFolder], appID: String, to folderID: String) -> [LauncherFolder] {
        guard folders.contains(where: { $0.id == folderID }) else { return folders }
        var out = stripping(folders, appIDs: [appID], keeping: folderID)
        if let i = out.firstIndex(where: { $0.id == folderID }), !out[i].appIDs.contains(appID) { out[i].appIDs.append(appID) }
        return out
    }

    /// Takes `appID` out of its folder; a folder left empty disappears.
    static func remove(_ folders: [LauncherFolder], appID: String) -> [LauncherFolder] {
        stripping(folders, appIDs: [appID])
    }

    static func rename(_ folders: [LauncherFolder], id: String, to name: String) -> [LauncherFolder] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return folders }
        return folders.map { $0.id == id ? LauncherFolder(id: $0.id, name: trimmed, appIDs: $0.appIDs) : $0 }
    }

    /// Deleting a folder returns its apps to the grid.
    static func delete(_ folders: [LauncherFolder], id: String) -> [LauncherFolder] {
        folders.filter { $0.id != id }
    }

    /// Apps that are not inside a folder.
    static func loose(_ apps: [LauncherApp], folders: [LauncherFolder]) -> [LauncherApp] {
        let inside = Set(folders.flatMap(\.appIDs))
        return apps.filter { !inside.contains($0.bundleID) }
    }

    /// Folder contents that exist in `apps` (an uninstalled app silently drops out).
    static func members(of folder: LauncherFolder, in apps: [LauncherApp]) -> [LauncherApp] {
        let byID = Dictionary(apps.map { ($0.bundleID, $0) }, uniquingKeysWith: { a, _ in a })
        return folder.appIDs.compactMap { byID[$0] }
    }

    /// `order` after a folder takes `target`'s place (so a new folder appears where the app it swallowed was).
    static func order(_ order: [String], replacing target: String, with folderID: String) -> [String] {
        guard let i = order.firstIndex(of: target) else { return order }
        var out = order.filter { $0 != folderID }
        let at = out.firstIndex(of: target) ?? min(i, out.count)
        out[at] = folderID
        return out
    }

    private static func stripping(_ folders: [LauncherFolder], appIDs: Set<String>, keeping keep: String? = nil) -> [LauncherFolder] {
        folders.compactMap { f in
            guard f.id != keep else { return f }
            var f = f
            f.appIDs.removeAll { appIDs.contains($0) }
            return f.appIDs.isEmpty ? nil : f
        }
    }
}

/// Phase 13i: arrow-key focus over the launcher grid. Pure: the view hands in the ids of each page as rows of sections.
enum LauncherFocus {
    struct Position: Equatable { var page: Int; var id: String }

    /// `pages[p]` = the sections on page p, each an ordered list of ids laid out `columns` per row.
    /// `from == nil` focuses the first cell of `currentPage`. Left/right step through cells (crossing rows and pages);
    /// up/down step by a row (keeping the column, clamped), staying put at the first/last row.
    static func move(pages: [[[String]]], columns: Int, from: String?, currentPage: Int, dx: Int, dy: Int) -> Position? {
        let cols = max(1, columns)
        // rows[p] = [[id]]
        let rows: [[[String]]] = pages.map { sections in
            sections.flatMap { ids in stride(from: 0, to: ids.count, by: cols).map { Array(ids[$0..<min($0 + cols, ids.count)]) } }
        }
        guard rows.contains(where: { !$0.isEmpty }) else { return nil }
        func firstOfPage(_ p: Int) -> Position? {
            guard rows.indices.contains(p) else { return nil }
            return rows[p].first?.first.map { Position(page: p, id: $0) }
        }
        guard let from else {
            return firstOfPage(min(max(currentPage, 0), rows.count - 1)) ?? rows.indices.lazy.compactMap(firstOfPage).first
        }
        // Locate.
        var loc: (p: Int, r: Int, c: Int)?
        outer: for (p, prs) in rows.enumerated() {
            for (r, row) in prs.enumerated() {
                if let c = row.firstIndex(of: from) { loc = (p, r, c); break outer }
            }
        }
        guard let loc else { return firstOfPage(min(max(currentPage, 0), rows.count - 1)) }
        if dy != 0 {
            let r = loc.r + dy
            guard rows[loc.p].indices.contains(r) else { return Position(page: loc.p, id: from) }
            let row = rows[loc.p][r]
            return Position(page: loc.p, id: row[min(loc.c, row.count - 1)])
        }
        // Horizontal: linear walk over every cell of every page.
        var flat: [Position] = []
        for (p, prs) in rows.enumerated() { for row in prs { for id in row { flat.append(Position(page: p, id: id)) } } }
        guard let i = flat.firstIndex(where: { $0.id == from }) else { return nil }
        return flat[min(max(i + dx, 0), flat.count - 1)]
    }

    /// Flat vertical grid/list focus navigation (reuses `move` on a single scrollable page).
    static func moveFlat(ids: [String], columns: Int, from: String?, dx: Int, dy: Int) -> String? {
        move(pages: [[ids]], columns: max(1, columns), from: from, currentPage: 0, dx: dx, dy: dy)?.id
    }

    /// Cycles the active category rail selection on Tab / Backtab.
    static func cycleCategory(
        current: LauncherSidebarCategory,
        delta: Int,
        available: [LauncherSidebarCategory] = LauncherSidebarCategory.allCases
    ) -> LauncherSidebarCategory {
        guard !available.isEmpty, let index = available.firstIndex(of: current) else {
            return available.first ?? current
        }
        let next = (index + delta % available.count + available.count) % available.count
        return available[next]
    }
}

// MARK: - Dock App Groups (DockFolders, Slice DO-5)

/// Mini-grid density rendered on a Dock App Group tile.
enum DockAppGroupIconGrid: String, Codable, CaseIterable, Sendable, Identifiable {
    case grid2x2
    case grid3x3

    var id: String { rawValue }
    var columns: Int { self == .grid2x2 ? 2 : 3 }
    var previewLimit: Int { columns * columns }
}

/// An iOS/iPadOS-style folder pinned directly on the Dock strip holding grouped app bundle IDs.
struct DockAppGroup: Equatable, Codable, Sendable, Identifiable {
    var id: String
    var name: String
    var appIDs: [String]
    var iconGrid: DockAppGroupIconGrid
    var isPinnedToDock: Bool
    var syncedLauncherFolderID: String?

    init(
        id: String,
        name: String,
        appIDs: [String],
        iconGrid: DockAppGroupIconGrid = .grid2x2,
        isPinnedToDock: Bool = true,
        syncedLauncherFolderID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.appIDs = appIDs
        self.iconGrid = iconGrid
        self.isPinnedToDock = isPinnedToDock
        self.syncedLauncherFolderID = syncedLauncherFolderID
    }
}

/// Pure CRUD, ordering, category auto-grouping, and two-way Launcher folder sync for `DockAppGroup`.
enum DockAppGroups {
    static let defaultsKey = "com.katikati.dock.appGroups.v1"
    static let enabledKey = "com.katikati.dock.appGroups.enabled"
    static let syncLauncherKey = "com.katikati.dock.appGroups.syncLauncher"
    static let viewModeKey = "com.katikati.dock.appGroups.viewMode"
    static let idPrefix = "katikati.dockgroup."

    static func newID() -> String { idPrefix + UUID().uuidString }

    private static func deduplicated(_ appIDs: [String]) -> [String] {
        var seen = Set<String>()
        return appIDs.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func create(
        _ groups: [DockAppGroup],
        id: String = newID(),
        name: String,
        appIDs: [String],
        iconGrid: DockAppGroupIconGrid = .grid2x2
    ) -> [DockAppGroup] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "App Group" : trimmed
        return groups + [DockAppGroup(id: id, name: title, appIDs: deduplicated(appIDs), iconGrid: iconGrid)]
    }

    static func add(_ groups: [DockAppGroup], appID: String, to groupID: String) -> [DockAppGroup] {
        guard !appID.isEmpty else { return groups }
        return groups.map { group in
            guard group.id == groupID, !group.appIDs.contains(appID) else { return group }
            var copy = group
            copy.appIDs.append(appID)
            return copy
        }
    }

    static func remove(
        _ groups: [DockAppGroup],
        appID: String,
        from groupID: String,
        dropWhenEmpty: Bool = false
    ) -> [DockAppGroup] {
        groups.compactMap { group in
            guard group.id == groupID else { return group }
            var copy = group
            copy.appIDs.removeAll { $0 == appID }
            if dropWhenEmpty && copy.appIDs.isEmpty { return nil }
            return copy
        }
    }

    static func rename(_ groups: [DockAppGroup], id: String, to name: String) -> [DockAppGroup] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return groups }
        return groups.map { group in
            guard group.id == id else { return group }
            var copy = group
            copy.name = trimmed
            return copy
        }
    }

    static func setIconGrid(_ groups: [DockAppGroup], id: String, to grid: DockAppGroupIconGrid) -> [DockAppGroup] {
        groups.map { group in
            guard group.id == id else { return group }
            var copy = group
            copy.iconGrid = grid
            return copy
        }
    }

    static func delete(_ groups: [DockAppGroup], id: String) -> [DockAppGroup] {
        groups.filter { $0.id != id }
    }

    static func reorder(_ groups: [DockAppGroup], draggedID: String, relativeTo targetID: String, after: Bool) -> [DockAppGroup] {
        guard draggedID != targetID,
              let fromIndex = groups.firstIndex(where: { $0.id == draggedID }),
              groups.contains(where: { $0.id == targetID }) else {
            return groups
        }
        var copy = groups
        let moved = copy.remove(at: fromIndex)
        guard let targetIndex = copy.firstIndex(where: { $0.id == targetID }) else { return groups }
        copy.insert(moved, at: after ? targetIndex + 1 : targetIndex)
        return copy
    }

    static func categoryDisplayName(for rawCategory: String) -> String {
        var cleaned = rawCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("public.app-category.") {
            cleaned.removeFirst("public.app-category.".count)
        }
        let words = cleaned
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
        return words.joined(separator: " ")
    }

    static func autoGroupedByCategory(apps: [LauncherApp], minGroupSize: Int = 2) -> [DockAppGroup] {
        let grouped = Dictionary(grouping: apps) { categoryDisplayName(for: $0.category) }
        let threshold = max(1, minGroupSize)
        return grouped.keys
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .compactMap { category -> DockAppGroup? in
                let members = grouped[category] ?? []
                let sortedIDs = deduplicated(
                    members
                        .sorted {
                            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
                            return order == .orderedSame ? $0.bundleID < $1.bundleID : order == .orderedAscending
                        }
                        .map(\.bundleID)
                )
                guard sortedIDs.count >= threshold else { return nil }
                let slug = category.lowercased().replacingOccurrences(of: " ", with: "-")
                return DockAppGroup(id: "\(idPrefix)cat.\(slug)", name: category, appIDs: sortedIDs)
            }
    }

    static func importingFromLauncher(_ launcherFolders: [LauncherFolder], into existing: [DockAppGroup]) -> [DockAppGroup] {
        let folderByID = Dictionary(launcherFolders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var syncedIDs = Set<String>()
        var result: [DockAppGroup] = existing.compactMap { group in
            let matchKey = group.syncedLauncherFolderID ?? (folderByID[group.id] != nil ? group.id : nil)
            guard let key = matchKey else { return group }
            guard let folder = folderByID[key] else {
                return group.syncedLauncherFolderID != nil ? nil : group
            }
            syncedIDs.insert(folder.id)
            var updated = group
            updated.name = folder.name
            updated.appIDs = deduplicated(folder.appIDs)
            updated.syncedLauncherFolderID = folder.id
            return updated
        }
        for folder in launcherFolders where !syncedIDs.contains(folder.id) && !folder.appIDs.isEmpty {
            result.append(
                DockAppGroup(
                    id: "\(idPrefix)\(folder.id)",
                    name: folder.name,
                    appIDs: deduplicated(folder.appIDs),
                    syncedLauncherFolderID: folder.id
                )
            )
        }
        return result
    }

    static func exportingToLauncher(_ groups: [DockAppGroup], existing: [LauncherFolder]) -> [LauncherFolder] {
        var result = existing
        for group in groups where !group.appIDs.isEmpty {
            let folderID = group.syncedLauncherFolderID ?? group.id
            let mirrored = LauncherFolder(id: folderID, name: group.name, appIDs: deduplicated(group.appIDs))
            if let index = result.firstIndex(where: { $0.id == folderID }) {
                result[index] = mirrored
            } else {
                result.append(mirrored)
            }
        }
        return result
    }

    static func visibleDockGroups(_ groups: [DockAppGroup], enabled: Bool) -> [DockAppGroup] {
        enabled ? groups.filter(\.isPinnedToDock) : []
    }
}
