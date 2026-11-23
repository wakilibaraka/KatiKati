import Foundation

/// Phase 20b — per-app memory for the hold-Control overlay. Pure: process facts in, numbers and text out.
enum ProcessMemory {
    struct Proc: Equatable, Sendable {
        var pid: Int32
        var ppid: Int32
        /// Physical footprint in bytes (what Activity Monitor calls "Memory").
        var bytes: UInt64
    }

    struct AppIdentity: Equatable, Sendable {
        var pid: Int32
        var bundleID: String?
        var name: String
        var isBackgroundApp: Bool
        var isRegularApp: Bool
    }

    struct ProcessEntry: Identifiable, Equatable, Sendable {
        var id: String
        var pid: Int32
        var bundleID: String?
        var name: String
        var bytes: UInt64
        var isBackgroundApp: Bool
        var isHelper: Bool
    }

    private static func claimTreeBytes(
        startingAt root: Int32,
        byPid: [Int32: Proc],
        children: [Int32: [Proc]],
        claimed: inout Set<Int32>
    ) -> UInt64? {
        guard let rootProc = byPid[root], !claimed.contains(root) else { return nil }
        var total: UInt64 = 0
        var stack = [rootProc]
        while let p = stack.popLast() {
            guard claimed.insert(p.pid).inserted else { continue }
            total &+= p.bytes
            stack.append(contentsOf: children[p.pid] ?? [])
        }
        return total
    }

    /// Sum of each app's root process and all its descendants (helper/renderer processes), keyed by bundle id.
    /// Cycles and missing parents are tolerated; a process is attributed to at most one app.
    static func aggregate(procs: [Proc], roots: [String: Int32]) -> [String: UInt64] {
        var children: [Int32: [Proc]] = [:]
        for p in procs { children[p.ppid, default: []].append(p) }
        let byPid = Dictionary(procs.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        var claimed = Set<Int32>()
        var result: [String: UInt64] = [:]
        for (bundle, root) in roots.sorted(by: { $0.key < $1.key }) {
            if let total = claimTreeBytes(startingAt: root, byPid: byPid, children: children, claimed: &claimed) {
                result[bundle] = total
            }
        }
        return result
    }

    /// Ranks running apps (grouped per bundle ID with helper descendants) and high-footprint unclaimed
    /// background processes in descending physical memory order without double-counting shared trees.
    static func rankedUsage(
        procs: [Proc],
        apps: [AppIdentity],
        fallbackNames: [Int32: String] = [:],
        minFallbackBytes: UInt64 = 30 * 1_048_576,
        limit: Int = 24
    ) -> [ProcessEntry] {
        var children: [Int32: [Proc]] = [:]
        for p in procs { children[p.ppid, default: []].append(p) }
        let byPid = Dictionary(procs.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        var claimed = Set<Int32>()
        var entries: [ProcessEntry] = []

        let groupedApps = Dictionary(grouping: apps) { app -> String in
            if let bundleID = app.bundleID, !bundleID.isEmpty { return bundleID }
            return "pid-\(app.pid)"
        }

        for key in groupedApps.keys.sorted() {
            guard let group = groupedApps[key], !group.isEmpty else { continue }
            var total: UInt64 = 0
            for app in group.sorted(by: { $0.pid < $1.pid }) {
                if let subTotal = claimTreeBytes(startingAt: app.pid, byPid: byPid, children: children, claimed: &claimed) {
                    total &+= subTotal
                }
            }
            guard total > 0 else { continue }
            let primary = group.filter(\.isRegularApp).min(by: { $0.pid < $1.pid })
                ?? group.min(by: { $0.pid < $1.pid })
                ?? group[0]
            let isBackgroundApp = group.allSatisfy(\.isBackgroundApp)
            let isHelper = !group.contains(where: \.isRegularApp)
            entries.append(
                ProcessEntry(
                    id: key,
                    pid: primary.pid,
                    bundleID: primary.bundleID,
                    name: primary.name,
                    bytes: total,
                    isBackgroundApp: isBackgroundApp,
                    isHelper: isHelper
                )
            )
        }

        for proc in procs.sorted(by: { $0.pid < $1.pid }) {
            guard !claimed.contains(proc.pid),
                  proc.bytes >= minFallbackBytes,
                  let rawName = fallbackNames[proc.pid]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawName.isEmpty,
                  let total = claimTreeBytes(startingAt: proc.pid, byPid: byPid, children: children, claimed: &claimed),
                  total > 0 else { continue }
            entries.append(
                ProcessEntry(
                    id: "pid-\(proc.pid)",
                    pid: proc.pid,
                    bundleID: nil,
                    name: rawName,
                    bytes: total,
                    isBackgroundApp: false,
                    isHelper: true
                )
            )
        }

        entries.sort { lhs, rhs in
            if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
            let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return lhs.id < rhs.id
        }
        return Array(entries.prefix(max(0, limit)))
    }

    static func totalBytes(entries: [ProcessEntry]) -> UInt64 {
        entries.reduce(0) { $0 &+ $1.bytes }
    }

    enum Tier: Equatable, Sendable { case low, medium, high }

    /// Green under 500 MB, amber under 2 GB, red from 2 GB.
    static func tier(bytes: UInt64) -> Tier {
        if bytes < 500 * 1_048_576 { return .low }
        if bytes < 2 * 1_073_741_824 { return .medium }
        return .high
    }

    /// "812 MB", "1.4 GB" (locale-aware via `ByteCountFormatter`, memory units).
    static func format(bytes: UInt64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        f.allowedUnits = [.useMB, .useGB]
        f.includesUnit = true
        f.isAdaptive = true
        return f.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))))
    }
}
