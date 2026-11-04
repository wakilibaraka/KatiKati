import Foundation

/// One launchable app as the launcher sees it (Phase 7B-L1). Pure value; the platform indexer fills it in.
struct LauncherApp: Equatable, Hashable, Sendable {
    var bundleID: String
    var name: String
    var path: String
    var installedAt: Date
    /// `LSApplicationCategoryType` from the app's Info.plist ("" = none). Used by Sort by Category.
    var category: String = ""
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
    /// 13f: dock-kept + launcher-pinned apps as their own first block (empty unless `page(separatePinned:)`).
    var pinned: [LauncherApp] = []
    /// 13g: when non-empty (Group by Category) these blocks replace `all`.
    var groups: [LauncherAppGroup] = []
}

/// Which block of the launcher a section is (the view supplies the localized title).
enum LauncherSectionKind: Equatable, Hashable, Sendable { case pinned, mostUsed, recentlyInstalled, allApps, category(String) }

/// One run of apps on a launcher page. A section that does not fit on one page continues on the next without a header.
struct LauncherPageSection: Equatable, Sendable {
    var kind: LauncherSectionKind
    var apps: [LauncherApp]
    var showsHeader: Bool
}

enum LauncherPaging {
    /// Splits the launcher into slide pages: Most Used, Recently Installed, then All Apps, each in rows of `columns`,
    /// filling every page to `pageHeight` before starting the next. A header costs `headerHeight`, a row `rowHeight`.
    static func paginate(_ page: LauncherPage, columns: Int, pageHeight: Double,
                         rowHeight: Double, headerHeight: Double) -> [[LauncherPageSection]] {
        let cols = max(1, columns)
        var pages: [[LauncherPageSection]] = [[]]
        var remaining = pageHeight
        let blocks: [(LauncherSectionKind, [LauncherApp])] = [
            (.mostUsed, page.mostUsed), (.recentlyInstalled, page.recentlyInstalled), (.allApps, page.all),
        ]
        for (kind, apps) in blocks where !apps.isEmpty {
            var rest = apps[...]
            var first = true
            while !rest.isEmpty {
                let header = first ? headerHeight : 0
                if remaining < header + rowHeight - 1e-9, !(pages[pages.count - 1].isEmpty) {
                    pages.append([]); remaining = pageHeight
                }
                let rowsFit = max(1, Int((remaining - header + 1e-9) / rowHeight))
                let take = min(rest.count, rowsFit * cols)
                pages[pages.count - 1].append(LauncherPageSection(kind: kind, apps: Array(rest.prefix(take)), showsHeader: first))
                remaining -= header + Double((take + cols - 1) / cols) * rowHeight
                rest = rest.dropFirst(take)
                first = false
                if !rest.isEmpty { pages.append([]); remaining = pageHeight }
            }
        }
        return pages.filter { !$0.isEmpty }
    }

    /// 13f: fixed-capacity pages. Every page holds `rowsPerPage` rows of `columns`; section titles cost no height (the view
    /// draws divider lines in a reserved gap), so page 1 has the same grid as every other page. A block that does not fit
    /// continues on the next page.
    static func paginateRows(_ page: LauncherPage, columns: Int, rowsPerPage: Int) -> [[LauncherPageSection]] {
        let cols = max(1, columns), rows = max(1, rowsPerPage)
        var blocks: [(LauncherSectionKind, [LauncherApp])] = [
            (.pinned, page.pinned), (.mostUsed, page.mostUsed), (.recentlyInstalled, page.recentlyInstalled),
        ]
        if page.groups.isEmpty {
            blocks.append((.allApps, page.all))
        } else {
            blocks += page.groups.map { (.category($0.title), $0.apps) }
        }
        var pages: [[LauncherPageSection]] = [[]]
        var rowsLeft = rows
        for (kind, apps) in blocks where !apps.isEmpty {
            var rest = apps[...]
            var first = true
            while !rest.isEmpty {
                if rowsLeft == 0 { pages.append([]); rowsLeft = rows }
                let take = min(rest.count, rowsLeft * cols)
                pages[pages.count - 1].append(LauncherPageSection(kind: kind, apps: Array(rest.prefix(take)), showsHeader: first))
                rowsLeft -= (take + cols - 1) / cols
                rest = rest.dropFirst(take)
                first = false
            }
        }
        return pages.filter { !$0.isEmpty }
    }
}

/// The user's own arrangement of All Apps: apps named in `order` come first, in that order; every other app follows in its
/// existing (name) order, so a newly installed app lands at the end instead of scrambling the layout.
enum LauncherOrdering {
    static func ordered(_ apps: [LauncherApp], by order: [String]) -> [LauncherApp] {
        guard !order.isEmpty else { return apps }
        var rank: [String: Int] = [:]
        for (i, id) in order.enumerated() where rank[id] == nil { rank[id] = i }
        let known = apps.filter { rank[$0.bundleID] != nil }.sorted { rank[$0.bundleID]! < rank[$1.bundleID]! }
        let rest = apps.filter { rank[$0.bundleID] == nil }
        return known + rest
    }

