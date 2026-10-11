import Foundation

/// Drives the System monitor flyout. Lazy and ref-counted like `SystemStatusService`: the 1 s timer exists only
/// while at least one view is on screen, so a closed flyout costs nothing.
@MainActor
final class SystemMonitorController: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot()
    private var timer: Timer?
    private var holders = 0
    private var lastCPU: CPUTicks?
    private var lastNet: NetCounters?
    private var lastTime = Date()

    func acquire() {
        holders += 1
        guard timer == nil else { return }
        lastCPU = SystemMonitorSampler.cpuTicks()
        lastNet = SystemMonitorSampler.network()
        lastTime = Date()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 0.2
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
        lastTime = now
        next.memory = SystemMonitorSampler.memory()
        next.disk = SystemMonitorSampler.disk()
        snapshot = next
    }

    deinit { timer?.invalidate() }
}
