import Combine
import Foundation

/// Ref-counted feed driving the Dock II Live System Telemetry wing card.
/// Reuses `SystemMonitorController` (so TelemetryPollingPolicy throttling applies automatically)
/// and adds public battery/thermal state plus opt-in IOHID sensor readings.
@MainActor
final class DockTelemetryFeed: ObservableObject {
    static let shared = DockTelemetryFeed()

    @Published private(set) var state = DockTelemetryState()

    private let monitor = SystemMonitorController()
    private var history = SampleHistory(capacity: 30)
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
        state.downBytesPerSec = snap.down
        state.upBytesPerSec = snap.up
        state.frequencyGHz = nominalGHz
        state.thermalState = PowerThermal(ProcessInfo.processInfo.thermalState)

        // Read GPU & thermal sensors every 2 ticks to keep sampling ultra-light.
        if tickCount % 2 == 1 {
            refreshTemperature()
        }
    }

    private func refreshTemperature() {
        let useIOHID = iohidEnabled
        Task.detached(priority: .utility) {
            let gpu = SystemMonitorSampler.gpu()
            let iohidTemp = useIOHID ? AppleSiliconSensorReader.readSoCTemperatureCelsius() : nil
            let fallbackBatteryTemp = iohidTemp == nil ? BatteryHealthReader.read()?.temperatureCelsius : nil
            let temp = iohidTemp ?? fallbackBatteryTemp
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.state.gpuUsage = gpu
                self.state.temperatureCelsius = temp
            }
        }
    }
}
