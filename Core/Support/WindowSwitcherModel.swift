import Foundation

/// Phase 20c — pure ordering and selection rules for the Option+Tab window switcher.
/// Windows are listed most-recently-used first; the first press selects the *previous* window (index 1),
/// as AltTab / the system app switcher do, so a quick Option+Tab flips between the last two windows.
enum WindowSwitcherModel {
    static let mruLimit = 64

    /// Moves `active` to the front of the MRU list and drops windows that no longer exist.
    static func updatedMRU(_ mru: [String], active: String?, alive: Set<String>) -> [String] {
        var next = mru.filter { alive.contains($0) && $0 != active }
        if let active, alive.contains(active) { next.insert(active, at: 0) }
        return Array(next.prefix(mruLimit))
    }

    /// Candidates ordered by MRU position; windows the MRU has not seen keep their incoming order after it.
    static func order(candidates: [String], mru: [String]) -> [String] {
        let rank = Dictionary(mru.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let known = candidates.filter { rank[$0] != nil }.sorted { rank[$0]! < rank[$1]! }
        let unknown = candidates.filter { rank[$0] == nil }
        return known + unknown
    }

    /// Selection when the switcher opens: the previous window, or the last one when going backwards.
    static func initialSelection(count: Int, reverse: Bool) -> Int {
        guard count > 1 else { return 0 }
        return reverse ? count - 1 : 1
    }

    /// Steps the selection by one with wraparound.
    static func step(selection: Int, count: Int, reverse: Bool) -> Int {
        guard count > 0 else { return 0 }
        return (selection + (reverse ? count - 1 : 1)) % count
    }

    /// Type-to-search: every whitespace-separated word of `query` must appear in the title or app name.
    static func matches(query: String, title: String, appName: String) -> Bool {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let haystack = (title + " " + appName).lowercased()
        return words.allSatisfy { haystack.contains($0) }
    }

    /// Grid column count for `count` tiles: one row up to `maxColumns`, then balanced rows.
    static func columns(count: Int, maxColumns: Int = 6) -> Int {
        guard count > 0 else { return 1 }
        guard count > maxColumns else { return count }
        let rows = Int((Double(count) / Double(maxColumns)).rounded(.up))
        return Int((Double(count) / Double(rows)).rounded(.up))
    }

    /// Up/Down: one row at a time, staying put at the first and last row (Left/Right wrap, rows do not).
    static func rowStep(selection: Int, count: Int, columns: Int, down: Bool) -> Int {
        guard count > 0 else { return 0 }
        let next = selection + (down ? columns : -columns)
        return next >= 0 && next < count ? next : selection
    }
}

// MARK: - Numbered Window Switcher Model (Slice 3.1: SC-AltTabNumbered)

/// Pure digit-based direct navigation and shortcut actions for Window Switcher.
enum NumberedWindowSwitcherModel {
    /// Returns 1-based digit badge for index 0...8 ("1"..."9"); nil for index >= 9.
    static func digitBadge(for index: Int) -> String? {
        guard index >= 0, index < 9 else { return nil }
        return "\(index + 1)"
    }

    /// Resolves target selection index from digit (1...9), clamped to available count.
    static func index(forDigit digit: Int, count: Int) -> Int? {
        guard digit >= 1, digit <= 9, count > 0 else { return nil }
        let idx = digit - 1
        return idx < count ? idx : nil
    }

    /// Maps standard macOS ANSI number row key codes (1-9) to integer digits.
    static func digit(fromKeyCode keyCode: UInt16) -> Int? {
        switch keyCode {
        case 18: return 1 // 1
        case 19: return 2 // 2
        case 20: return 3 // 3
        case 21: return 4 // 4
        case 23: return 5 // 5
        case 22: return 6 // 6
        case 26: return 7 // 7
        case 28: return 8 // 8
        case 25: return 9 // 9
        default: return nil
        }
    }
}

// MARK: - Window Management revamp — pure switcher models

/// The five AltTabby-style presentations plus an explicit off state. Pure: the App layer maps this
/// to SwiftUI and the controller maps it to panel/capture behaviour.
enum WindowSwitcherStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case thumbnail
    case list
    case icons
    case classicIcons
    case carousel
    case disabled

