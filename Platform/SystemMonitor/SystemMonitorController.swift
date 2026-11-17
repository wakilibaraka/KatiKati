import AppKit
import Foundation

/// Drives the System monitor flyout. Lazy and ref-counted like `SystemStatusService`: the 1 s timer exists only
/// while at least one view is on screen, so a closed flyout costs nothing.
@MainActor
final class SystemMonitorController: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot()
    /// OW-4: read once when the controller is created; the Rig card only formats it after that.
    @Published private(set) var rigSpec = MacRigSpecSnapshot.current()
    /// OW-2: true while a full-screen app or Low Power Mode has the sampler on its slow cadence.
    @Published private(set) var isThrottled = false
    private var timer: Timer?
    private var currentInterval: TimeInterval = 1
    private var holders = 0
    private var lastCPU: CPUTicks?
    private var lastNet: NetCounters?
    private var lastDisk: DiskCounters?
    private var lastTime = Date()
    private var ticksSinceDiskStat = 0
    private static let diskStatIntervalTicks = 15

    func acquire() {
        holders += 1
        guard timer == nil else { return }
        lastCPU = SystemMonitorSampler.cpuTicks()
        lastNet = SystemMonitorSampler.network()
        lastDisk = SystemMonitorSampler.diskCounters()
        lastTime = Date()
        ticksSinceDiskStat = Self.diskStatIntervalTicks
        refresh()
        schedule(interval: currentInterval)
    }

    /// OW-2: the cadence is decided per tick, so a game going full screen (or Low Power Mode turning on)
    /// slows the sampler without a restart, and leaving it brings the 1 s cadence straight back.
    private func schedule(interval: TimeInterval) {
        currentInterval = interval
        timer?.invalidate()
        let next = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        next.tolerance = min(0.2, interval * 0.1)
        timer = next
    }

    private func tick() {
        refresh()
        let decision = TelemetryPollingPolicy.decision(
            isFullscreenGame: TelemetryEnvironment.isFullscreenGame(),
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        isThrottled = decision.isThrottled
        if let interval = decision.interval, abs(interval - currentInterval) > 0.05 {
            schedule(interval: interval)
        }
    }

    func release() {
        holders = max(0, holders - 1)
        guard holders == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        let now = Date()
        var next = snapshot
        if let ticks = SystemMonitorSampler.cpuTicks() {
            if let last = lastCPU { next.cpu = CPUTicks.usage(from: last, to: ticks) }
            lastCPU = ticks
        }
        let net = SystemMonitorSampler.network()
        if let last = lastNet {
            let r = NetCounters.rate(from: last, to: net, seconds: now.timeIntervalSince(lastTime))
            next.down = r.down; next.up = r.up
        }
        lastNet = net
        let disk = SystemMonitorSampler.diskCounters()
        if let last = lastDisk {
            let r = DiskCounters.rate(from: last, to: disk, seconds: now.timeIntervalSince(lastTime))
            next.diskRead = r.read; next.diskWrite = r.write
        }
        lastDisk = disk
        lastTime = now
        next.memory = SystemMonitorSampler.memory()
        if ticksSinceDiskStat >= Self.diskStatIntervalTicks || next.disk == nil {
            next.disk = SystemMonitorSampler.disk()
            ticksSinceDiskStat = 0
        } else {
            ticksSinceDiskStat += 1
        }
        snapshot = next
    }

    deinit { timer?.invalidate() }
}

extension MacRigSpecSnapshot {
    /// OW-4: one read of the machine (sysctl + ProcessInfo + the boot volume's size), never polled.
    static func current() -> MacRigSpecSnapshot {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let storage = (try? FileManager.default.attributesOfFileSystem(forPath: "/"))?[.systemSize] as? NSNumber
        return MacRigSpecSnapshot(
            chip: sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon",
            physicalCores: sysctlInt("hw.physicalcpu") ?? ProcessInfo.processInfo.processorCount,
            efficiencyCores: sysctlInt("hw.perflevel1.physicalcpu") ?? 0,
            performanceCores: sysctlInt("hw.perflevel0.physicalcpu") ?? 0,
            gpuCores: sysctlInt("hw.gpu.corecount").flatMap { $0 > 0 ? $0 : nil },
            unifiedMemoryGB: memoryGB(ProcessInfo.processInfo.physicalMemory),
            storageGB: storageGB(storage?.int64Value ?? 0),
            macOSVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            macOSBuild: sysctlString("kern.osversion") ?? "-"
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}

/// OW-2: the cheap "another app owns the screen" test, read once per polling tick — a frontmost regular app
/// with a layer-0 window as tall as a screen. KatiKati itself never counts, so the badge only appears for a
/// real game or full-screen app in front.
enum TelemetryEnvironment {
    static func isFullscreenGame() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              front.activationPolicy == .regular,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let screenHeights = NSScreen.screens.map(\.frame.height)
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == front.processIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let height = (bounds["Height"] as? NSNumber)?.doubleValue,
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue,
                  width > 600
            else { continue }
            if screenHeights.contains(where: { abs($0 - CGFloat(height)) < 2 }) { return true }
        }
        return false
    }
}
