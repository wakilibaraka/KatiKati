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
