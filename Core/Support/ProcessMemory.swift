import Foundation

/// Phase 20b — per-app memory for the hold-Control overlay. Pure: process facts in, numbers and text out.
enum ProcessMemory {
    struct Proc: Equatable, Sendable {
        var pid: Int32
        var ppid: Int32
        /// Physical footprint in bytes (what Activity Monitor calls "Memory").
        var bytes: UInt64
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
            guard let rootProc = byPid[root], !claimed.contains(root) else { continue }
            var total: UInt64 = 0
            var stack = [rootProc]
            while let p = stack.popLast() {
                guard claimed.insert(p.pid).inserted else { continue }
                total &+= p.bytes
                stack.append(contentsOf: children[p.pid] ?? [])
            }
            result[bundle] = total
        }
        return result
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
