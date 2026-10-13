import Foundation

/// Phase 13f–13h: launcher sort, categories, preferences and the "hide rarely used apps" presets. Pure logic.

enum LauncherSortMode: String, CaseIterable, Codable, Sendable {
    case custom, name, mostUsed, recentlyAdded, category
    static let `default`: LauncherSortMode = .custom
}

/// A named run of apps (one Launchpad-style category block).
struct LauncherAppGroup: Equatable, Sendable {
    var title: String
    var apps: [LauncherApp]
}

enum LauncherCategory {
    static let other = "Other"

    /// `public.app-category.productivity` → "Productivity"; `…-games` / `…graphics-design` → "Graphics Design"; empty → "Other".
    static func title(forUTI uti: String) -> String {
        let tail = uti.split(separator: ".").last.map(String.init) ?? ""
        let words = tail.split(whereSeparator: { $0 == "-" || $0 == "_" })
        guard !words.isEmpty else { return other }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

enum LauncherSort {
    static func apply(_ mode: LauncherSortMode, to apps: [LauncherApp], usage: [String: LauncherUsage], order: [String]) -> [LauncherApp] {
        switch mode {
        case .custom: return LauncherOrdering.ordered(apps, by: order)
        case .name: return apps.sorted(by: LauncherAppIndex.nameOrder)
        case .mostUsed:
            return apps.sorted { a, b in
                let ua = usage[a.bundleID]?.launches ?? 0, ub = usage[b.bundleID]?.launches ?? 0
                return ua != ub ? ua > ub : LauncherAppIndex.nameOrder(a, b)
            }
        case .recentlyAdded:
            return apps.sorted { $0.installedAt != $1.installedAt ? $0.installedAt > $1.installedAt : LauncherAppIndex.nameOrder($0, $1) }
        case .category:
            return apps.sorted { a, b in
                let ca = LauncherCategory.title(forUTI: a.category), cb = LauncherCategory.title(forUTI: b.category)
                return ca != cb ? categoryOrder(ca, cb) : LauncherAppIndex.nameOrder(a, b)
            }
        }
    }

    /// Category blocks, alphabetical with "Other" last; apps inside keep the order they came in.
    static func groups(_ apps: [LauncherApp]) -> [LauncherAppGroup] {
        var buckets: [String: [LauncherApp]] = [:]
        for app in apps { buckets[LauncherCategory.title(forUTI: app.category), default: []].append(app) }
        return buckets.keys.sorted(by: categoryOrder).map { LauncherAppGroup(title: $0, apps: buckets[$0]!) }
    }

    private static func categoryOrder(_ a: String, _ b: String) -> Bool {
        if a == LauncherCategory.other { return false }
        if b == LauncherCategory.other { return true }
        return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
    }
}

/// Launcher look-and-layout preferences edited from the gear popover. One JSON blob in `com.katikati.launcher.prefs`.
struct LauncherPrefs: Equatable, Codable, Sendable {
    static let key = "com.katikati.launcher.prefs"
    static let columnRange = 5...9
    static let rowRange = 3...6
    static let iconScaleRange = 0.8...1.25

    /// 0…1; 1 = the full system blur (the look before 13g).
    var blur = 1.0
    /// 0 = fit to the screen width (up to 8), otherwise 5…9.
    var columns = 0
    /// 0 = fit to the screen height, otherwise 3…6 rows per page.
    var rows = 0
    var iconScale = 1.0
    var sort = LauncherSortMode.default
    var groupByCategory = false
    var showRunningDot = true

    func clamped() -> LauncherPrefs {
        var p = self
        p.blur = blur.isFinite ? min(max(blur, 0), 1) : 1
        p.columns = columns == 0 ? 0 : min(max(columns, Self.columnRange.lowerBound), Self.columnRange.upperBound)
        p.rows = rows == 0 ? 0 : min(max(rows, Self.rowRange.lowerBound), Self.rowRange.upperBound)
        p.iconScale = iconScale.isFinite ? min(max(iconScale, Self.iconScaleRange.lowerBound), Self.iconScaleRange.upperBound) : 1
        return p
    }

    static func load(_ defaults: UserDefaults = .standard) -> LauncherPrefs {
        guard let data = defaults.data(forKey: key), let p = try? JSONDecoder().decode(LauncherPrefs.self, from: data) else { return LauncherPrefs() }
        return p.clamped()
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(clamped()) { defaults.set(data, forKey: Self.key) }
    }
}

/// Apps most people never open from a launcher (Automator-style list). One tap hides them all; hidden apps stay searchable.
enum LauncherHidePresets {
    struct Entry: Equatable, Sendable { let bundleID: String; let name: String }

    static let entries: [Entry] = [
        Entry(bundleID: "com.apple.Chess", name: "Chess"),
        Entry(bundleID: "com.apple.podcasts", name: "Podcasts"),
        Entry(bundleID: "com.apple.Magnifier", name: "Magnifier"),
        Entry(bundleID: "com.apple.Automator", name: "Automator"),
        Entry(bundleID: "com.apple.stocks", name: "Stocks"),
        Entry(bundleID: "com.apple.VoiceMemos", name: "Voice Memos"),
        Entry(bundleID: "com.apple.PhotoBooth", name: "Photo Booth"),
        Entry(bundleID: "com.apple.grapher", name: "Grapher"),
        Entry(bundleID: "com.apple.Dictionary", name: "Dictionary"),
        Entry(bundleID: "com.apple.DigitalColorMeter", name: "Digital Color Meter"),
        Entry(bundleID: "com.apple.Console", name: "Console"),
        Entry(bundleID: "com.apple.keychainaccess", name: "Keychain Access"),
        Entry(bundleID: "com.apple.ScriptEditor2", name: "Script Editor"),
        Entry(bundleID: "com.apple.FontBook", name: "Font Book"),
        Entry(bundleID: "com.apple.Image_Capture", name: "Image Capture"),
        Entry(bundleID: "com.apple.AudioMIDISetup", name: "Audio MIDI Setup"),
        Entry(bundleID: "com.apple.BluetoothFileExchange", name: "Bluetooth File Exchange"),
        Entry(bundleID: "com.apple.news", name: "News"),
        Entry(bundleID: "com.apple.stickies", name: "Stickies"),
    ]

    static var bundleIDs: [String] { entries.map(\.bundleID) }

    /// `hidden` plus every preset (no duplicates, existing order kept).
    static func hidingAll(_ hidden: [String]) -> [String] {
        hidden + bundleIDs.filter { !hidden.contains($0) }
    }

    /// `hidden` without any preset id (apps the user hid by hand stay hidden).
    static func restoringAll(_ hidden: [String]) -> [String] {
        let preset = Set(bundleIDs)
        return hidden.filter { !preset.contains($0) }
    }
}

/// 13i: what Return does when no app matches the query — open a URL or search the web.
enum LauncherQuickAction: Equatable, Sendable {
    case open(URL)
    case webSearch(URL)

    static func resolve(_ raw: String) -> LauncherQuickAction? {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        if !q.contains(" "), let url = URL(string: q), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https", url.host != nil {
            return .open(url)
        }
        if !q.contains(" "), !q.contains("://"), let dot = q.firstIndex(of: "."),
           q.index(after: dot) < q.endIndex, !q.hasPrefix("."),
           let host = q.split(separator: "/").first, let tld = host.split(separator: ".").last, tld.count >= 2,
           tld.allSatisfy(\.isLetter), let url = URL(string: "https://" + q) {
            return .open(url)
        }
        var comps = URLComponents(string: "https://duckduckgo.com/")!
        comps.queryItems = [URLQueryItem(name: "q", value: q)]
        return comps.url.map { .webSearch($0) }
    }
}
