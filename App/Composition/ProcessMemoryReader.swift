import AppKit
import Combine
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

    static func processName(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let name = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

/// Zero-idle-CPU off-main-thread process & RAM sampler, active strictly while the `Processes & RAM` tab is open.
@MainActor
final class ActivityProcessMonitor: ObservableObject {
    @Published private(set) var entries: [ProcessMemory.ProcessEntry] = []
    @Published private(set) var totalBytes: UInt64 = 0
    @Published private(set) var hasSampled = false

    private var pollTask: Task<Void, Never>?

    func start(backgroundIDsProvider: @escaping () -> Set<String>) {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let bgIDs = backgroundIDsProvider()
                let runningApps = NSWorkspace.shared.runningApplications
                    .filter { !$0.isTerminated }
                    .map { app in
                        let bid = app.bundleIdentifier
                        return ProcessMemory.AppIdentity(
                            pid: app.processIdentifier,
                            bundleID: bid,
                            name: app.localizedName ?? bid ?? "PID \(app.processIdentifier)",
                            isBackgroundApp: bid.map { bgIDs.contains($0) } ?? false,
                            isRegularApp: app.activationPolicy == .regular
                        )
                    }
                let appPids = Set(runningApps.map(\.pid))
                let ranked = await Task.detached(priority: .utility) {
                    let procs = ProcessMemoryReader.snapshot()
                    var fallbackNames: [Int32: String] = [:]
                    let minBytes: UInt64 = 30 * 1_048_576
                    for proc in procs where proc.bytes >= minBytes && !appPids.contains(proc.pid) {
                        if let name = ProcessMemoryReader.processName(pid: proc.pid) {
                            fallbackNames[proc.pid] = name
                        }
                    }
                    return ProcessMemory.rankedUsage(procs: procs, apps: runningApps, fallbackNames: fallbackNames, limit: 24)
                }.value
                guard !Task.isCancelled else { break }
                self.entries = ranked
                self.totalBytes = ProcessMemory.totalBytes(entries: ranked)
                self.hasSampled = true
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    deinit {
        pollTask?.cancel()
    }
}
