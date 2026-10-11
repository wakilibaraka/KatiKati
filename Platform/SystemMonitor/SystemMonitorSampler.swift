import Darwin
import Foundation

/// Reads CPU ticks, memory, disk and network byte counters. Stateless: the controller keeps the previous sample.
enum SystemMonitorSampler {
    static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks   // (user, system, idle, nice)
        return CPUTicks(user: UInt64(t.0), system: UInt64(t.1), idle: UInt64(t.2), nice: UInt64(t.3))
    }

    /// "Used" the way Activity Monitor counts it: active + wired + compressed pages.
    static func memory() -> MemoryUsage {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else { return MemoryUsage(used: 0, total: total) }
        let page = UInt64(vm_kernel_page_size)
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        return MemoryUsage(used: min(used, total), total: total)
    }

    static func disk() -> DiskUsage {
        let url = URL(fileURLWithPath: "/")
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        return DiskUsage(free: UInt64(max(0, values?.volumeAvailableCapacityForImportantUsage ?? 0)),
                         total: UInt64(max(0, values?.volumeTotalCapacity ?? 0)))
    }

    /// Sum of received/sent bytes over the non-loopback `en*` interfaces (Wi-Fi, Ethernet, Thunderbolt bridges).
    static func network() -> NetCounters {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return NetCounters(received: 0, sent: 0) }
        defer { freeifaddrs(list) }
        var rx: UInt64 = 0, tx: UInt64 = 0
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), let data = ifa.ifa_data,
                  String(cString: ifa.ifa_name).hasPrefix("en") else { continue }
            let d = data.assumingMemoryBound(to: if_data.self).pointee
            rx &+= UInt64(d.ifi_ibytes); tx &+= UInt64(d.ifi_obytes)
        }
        return NetCounters(received: rx, sent: tx)
    }
}
