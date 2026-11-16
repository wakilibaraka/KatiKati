import CoreGraphics
import Foundation

enum QuitOnCloseMode: String, CaseIterable, Identifiable, Sendable {
    case off
    case selectedOnly
    case allExceptExcluded
    var id: String { rawValue }
}

/// 53d: which apps may be quit when their last window closes. Off by default and list-driven, because leaving
/// an app running is the safe default and quitting one can end in the app's own save prompt.
struct QuitOnLastWindowPolicy: Equatable, Sendable {
    /// Never ours, whatever a stored list says: the Finder and KatiKati itself are system surfaces.
    static let alwaysIgnored: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.systemuiserver", "com.katikati.app",
    ]

    var mode: QuitOnCloseMode = .selectedOnly
    var bundleIDs: Set<String> = []
    var excludedBundleIDs: Set<String> = []

    func applies(to bundleID: String?) -> Bool {
        guard let id = bundleID, Self.allowsQuitOnClose(id) else { return false }
        switch mode {
        case .off:
            return false
        case .selectedOnly:
            return bundleIDs.contains(id)
        case .allExceptExcluded:
            return !excludedBundleIDs.contains(id)
        }
    }

    /// False for the surfaces the service refuses whatever a stored list says. The app-rules table
    /// asks this before drawing its quit-on-close switch, so the switch is never offered where the
    /// policy would ignore it.
    static func allowsQuitOnClose(_ bundleID: String) -> Bool {
        !alwaysIgnored.contains(bundleID)
    }

    /// Comma/whitespace separated, the same form the key-guard lists use. Empty means off.
    static func parse(_ raw: String, mode: QuitOnCloseMode = .selectedOnly, excludedRaw: String = "") -> QuitOnLastWindowPolicy {
        let selected = Set(raw.split { $0 == "," || $0.isWhitespace }.map(String.init))
        let excluded = Set(excludedRaw.split { $0 == "," || $0.isWhitespace }.map(String.init))
        return QuitOnLastWindowPolicy(mode: mode, bundleIDs: selected, excludedBundleIDs: excluded)
    }

    /// True only for the transition the feature is named after: the app had a window and now has none.
    /// A launch with no window yet, an unknown read, or an app that never had one must never quit.
    static func shouldQuit(hadWindow: Bool, windowCount: Int?) -> Bool {
        guard let windowCount else { return false }
        return hadWindow && windowCount == 0
    }

    /// Filters out zero-size or non-standard helper/popover windows (common in Electron/Chromium apps).
    static func isCountableWindow(subrole: String?, size: CGSize) -> Bool {
        guard size.width > 1, size.height > 1 else { return false }
        guard let subrole else { return true }
        return subrole == "AXStandardWindow" || subrole == "AXDialog"
    }

    static func clampDelay(_ seconds: TimeInterval) -> TimeInterval {
        min(max(seconds, 0.25), 5.0)
    }
}

/// The three per-app exceptions behind quitting as one table: how the app answers ⌘Q (skip the hold,
/// or keep its own), and whether it is quit once its last window closes.
///
/// The table is a *view* of the three strings the services already read —
/// `KeyGuardService.slowQuitExceptions`, `KeyGuardService.passthroughApps` and
/// `QuitOnLastWindowService.apps` — not a fourth store, so Settings and the key tap cannot disagree
/// about which app does what. Two of the columns contradict each other (the pipeline checks
/// pass-through before the deny list), and that is where the exclusivity comes from: `set` clears the
/// one when the other goes on, and `parse` reads a stale overlap the way the pipeline resolves it.
struct QuitAppRules: Equatable, Sendable {
    /// One column of the table. Declaration order is the column order on the page.
    enum Option: String, CaseIterable, Identifiable, Sendable {
        /// The SlowQuit deny list: ⌘Q quits at once instead of holding.
        case skipHold
        /// The SlowQuit pass-through list: the app keeps its own ⌘Q (remote desktops, VMs).
        case ownQuitKey
        /// The quit-on-last-window list: quit once the last window closes.
        case quitOnClose

        var id: String { rawValue }
    }

