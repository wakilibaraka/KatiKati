import Darwin
import Foundation

/// Reads every visible process's physical footprint + parent pid (same-user processes only; others fail and are
/// skipped, so an app we can't measure shows nothing rather than 0).
enum ProcessMemoryReader {
    static func snapshot() -> [ProcessMemory.Proc] {
        var pids = [pid_t](repeating: 0, count: 4096)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        guard count > 0 else { return [] }
        var result: [ProcessMemory.Proc] = []
        result.reserveCapacity(count)
        for pid in pids.prefix(count) where pid > 0 {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { continue }
            var usage = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            guard status == 0 else { continue }
            result.append(.init(pid: pid, ppid: Int32(info.pbi_ppid), bytes: usage.ri_phys_footprint))
        }
        return result
    }
}
