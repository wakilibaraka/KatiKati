import Combine
import Foundation

/// Ref-counted feed driving the Dock II Live System Telemetry wing card.
/// Reuses `SystemMonitorController` (so TelemetryPollingPolicy throttling applies automatically)
/// and adds public battery/thermal state plus opt-in IOHID sensor readings.
@MainActor
final class DockTelemetryFeed: ObservableObject {
    static let shared = DockTelemetryFeed()

    @Published private(set) var state = DockTelemetryState()

    private let monitor = SystemMonitorController.shared
    private var history = SampleHistory(capacity: 30)
    private var ramHistory = SampleHistory(capacity: 30)
    private var networkHistory = SampleHistory(capacity: 30)
    private var cancellable: AnyCancellable?
    private var holders = 0
    private var tickCount = 0
    private let nominalGHz: Double? = AppleSiliconSensorReader.nominalFrequencyGHz()

    private var iohidEnabled: Bool {
        UserDefaults.standard.bool(forKey: "com.katikati.dockII.telemetryIOHIDEnabled")
    }

    private init() {
        cancellable = monitor.$snapshot.dropFirst().sink { [weak self] snap in
            self?.handleSnapshot(snap)
        }
    }

    func retain() {
        holders += 1
        monitor.acquire()
        if holders == 1 {
            if state.frequencyGHz == nil {
                state.frequencyGHz = nominalGHz
            }
            state.thermalState = PowerThermal(ProcessInfo.processInfo.thermalState)
            if tickCount == 0 {
                let mem = SystemMonitorSampler.memory()
                state.memoryFraction = mem.fraction
                state.memoryUsedBytes = mem.used
                state.memoryTotalBytes = mem.total
                ramHistory.append(mem.fraction)
                state.ramHistory = ramHistory.normalized(ceiling: 1.0)
                let disk = SystemMonitorSampler.disk()
                state.diskUsedFraction = disk.usedFraction
                state.diskFreeBytes = disk.free
                state.diskTotalBytes = disk.total
                seedInitialCPUSample()
            }
            refreshTemperature()
        }
    }

    private func seedInitialCPUSample() {
        guard let t0 = SystemMonitorSampler.cpuTicks() else { return }
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(220))
            guard let t1 = SystemMonitorSampler.cpuTicks() else { return }
            let cpu = CPUTicks.usage(from: t0, to: t1)
            await MainActor.run { [weak self] in
                guard let self, self.holders > 0, self.tickCount == 0 else { return }
                self.history.append(cpu)
                self.state.cpuUsage = cpu
                self.state.cpuHistory = self.history.normalized(ceiling: 1.0)
            }
        }
    }

    func release() {
        holders = max(0, holders - 1)
        monitor.release()
    }

    private func handleSnapshot(_ snap: SystemSnapshot) {
        tickCount += 1
        history.append(snap.cpu)
        state.cpuUsage = snap.cpu
        state.cpuHistory = history.normalized(ceiling: 1.0)
        state.memoryFraction = snap.memory.fraction
        state.memoryUsedBytes = snap.memory.used
        state.memoryTotalBytes = snap.memory.total
        ramHistory.append(snap.memory.fraction)
        state.ramHistory = ramHistory.normalized(ceiling: 1.0)
        state.downBytesPerSec = snap.down
        state.upBytesPerSec = snap.up
        let throughput = max(snap.down, snap.up)
        networkHistory.append(throughput)
        let peakNet = max(networkHistory.values.max() ?? 1, 250_000)
        state.networkHistory = networkHistory.normalized(ceiling: peakNet)
        state.diskUsedFraction = snap.disk.usedFraction
        state.diskFreeBytes = snap.disk.free
        state.diskTotalBytes = snap.disk.total
        state.diskReadBytesPerSec = snap.diskRead
        state.diskWriteBytesPerSec = snap.diskWrite
        state.frequencyGHz = nominalGHz
        state.thermalState = PowerThermal(ProcessInfo.processInfo.thermalState)

        // Read GPU & thermal sensors every 2 ticks to keep sampling ultra-light.
        if tickCount % 2 == 1 {
            refreshTemperature()
        }
    }

    func refreshSensorsNow() {
        refreshTemperature()
    }

    private func refreshTemperature() {
        let useIOHID = iohidEnabled
        Task.detached(priority: .utility) {
            let gpu = SystemMonitorSampler.gpu()
            let bat = SystemMonitorSampler.battery()
            let health = BatteryHealthReader.read()
            let iohidTemp = useIOHID ? AppleSiliconSensorReader.readSoCTemperatureCelsius() : nil
            let temp = iohidTemp ?? health?.temperatureCelsius
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.state.gpuUsage = gpu
                self.state.temperatureCelsius = temp
                self.state.batteryFraction = bat?.fraction
                self.state.batteryCharging = bat?.isCharging ?? false
                self.state.batteryWatts = bat?.watts
                self.state.batterySecondsRemaining = bat?.secondsRemaining
                self.state.batteryCycleCount = health?.cycleCount
                self.state.batteryHealthPercent = health?.healthPercent
            }
        }
    }
}
