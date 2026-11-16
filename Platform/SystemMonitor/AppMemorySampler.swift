import Darwin
import Foundation

/// Reads physical memory footprint (`ri_phys_footprint`) for a single PID on demand using `proc_pid_rusage`.
enum AppMemorySampler {
    static func physicalFootprintBytes(for pid: pid_t) -> UInt64 {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rusagePtr in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rusagePtr)
            }
        }
        guard result == 0 else { return 0 }
        return info.ri_phys_footprint
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(clamping: bytes))
    }
}
