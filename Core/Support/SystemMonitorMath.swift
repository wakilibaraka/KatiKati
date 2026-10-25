import Foundation

/// Pure arithmetic for the System monitor flyout (Phase 7A-8c): platform samplers feed raw counters in, these turn
/// two samples into rates and fractions. No Mach / IOKit here.
struct CPUTicks: Equatable, Sendable {
    var user: UInt64, system: UInt64, idle: UInt64, nice: UInt64

    var total: UInt64 { user &+ system &+ idle &+ nice }

    /// Busy share (0...1) between two samples; 0 when nothing elapsed or a counter went backwards.
    static func usage(from a: CPUTicks, to b: CPUTicks) -> Double {
        guard b.total > a.total, b.idle >= a.idle else { return 0 }
        let total = Double(b.total - a.total)
        let idle = Double(b.idle - a.idle)
        return min(1, max(0, (total - idle) / total))
    }
}

struct NetCounters: Equatable, Sendable {
    var received: UInt64, sent: UInt64

    /// Bytes per second between two samples. A counter that went down (interface reset, 32-bit wrap) reads as 0
    /// rather than a huge spike.
    static func rate(from a: NetCounters, to b: NetCounters, seconds: Double) -> (down: Double, up: Double) {
        guard seconds > 0 else { return (0, 0) }
        let down = b.received >= a.received ? Double(b.received - a.received) / seconds : 0
        let up = b.sent >= a.sent ? Double(b.sent - a.sent) / seconds : 0
        return (down, up)
    }
}

/// Cumulative bytes read from / written to storage (IOBlockStorageDriver statistics).
struct DiskCounters: Equatable, Sendable {
    var read: UInt64, written: UInt64

    /// Bytes per second between two samples; a counter that went down (a drive was unplugged) reads as 0.
    static func rate(from a: DiskCounters, to b: DiskCounters, seconds: Double) -> (read: Double, write: Double) {
        guard seconds > 0 else { return (0, 0) }
        let r = b.read >= a.read ? Double(b.read - a.read) / seconds : 0
        let w = b.written >= a.written ? Double(b.written - a.written) / seconds : 0
        return (r, w)
    }
}

struct MemoryUsage: Equatable, Sendable {
    var used: UInt64
    var total: UInt64
    var fraction: Double { total == 0 ? 0 : min(1, Double(used) / Double(total)) }
}

struct DiskUsage: Equatable, Sendable {
    var free: UInt64
    var total: UInt64
    var usedFraction: Double { total == 0 ? 0 : min(1, max(0, 1 - Double(free) / Double(total))) }
}

/// One refresh worth of numbers for the flyout.
struct SystemSnapshot: Equatable, Sendable {
    var cpu: Double = 0
    var memory = MemoryUsage(used: 0, total: 0)
    var disk = DiskUsage(free: 0, total: 0)
    var down: Double = 0
    var up: Double = 0
    /// Storage throughput in bytes per second.
    var diskRead: Double = 0
    var diskWrite: Double = 0
}

enum SystemMonitorFormat {
    /// Compact menu-bar text, e.g. `CPU 12% · MEM 61%`. Phase 20c.
    static func menuBarTitle(_ snapshot: SystemSnapshot) -> String {
        "CPU \(percent(snapshot.cpu)) · MEM \(percent(snapshot.memory.fraction))"
    }

    /// `0%`…`100%`.
    static func percent(_ fraction: Double) -> String { "\(Int((min(1, max(0, fraction)) * 100).rounded()))%" }

    /// Binary-free (1000-based, like Finder) size: `0 KB`, `12.3 MB`, `1.50 GB`.
    static func bytes(_ value: Double) -> String {
        let v = max(0, value)
        switch v {
        case ..<1_000: return String(format: "%.0f B", v)
        case ..<1_000_000: return String(format: "%.0f KB", v / 1_000)
        case ..<1_000_000_000: return String(format: "%.1f MB", v / 1_000_000)
        case ..<1_000_000_000_000: return String(format: "%.2f GB", v / 1_000_000_000)
        default: return String(format: "%.2f TB", v / 1_000_000_000_000)
        }
    }
}

// MARK: - Battery health + top processes (Phase 16m: moved verbatim from PinboardMonitor.swift)

/// Battery health from the `AppleSmartBattery` registry entry (Phase 7B-V3). Pure parsing; the Platform reader
/// supplies the dictionary. Public IOKit only.
struct BatteryHealth: Equatable, Sendable {
    var cycleCount: Int
    var healthPercent: Int?
    var temperatureCelsius: Double?

    init?(registry info: [String: Any]) {
        guard let cycles = info["CycleCount"] as? Int else { return nil }
        cycleCount = cycles
        // Apple Silicon reports MaxCapacity as a percentage; Intel as mAh next to DesignCapacity.
        let design = info["DesignCapacity"] as? Int
        let rawMax = (info["AppleRawMaxCapacity"] as? Int) ?? (info["MaxCapacity"] as? Int)
        if let design, design > 0, let rawMax, rawMax > 100 {
            healthPercent = min(100, Int((Double(rawMax) / Double(design) * 100).rounded()))
        } else if let m = info["MaxCapacity"] as? Int, m <= 100 {
            healthPercent = m
        } else {
            healthPercent = nil
        }
        // Reported in hundredths of a degree.
        temperatureCelsius = (info["Temperature"] as? Int).map { Double($0) / 100 }
    }
}

struct TopProcess: Equatable, Hashable, Sendable {
    var pid: Int32?
    var name: String
    var cpu: Double

    /// A row without a pid offers no action — it can only print a name and a percentage.
    var canAct: Bool { pid != nil }
}

enum TopProcessParser {
    /// Parses `ps -Ao pid=,pcpu=,comm= -r` output: one row per pid, highest CPU first,
    /// trims to `limit`. Same-named processes stay separate rows — summing them would
    /// destroy the pid the kill flow needs. A line with no parsable pid still draws,
    /// but with `pid == nil` it offers no action.
    static func parse(_ text: String, limit: Int) -> [TopProcess] {
        var rows: [TopProcess] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }
            // Pid form wins when it parses; otherwise the line is a pid-less reading.
            if parts.count >= 3, let pid = Int32(parts[0]), let cpu = Double(parts[1]), cpu >= 0 {
                let name = Self.baseName(of: parts[2...].joined(separator: " "))
                guard !name.isEmpty else { continue }
                rows.append(TopProcess(pid: pid, name: name, cpu: cpu))
            } else if let cpu = Double(parts[0]), cpu >= 0 {
                let name = Self.baseName(of: parts[1...].joined(separator: " "))
                guard !name.isEmpty else { continue }
                rows.append(TopProcess(pid: nil, name: name, cpu: cpu))
            }
        }
        return rows.sorted { $0.cpu > $1.cpu }.prefix(max(0, limit)).map { $0 }
    }

    private static func baseName(of path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}
