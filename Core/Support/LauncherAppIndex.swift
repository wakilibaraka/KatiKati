import Foundation

/// One launchable app as the launcher sees it (Phase 7B-L1). Pure value; the platform indexer fills it in.
struct LauncherApp: Equatable, Hashable, Sendable {
    var bundleID: String
    var name: String
    var path: String
    var installedAt: Date
}

/// Launch history for one app. Counts only start when the launcher ships (macOS keeps no history).
struct LauncherUsage: Equatable, Codable, Sendable {
    var launches: Int
    var lastLaunched: Date
}

/// The launcher's sections, in display order.
struct LauncherSections: Equatable, Sendable {
    var pinned: [LauncherApp]
    var mostUsed: [LauncherApp]
    var recentlyInstalled: [LauncherApp]
}

/// The grid page (Phase 7B launcher redo): one Most Used row, one Recently Installed row, then every app.
struct LauncherPage: Equatable, Sendable {
    var mostUsed: [LauncherApp]
    var recentlyInstalled: [LauncherApp]
    var all: [LauncherApp]
}

enum LauncherPresets {
    /// Shown in Most Used until real usage takes the slots (only the installed ones appear).
    static let bundleIDs = [
        "com.apple.systempreferences", "com.apple.Safari", "com.apple.Terminal", "com.apple.MobileSMS",
        "com.apple.finder", "com.apple.mail", "com.apple.iCal", "com.apple.Notes",
        "com.apple.Music", "com.apple.Photos", "com.apple.AppStore", "com.apple.calculator",
    ]
}

enum LauncherGrid {
    /// How many icon cells fit one row: the grid's cells are 104 pt minimum with 12 pt gaps.
    static func columns(forWidth width: Double, minCell: Double = 104, gap: Double = 12) -> Int {
        max(1, Int((width + gap) / (minCell + gap)))
    }
}

enum LauncherAppIndex {
    /// One entry per bundle id; when copies exist the shortest path wins (`/Applications/X.app` beats a nested or
    /// `~/Downloads` copy), then the newer install. Result sorted by localized name, case-insensitive.
    static func merged(_ apps: [LauncherApp], excluding excluded: Set<String> = []) -> [LauncherApp] {
        var best: [String: LauncherApp] = [:]
        for app in apps where !app.bundleID.isEmpty && !excluded.contains(app.bundleID) {
            guard let current = best[app.bundleID] else { best[app.bundleID] = app; continue }
            if app.path.count < current.path.count
                || (app.path.count == current.path.count && app.installedAt > current.installedAt) {
                best[app.bundleID] = app
            }
        }
        return best.values.sorted(by: nameOrder)
    }

    static func nameOrder(_ a: LauncherApp, _ b: LauncherApp) -> Bool {
        let c = a.name.localizedCaseInsensitiveCompare(b.name)
        return c == .orderedSame ? a.bundleID < b.bundleID : c == .orderedAscending
    }