    var id: String { rawValue }

    /// Views that show captured window content. List/classic stay icon-only on purpose.
    var usesLiveThumbnails: Bool {
        switch self {
        case .thumbnail, .carousel: return true
        case .list, .icons, .classicIcons, .disabled: return false
        }
    }
}

/// Accent colour kept as plain channels so the pure model has no AppKit dependency. `nil` on the
/// config means "follow the system accent".
struct WindowSwitcherAccentColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    func normalized() -> Self {
        Self(red: min(max(red, 0), 1),
             green: min(max(green, 0), 1),
             blue: min(max(blue, 0), 1),
             alpha: min(max(alpha, 0), 1))
    }
}

/// Per-style geometry and motion. Zero rows/columns mean "automatic"; `normalized()` is the one
/// place a stored value is made safe before it reaches the panel.
struct WindowSwitcherStyleConfig: Codable, Equatable, Sendable {
    var iconSize: Double
    var spacing: Double
    var rows: Int
    var columns: Int
    var opacity: Double
    var accentColor: WindowSwitcherAccentColor?
    var animationSpeed: Double
    var keepOpenOnRelease: Bool

    init(iconSize: Double = 52,
         spacing: Double = 10,
         rows: Int = 0,
         columns: Int = 0,
         opacity: Double = 1,
         accentColor: WindowSwitcherAccentColor? = nil,
         animationSpeed: Double = 1,
         keepOpenOnRelease: Bool = false) {
        self.iconSize = iconSize
        self.spacing = spacing
        self.rows = rows
        self.columns = columns
        self.opacity = opacity
        self.accentColor = accentColor
        self.animationSpeed = animationSpeed
        self.keepOpenOnRelease = keepOpenOnRelease
    }

    static let standard = WindowSwitcherStyleConfig()

    func normalized() -> Self {
        var next = self
        next.iconSize = min(max(iconSize, 16), 128)
        next.spacing = min(max(spacing, 0), 48)
        next.rows = min(max(rows, 0), 8)
        next.columns = min(max(columns, 0), 8)
        next.opacity = min(max(opacity, 0.2), 1)
        next.animationSpeed = min(max(animationSpeed, 0.1), 3)
        next.accentColor = accentColor?.normalized()
        return next
    }
}

/// Blends recency decay with usage frequency. Timestamps are caller-supplied seconds so the model
/// is deterministic and synchronous in tests; production will pass `ProcessInfo.systemUptime` or a
/// monotonic clock.
struct WindowPredictiveRanker: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var lastUsed: Double
        var uses: Int
    }

    private(set) var entries: [String: Entry]
    var halfLife: Double
    var maxEntries: Int

    init(entries: [String: Entry] = [:], halfLife: Double = 1_800, maxEntries: Int = 256) {
        self.entries = entries
        self.halfLife = halfLife
        self.maxEntries = maxEntries
    }

    /// Stable identity for a window across focus changes: bundle + title, as specified by the
    /// revamp plan. Window IDs are deliberately not used here because they can change with tabs.
    static func key(bundleID: String, title: String) -> String {
        "\(bundleID)\u{1F}\(title)"
    }

    mutating func record(_ key: String, at timestamp: Double) {
        guard !key.isEmpty else { return }
        var entry = entries[key] ?? Entry(lastUsed: timestamp, uses: 0)
        entry.uses = min(entry.uses + 1, 10_000)
        entry.lastUsed = max(entry.lastUsed, timestamp)
        entries[key] = entry
        pruneIfNeeded()
    }

    mutating func record(bundleID: String, title: String, at timestamp: Double) {
        record(Self.key(bundleID: bundleID, title: title), at: timestamp)
    }

    func score(bundleID: String, title: String, at timestamp: Double) -> Double {
        score(for: Self.key(bundleID: bundleID, title: title), at: timestamp)
    }

    func score(for key: String, at timestamp: Double) -> Double {
        guard let entry = entries[key] else { return 0 }
        let life = max(halfLife, 0.001)
        let age = max(0, timestamp - entry.lastUsed)
        let recency = pow(0.5, age / life)
        // Frequency is bounded to 0...1 before weighting, so a burst of old uses informs the
        // score without overpowering a window the user just focused.
        let frequency = log1p(Double(entry.uses)) / log1p(10_000)
        return recency * 0.9 + frequency * 0.1
    }

    /// Stable descending order; equal scores preserve the caller's incoming order.
    func order(candidates: [String], at timestamp: Double) -> [String] {
        candidates.enumerated().sorted { lhs, rhs in
            let left = score(for: lhs.element, at: timestamp)
            let right = score(for: rhs.element, at: timestamp)
            return left == right ? lhs.offset < rhs.offset : left > right
        }.map(\.element)
    }

    mutating func resetLearnedData() {
        entries.removeAll()
    }

    private mutating func pruneIfNeeded() {
        let limit = max(1, maxEntries)
        guard entries.count > limit else { return }
        entries = Dictionary(uniqueKeysWithValues: entries
            .sorted { $0.value.lastUsed > $1.value.lastUsed }
            .prefix(limit)
            .map { ($0.key, $0.value) })
    }
}