    struct Row: Identifiable, Equatable, Sendable {
        let bundleID: String
        var skipHold = false
        var ownQuitKey = false
        var quitOnClose = false

        var id: String { bundleID }

        /// A row with every column off is dropped: it would name an app that does nothing.
        var isActive: Bool { skipHold || ownQuitKey || quitOnClose }

        func isOn(_ option: Option) -> Bool {
            switch option {
            case .skipHold: return skipHold
            case .ownQuitKey: return ownQuitKey
            case .quitOnClose: return quitOnClose
            }
        }
    }

    /// Sorted by bundle ID, so the table never reorders itself between a read and a write.
    private(set) var rows: [Row]

    init(rows: [Row] = []) {
        self.rows = Self.normalized(rows)
    }

    func row(_ bundleID: String) -> Row? { rows.first { $0.bundleID == bundleID } }

    // MARK: reading the three lists

    static func parse(skipHold: String, ownQuitKey: String, quitOnClose: String) -> QuitAppRules {
        var byID: [String: Row] = [:]
        for id in split(skipHold) {
            var row = byID[id] ?? Row(bundleID: id)
            row.skipHold = true
            byID[id] = row
        }
        for id in split(ownQuitKey) {
            var row = byID[id] ?? Row(bundleID: id)
            row.ownQuitKey = true
            // The tap checks pass-through first, so an app in both lists keeps its own ⌘Q. Showing
            // both switches on would describe a hold that never happens.
            row.skipHold = false
            byID[id] = row
        }
        for id in split(quitOnClose) where QuitOnLastWindowPolicy.allowsQuitOnClose(id) {
            var row = byID[id] ?? Row(bundleID: id)
            row.quitOnClose = true
            byID[id] = row
        }
        return QuitAppRules(rows: Array(byID.values))
    }

    var skipHoldList: String { Self.serialized(rows.filter(\.skipHold).map(\.bundleID)) }
    var ownQuitKeyList: String { Self.serialized(rows.filter(\.ownQuitKey).map(\.bundleID)) }
    var quitOnCloseList: String { Self.serialized(rows.filter(\.quitOnClose).map(\.bundleID)) }

    // MARK: editing

    /// Turns one column on or off for one app. Turning a column on adds the app to the table;
    /// turning its last column off takes the row away, so the table never holds an app that does
    /// nothing. `quitOnClose` refuses the surfaces the policy always ignores.
    mutating func set(_ option: Option, for bundleID: String, to on: Bool) {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        guard on else {
            guard var row = row(id) else { return }
            switch option {
            case .skipHold: row.skipHold = false
            case .ownQuitKey: row.ownQuitKey = false
            case .quitOnClose: row.quitOnClose = false
            }
            replace(row)
            return
        }
        guard option != .quitOnClose || QuitOnLastWindowPolicy.allowsQuitOnClose(id) else { return }
        var row = row(id) ?? Row(bundleID: id)
        switch option {
        case .skipHold:
            row.skipHold = true
            row.ownQuitKey = false
        case .ownQuitKey:
            row.ownQuitKey = true
            row.skipHold = false
        case .quitOnClose:
            row.quitOnClose = true
        }
        replace(row)
    }

    mutating func remove(_ bundleID: String) {
        rows.removeAll { $0.bundleID == bundleID }
    }

    // MARK: pieces

    /// Comma/whitespace separated, the form every one of these keys has always used.
    static func split(_ raw: String) -> [String] {
        raw.split { $0 == "," || $0.isWhitespace }.map(String.init)
    }

    /// `", "` between sorted IDs. A bundle ID never contains a space, so the lists round-trip.
    static func serialized(_ ids: [String]) -> String {
        ids.sorted().joined(separator: ", ")
    }

    /// A bundle ID is reverse-DNS: at least one dot, no whitespace, no path separators, no leading or
    /// trailing dot. Catches a pasted app name or a stray character before it goes into a list that
    /// otherwise fails silently — nothing matches, nothing says so.
    static func isPlausibleBundleID(_ raw: String) -> Bool {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.contains("."), !id.contains(where: \.isWhitespace) else { return false }
        guard !id.hasPrefix("."), !id.hasSuffix(".") else { return false }
        return !id.contains("/")
    }