    /// Pinned (in the user's order) → most used (launch count, then recency; apps never launched are skipped) →
    /// recently installed (newest first, within `recentDays`). An app appears in the first section that claims it.
    static func sections(
        apps: [LauncherApp],
        usage: [String: LauncherUsage],
        pinned: [String],
        now: Date,
        mostUsedLimit: Int = 8,
        recentLimit: Int = 8,
        recentDays: Int = 30
    ) -> LauncherSections {
        let byID = Dictionary(apps.map { ($0.bundleID, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        var pins: [LauncherApp] = []
        for id in pinned where !seen.contains(id) {
            if let app = byID[id] { pins.append(app); seen.insert(id) }
        }
        let used = apps
            .filter { !seen.contains($0.bundleID) && (usage[$0.bundleID]?.launches ?? 0) > 0 }
            .sorted { a, b in
                let ua = usage[a.bundleID]!, ub = usage[b.bundleID]!
                if ua.launches != ub.launches { return ua.launches > ub.launches }
                if ua.lastLaunched != ub.lastLaunched { return ua.lastLaunched > ub.lastLaunched }
                return nameOrder(a, b)
            }
            .prefix(max(0, mostUsedLimit))
        used.forEach { seen.insert($0.bundleID) }
        let cutoff = now.addingTimeInterval(-Double(recentDays) * 86_400)
        let recent = apps
            .filter { !seen.contains($0.bundleID) && $0.installedAt >= cutoff && $0.installedAt <= now }
            .sorted { $0.installedAt != $1.installedAt ? $0.installedAt > $1.installedAt : nameOrder($0, $1) }
            .prefix(max(0, recentLimit))
        return LauncherSections(pinned: pins, mostUsed: Array(used), recentlyInstalled: Array(recent))
    }

    /// Most Used fills exactly one row (`columns`): pins first, then by launch count, then presets for any
    /// slot real usage has not taken. Recently Installed is one row of apps not already above. All lists everything.
    static func page(
        apps: [LauncherApp],
        usage: [String: LauncherUsage],
        pinned: [String],
        presets: [String] = LauncherPresets.bundleIDs,
        columns: Int,
        now: Date,
        recentDays: Int = 30
    ) -> LauncherPage {
        let row = max(1, columns)
        let byID = Dictionary(apps.map { ($0.bundleID, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        var top: [LauncherApp] = []
        func take(_ app: LauncherApp) {
            guard top.count < row, !seen.contains(app.bundleID) else { return }
            top.append(app); seen.insert(app.bundleID)
        }
        pinned.compactMap { byID[$0] }.forEach(take)
        apps.filter { (usage[$0.bundleID]?.launches ?? 0) > 0 }
            .sorted { a, b in
                let ua = usage[a.bundleID]!, ub = usage[b.bundleID]!
                if ua.launches != ub.launches { return ua.launches > ub.launches }
                if ua.lastLaunched != ub.lastLaunched { return ua.lastLaunched > ub.lastLaunched }
                return nameOrder(a, b)
            }
            .forEach(take)
        presets.compactMap { byID[$0] }.forEach(take)
        let cutoff = now.addingTimeInterval(-Double(recentDays) * 86_400)
        let recent = apps
            .filter { !seen.contains($0.bundleID) && $0.installedAt >= cutoff && $0.installedAt <= now }
            .sorted { $0.installedAt != $1.installedAt ? $0.installedAt > $1.installedAt : nameOrder($0, $1) }
            .prefix(row)
        return LauncherPage(mostUsed: top, recentlyInstalled: Array(recent), all: apps)
    }

    /// Records a launch.
    static func recordLaunch(_ usage: inout [String: LauncherUsage], bundleID: String, at date: Date) {
        var u = usage[bundleID] ?? LauncherUsage(launches: 0, lastLaunched: date)
        u.launches += 1
        u.lastLaunched = date
        usage[bundleID] = u
    }

    /// Toggles a pin; new pins go to the end.
    static func togglePin(_ pinned: [String], _ bundleID: String) -> [String] {
        pinned.contains(bundleID) ? pinned.filter { $0 != bundleID } : pinned + [bundleID]
    }
}

enum LauncherSearch {
    /// Score for `query` against `name` (higher is better, nil = no match). Case/diacritic-insensitive:
    /// exact > prefix > word prefix > substring > in-order letters ("ps" → Photoshop, "vsc" → Visual Studio Code).
    static func score(query: String, name: String) -> Int? {
        let q = fold(query)
        guard !q.isEmpty else { return nil }
        let n = fold(name)
        if n == q { return 1000 }
        if n.hasPrefix(q) { return 800 - min(n.count - q.count, 100) }
        let words = n.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if let i = words.firstIndex(where: { $0.hasPrefix(q) }) { return 600 - min(i * 10, 90) }
        if n.contains(q) { return 400 }
        let initials = String(words.compactMap(\.first))
        if initials.hasPrefix(q) { return 300 }
        if isSubsequence(q, of: n) { return 100 }
        return nil
    }

    /// Matching apps, best first; ties by usage count then name.
    static func search(_ query: String, in apps: [LauncherApp], usage: [String: LauncherUsage], limit: Int = 50) -> [LauncherApp] {
        let scored: [(LauncherApp, Int)] = apps.compactMap { app in
            score(query: query, name: app.name).map { (app, $0) }
        }
        return scored.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            let ua = usage[a.0.bundleID]?.launches ?? 0, ub = usage[b.0.bundleID]?.launches ?? 0
            if ua != ub { return ua > ub }
            return LauncherAppIndex.nameOrder(a.0, b.0)
        }.prefix(max(0, limit)).map(\.0)
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func isSubsequence(_ q: String, of n: String) -> Bool {
        var from = n.startIndex
        for c in q {
            guard let hit = n[from...].firstIndex(of: c) else { return false }
            from = n.index(after: hit)
        }
        return true
    }
}