    /// The full order after dragging `moving` in front of `target` (nil target = to the end). `ids` is the order on screen now.
    static func move(_ ids: [String], moving: String, before target: String?) -> [String] {
        guard ids.contains(moving), moving != target else { return ids }
        var out = ids.filter { $0 != moving }
        if let target, let i = out.firstIndex(of: target) { out.insert(moving, at: i) } else { out.append(moving) }
        return out
    }

    static func toggleHidden(_ hidden: [String], _ bundleID: String) -> [String] {
        hidden.contains(bundleID) ? hidden.filter { $0 != bundleID } : hidden + [bundleID]
    }
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
        recentDays: Int = 30,
        hidden: Set<String> = [],
        order: [String] = [],
        keptIDs: [String] = [],
        separatePinned: Bool = false,
        sort: LauncherSortMode = .custom,
        groupByCategory: Bool = false,
        folders: [LauncherFolder] = []
    ) -> LauncherPage {
        let visible = apps.filter { !hidden.contains($0.bundleID) }
        // Apps inside a folder leave the grid (they stay pinnable); a folder is one cell in All Apps.
        let apps = LauncherFolders.loose(visible, folders: folders)
        let row = max(1, columns)
        let byID = Dictionary(visible.map { ($0.bundleID, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        var pinnedBlock: [LauncherApp] = []
        if separatePinned {
            // Dock-kept apps first (their dock order), then the launcher's own pins; each app once.
            for id in keptIDs + pinned where !seen.contains(id) {
                if let app = byID[id] { pinnedBlock.append(app); seen.insert(id) }
            }
        }
        let legacyPins = separatePinned ? [] : pinned
        var top: [LauncherApp] = []
        func take(_ app: LauncherApp) {
            guard top.count < row, !seen.contains(app.bundleID) else { return }
            top.append(app); seen.insert(app.bundleID)
        }
        legacyPins.compactMap { byID[$0] }.forEach(take)
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
        let folderCells = folders.filter { !LauncherFolders.members(of: $0, in: visible).isEmpty }.map(LauncherFolders.cell)
        let sorted = LauncherSort.apply(sort, to: apps + folderCells, usage: usage, order: order)
        return LauncherPage(mostUsed: top, recentlyInstalled: Array(recent), all: sorted, pinned: pinnedBlock,
                            groups: groupByCategory ? LauncherSort.groups(sorted) : [])
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

/// Nanolight's matcher, ported from its `src/search.zig` (MIT, github.com/justrach/nanolight) so the
/// command bar and the launcher rank names the same way its panel does. Case- and diacritic-insensitive;
/// tiers, best first: the whole name, its start, a word's start, the words' initials ("vsc" for Visual
/// Studio Code), anywhere inside it, the letters in order (worse the more they spread), then typos —
/// a name or word that begins like the query but for a letter or two swapped, wrong, missing or extra
/// ("chorme" for Chrome). The weights are nanolight's own, so the gaps between tiers stay the same.
enum LauncherMatch {
    /// Nanolight's tiers, in its own points. `nil` = the query's letters are not all there.
    static func score(query: String, name: String) -> Int? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !name.isEmpty else { return nil }
        let q = trimmed.map(fold)
        let n = name.map(fold)
        let slack = min(max(n.count - q.count, 0), 60)
        if q.count == n.count, matches(n, q, at: 0) { return 1000 }
        if matches(n, q, at: 0) { return 900 - slack }
        if let i = wordPrefixIndex(q, n) { return 800 - slack - min(i, 60) }
        if let initials = initials(q, n) { return initials }
        if let i = substringIndex(q, n) { return 600 - slack - min(i, 60) }
        if let inOrder = subsequence(q, n) { return inOrder }
        return typo(q, n)
    }

    /// A folded character: case and diacritics gone ("Café" folds to "cafe"). A fold that expands
    /// ("ß" → "ss") keeps its first character, so offsets stay one-per-name-character.
    private static func fold(_ c: Character) -> Character {
        let folded = String(c).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return folded.first ?? c
    }

    /// Whether `i` starts a word: the name's start, after a space or punctuation, or a capital after a
    /// lowercase letter (FaceTime).
    private static func isWordStart(_ n: [Character], _ i: Int) -> Bool {
        if i == 0 { return true }
        let prev = n[i - 1], ch = n[i]
        if prev == " " || prev == "-" || prev == "_" || prev == "." || prev == "/" || prev == "(" {
            return ch != " "
        }
        return prev.isLowercase && ch.isUppercase
    }

    private static func matches(_ n: [Character], _ q: [Character], at start: Int) -> Bool {
        guard !q.isEmpty, start >= 0, start + q.count <= n.count else { return false }
        for k in 0..<q.count where n[start + k] != q[k] { return false }
        return true
    }

    private static func wordPrefixIndex(_ q: [Character], _ n: [Character]) -> Int? {
        for i in n.indices where isWordStart(n, i) && matches(n, q, at: i) { return i }
        return nil
    }

    private static func substringIndex(_ q: [Character], _ n: [Character]) -> Int? {
        guard q.count <= n.count else { return nil }
        for i in 0...(n.count - q.count) where matches(n, q, at: i) { return i }
        return nil
    }

    /// The query as the words' initials, in order, every one of them.
    private static func initials(_ q: [Character], _ n: [Character]) -> Int? {
        guard q.count >= 2 else { return nil }
        var qi = 0
        for i in n.indices {
            if qi == q.count { break }
            guard isWordStart(n, i) else { continue }
            if n[i] == q[qi] { qi += 1 }
        }
        return qi == q.count ? 750 - min(n.count, 60) : nil
    }

    /// The letters in order anywhere; each on a word's start or right after the last scores more, gaps
    /// score less.
    private static func subsequence(_ q: [Character], _ n: [Character]) -> Int? {
        var score = 300
        var last: Int?
        var from = 0
        for qc in q {
            if qc == " " { continue }
            var found: Int?
            while from < n.count {
                if n[from] == qc { found = from; break }
                from += 1
            }
            guard let at = found else { return nil }
            if isWordStart(n, at) { score += 12 }
            if let previous = last {
                score += at == previous + 1 ? 8 : -min(at - previous, 20)
            } else {
                score -= min(at, 20)
            }
            last = at
            from = at + 1
        }
        return score - min(n.count, 60) / 4
    }

    /// The typos a query of this length may have: none under 4 letters (too many names are a letter
    /// from "map"), one, then two from 7.
    private static func allowedEdits(_ length: Int) -> Int { length < 4 ? 0 : (length < 7 ? 1 : 2) }

    /// The query as a misspelt start of the name, or of one of its words: the fewest edits (a character
    /// put in, left out, changed, or two neighbours swapped) that make the query a prefix of it.
    private static func typo(_ q: [Character], _ n: [Character]) -> Int? {
        let most = allowedEdits(q.count)
        guard most > 0, q.count <= 32 else { return nil }
        var best: (errs: Int, start: Int)?
        for start in n.indices where isWordStart(n, start) {
            let word = Array(n[start..<min(n.count, start + 64)])
            let distance = prefixDistance(q, word)
            if distance.errs <= most, best == nil || distance.errs < best!.errs {
                best = (distance.errs, start)
            }
        }
        guard let best else { return nil }
        return 260 - 70 * best.errs - min(n.count, 60) / 4 - min(best.start, 20)
    }

    /// Optimal string alignment (insert, delete, change, swap neighbours) from `q` to every prefix of
    /// `word`: the fewest edits to any of them, and how long that prefix is.
    private static func prefixDistance(_ q: [Character], _ word: [Character]) -> (errs: Int, end: Int) {
        if word.isEmpty { return (q.count, 0) }
        var previousPrevious = Array(0...word.count)
        var previous = previousPrevious
        for i in 1...q.count {
            var current = [i] + Array(repeating: 0, count: word.count)
            for j in 1...word.count {
                let same = q[i - 1] == word[j - 1]
                var cost = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (same ? 0 : 1))
                if i > 1, j > 1, q[i - 1] == word[j - 2], q[i - 2] == word[j - 1] {
                    cost = min(cost, previousPrevious[j - 2] + 1)
                }
                current[j] = cost
            }
            previousPrevious = previous
            previous = current
        }
        var errs = Int.max, end = 0
        for j in 0...word.count where previous[j] < errs {
            errs = previous[j]
            end = j
        }
        return (errs, end)
    }
}

enum LauncherSearch {
    /// Score for `query` against `name` (higher is better, nil = no match), by nanolight's matcher.
    static func score(query: String, name: String) -> Int? {
        LauncherMatch.score(query: query, name: name)
    }

    /// Matching apps, best first. A launch count lifts a match by up to 250 (nanolight's own boost), which
    /// cannot carry a substring match over an exact name; ties by usage count then name.
    static func search(_ query: String, in apps: [LauncherApp], usage: [String: LauncherUsage], limit: Int = 50) -> [LauncherApp] {
        let scored: [(LauncherApp, Int)] = apps.compactMap { app in
            let nameScore = LauncherMatch.score(query: query, name: app.name)
            let bundleScore = LauncherMatch.score(query: query, name: app.bundleID).map { min($0, 250) }
            let filename = URL(fileURLWithPath: app.path).deletingPathExtension().lastPathComponent
            let filenameScore = LauncherMatch.score(query: query, name: filename).map { min($0, 500) }
            guard let base = [nameScore, filenameScore, bundleScore].compactMap({ $0 }).max() else { return nil }
            return (app, base + min((usage[app.bundleID]?.launches ?? 0) * 25, 250))
        }
        return scored.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            let ua = usage[a.0.bundleID]?.launches ?? 0, ub = usage[b.0.bundleID]?.launches ?? 0
            if ua != ub { return ua > ub }
            return LauncherAppIndex.nameOrder(a.0, b.0)
        }.prefix(max(0, limit)).map(\.0)
    }
}