/// Inputs the controller has at switcher-open time. `nil` means "unknown", never "no windows"; an
/// unknown display/Space must not hide every tile.
struct WindowFilterContext: Equatable, Sendable {
    var currentDisplayUUID: String?
    var currentSpaceWindowIDs: Set<String>?

    init(currentDisplayUUID: String? = nil, currentSpaceWindowIDs: Set<String>? = nil) {
        self.currentDisplayUUID = currentDisplayUUID
        self.currentSpaceWindowIDs = currentSpaceWindowIDs
    }
}

/// Pure filtering policy. Existing behaviour is preserved by the defaults: minimized and hidden
/// windows remain visible, and display/Space filters are opt-in.
struct WindowFilterPolicy: Codable, Equatable, Sendable {
    var currentDisplayOnly: Bool
    var currentSpaceOnly: Bool
    var showMinimized: Bool
    var showHidden: Bool
    var ignoredBundleIDs: [String]

    init(currentDisplayOnly: Bool = false,
         currentSpaceOnly: Bool = false,
         showMinimized: Bool = true,
         showHidden: Bool = true,
         ignoredBundleIDs: [String] = []) {
        self.currentDisplayOnly = currentDisplayOnly
        self.currentSpaceOnly = currentSpaceOnly
        self.showMinimized = showMinimized
        self.showHidden = showHidden
        self.ignoredBundleIDs = ignoredBundleIDs
    }

    var ignoredBundleIDSet: Set<String> {
        Set(ignoredBundleIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }

    func allows(_ window: WindowRecord, context: WindowFilterContext = .init()) -> Bool {
        if let bundleID = window.bundleIdentifier, ignoredBundleIDSet.contains(bundleID) {
            return false
        }

        switch window.status {
        case .active, .inactive:
            break
        case .minimized:
            guard showMinimized else { return false }
        case .hidden:
            guard showHidden else { return false }
        case .closedPending, .disappeared:
            return false
        }

        if currentDisplayOnly,
           let current = context.currentDisplayUUID,
           let windowDisplay = window.displayUUID,
           current != windowDisplay {
            return false
        }
        if currentSpaceOnly,
           let spaceWindowIDs = context.currentSpaceWindowIDs,
           !spaceWindowIDs.contains(window.id.rawValue) {
            return false
        }
        return true
    }

    func filter(_ windows: [WindowRecord], context: WindowFilterContext = .init()) -> [WindowRecord] {
        windows.filter { allows($0, context: context) }
    }

    func normalized() -> Self {
        var next = self
        next.ignoredBundleIDs = ignoredBundleIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return next
    }
}
