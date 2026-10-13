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

struct TopProcess: Equatable, Sendable {
    var name: String
    var cpu: Double
}

enum TopProcessParser {
    /// Parses `ps -Ao pcpu=,comm=` output: sums processes that share a name, highest CPU first, trims to `limit`.
    static func parse(_ text: String, limit: Int) -> [TopProcess] {
        var totals: [String: Double] = [:]
        var order: [String] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "), let cpu = Double(trimmed[..<space]) else { continue }
            let path = trimmed[trimmed.index(after: space)...].trimmingCharacters(in: .whitespaces)
            let name = path.split(separator: "/").last.map(String.init) ?? path
            guard !name.isEmpty, cpu >= 0 else { continue }
            if totals[name] == nil { order.append(name) }
            totals[name, default: 0] += cpu
        }
        return order.map { TopProcess(name: $0, cpu: totals[$0] ?? 0) }
            .sorted { $0.cpu > $1.cpu }
            .prefix(max(0, limit)).map { $0 }
    }
}
