import Darwin
import Foundation
import IOKit

/// Reads CPU ticks, memory, disk, network byte counters, GPU busy share and battery level.
/// Stateless: the controller keeps the previous sample.
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

    /// GPU busy share (0...1) from IOAccelerator's `PerformanceStatistics` — a de-facto but
    /// undocumented IOKit surface (the same one Stats / iStat Menus read).
    /// shortcut: no public GPU-utilization API exists; swap this if Apple ships one.
    /// nil where the machine reports nothing — never faked as 0.
    static func gpu() -> Double? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != 0 else { break }
            defer { IOObjectRelease(entry) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let stats = dict["PerformanceStatistics"] as? [String: Any] else { continue }
            let raw = (stats["Device Utilization %"] as? Double) ?? (stats["Device Utilization %"] as? Int).map(Double.init)
            if let raw { best = max(best ?? 0, min(1, raw / 100)) }
        }
        return best
    }

    /// Internal battery level and charger state. nil on desktops and when no internal battery
    /// is present — the metric row then reads "–" like any other missing reader.
    static func battery() -> MenuBarBattery? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = (desc[kIOPSCurrentCapacityKey] as? Double) ?? (desc[kIOPSCurrentCapacityKey] as? Int).map(Double.init) ?? 0
            let max = (desc[kIOPSMaxCapacityKey] as? Double) ?? (desc[kIOPSMaxCapacityKey] as? Int).map(Double.init) ?? 100
            let charging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
            guard max > 0 else { return nil }
            let facts = PowerFactsReader.read(isCharging: charging)
            return MenuBarBattery(fraction: min(1, current / max), isCharging: charging,
                                  secondsRemaining: facts.secondsRemaining, watts: facts.watts)
        }
        return nil
    }
}