    private mutating func replace(_ row: Row) {
        if let index = rows.firstIndex(where: { $0.bundleID == row.bundleID }) {
            rows[index] = row
        } else {
            rows.append(row)
        }
        rows = Self.normalized(rows)
    }

    private static func normalized(_ rows: [Row]) -> [Row] {
        rows.filter(\.isActive).sorted { $0.bundleID < $1.bundleID }
    }
}

// MARK: - Idle & Heavy App Policy (Leaf + Quitter Integration)

enum IdleAppAction: String, CaseIterable, Identifiable, Sendable {
    case off
    case notify
    case hide
    case quit
    case keep
    var id: String { rawValue }
}

/// Pure policy evaluating automatic notification, hiding, or termination of idle background applications.
struct IdleAppAutoQuitPolicy: Equatable, Sendable {
    static let defaultsKey = "com.katikati.apps.autoQuitIdleSeconds"
    static let actionKey = "com.katikati.apps.idleAction"
    static let minMemoryMBKey = "com.katikati.apps.idleMinMemoryMB"
    static let perAppActionsKey = "com.katikati.apps.idlePerAppActions"

    static let protectedPrefixes: [String] = [
        "com.apple.",
        "com.katikati."
    ]

    var idleThresholdSeconds: TimeInterval
    var defaultAction: IdleAppAction
    var minMemoryBytes: UInt64
    var perAppActions: [String: IdleAppAction]

    init(
        idleThresholdSeconds: TimeInterval = 0,
        defaultAction: IdleAppAction = .quit,
        minMemoryBytes: UInt64 = 0,
        perAppActions: [String: IdleAppAction] = [:]
    ) {
        self.idleThresholdSeconds = idleThresholdSeconds
        self.defaultAction = defaultAction
        self.minMemoryBytes = minMemoryBytes
        self.perAppActions = perAppActions
    }

    static func isEligible(bundleID: String?) -> Bool {
        guard let id = bundleID?.lowercased().trimmingCharacters(in: .whitespaces), !id.isEmpty else { return false }
        for prefix in protectedPrefixes {
            if id.hasPrefix(prefix) { return false }
        }
        return true
    }

    func resolvedAction(
        bundleID: String?,
        idleDuration: TimeInterval,
        memoryBytes: UInt64 = 0,
        isPlayingMedia: Bool = false,
        isAgentWorking: Bool = false
    ) -> IdleAppAction? {
        guard idleThresholdSeconds > 0 else { return nil }
        guard Self.isEligible(bundleID: bundleID), let bundleID else { return nil }
        guard !isPlayingMedia && !isAgentWorking else { return nil }

        let effective = perAppActions[bundleID] ?? defaultAction
        guard effective != .off, effective != .keep else { return nil }
        guard idleDuration >= idleThresholdSeconds else { return nil }
        if minMemoryBytes > 0, memoryBytes < minMemoryBytes { return nil }
        return effective
    }

    func shouldQuit(
        bundleID: String?,
        idleDuration: TimeInterval,
        isPlayingMedia: Bool = false,
        isAgentWorking: Bool = false
    ) -> Bool {
        resolvedAction(
            bundleID: bundleID,
            idleDuration: idleDuration,
            isPlayingMedia: isPlayingMedia,
            isAgentWorking: isAgentWorking
        ) == .quit
    }

    static func parsePerAppActions(_ raw: String) -> [String: IdleAppAction] {
        var result: [String: IdleAppAction] = [:]
        for entry in raw.split(separator: ",") {
            let parts = entry.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let id = String(parts[0]).trimmingCharacters(in: .whitespaces)
            if let action = IdleAppAction(rawValue: String(parts[1]).trimmingCharacters(in: .whitespaces)) {
                result[id] = action
            }
        }
        return result
    }

    static func serializePerAppActions(_ map: [String: IdleAppAction]) -> String {
        map.keys.sorted().compactMap { key in
            guard let action = map[key], action != .off else { return nil }
            return "\(key)=\(action.rawValue)"
        }.joined(separator: ", ")
    }
}
