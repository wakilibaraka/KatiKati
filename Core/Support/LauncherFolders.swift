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
}
