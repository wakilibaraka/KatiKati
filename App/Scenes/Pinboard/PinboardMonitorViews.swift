import SwiftUI

// V3 cards: system monitor, network, battery health, top apps, device batteries. Every card starts its sampling in
// onAppear and stops in onDisappear, and the panel tears its content down on close, so a hidden Pinboard costs nothing.

private struct Ring: View {
    let fraction: Double
    let label: Text
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.22), lineWidth: 8)
                Circle().trim(from: 0, to: max(0.02, fraction))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                Text(verbatim: value).font(.system(size: 13, weight: .bold)).monospacedDigit()
            }
            .frame(width: 70, height: 70)
            label.font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
    }
}

struct PinboardSystemCard: View {
    @ObservedObject private var monitor = ProductivityServices.shared.systemMonitor
    var body: some View {
        let s = monitor.snapshot
        WidgetCard(widget: .system, title: Text("System")) {
            HStack {
                Ring(fraction: s.cpu, label: Text("CPU"), value: SystemMonitorFormat.percent(s.cpu))
                Ring(fraction: s.memory.fraction, label: Text("Memory"), value: SystemMonitorFormat.percent(s.memory.fraction))
                Ring(fraction: s.disk.usedFraction, label: Text("Disk"), value: SystemMonitorFormat.percent(s.disk.usedFraction))
            }
        }
        .onAppear { monitor.acquire() }
        .onDisappear { monitor.release() }
    }
}

struct PinboardNetworkCard: View {
    @ObservedObject private var monitor = ProductivityServices.shared.systemMonitor
    var body: some View {
        let s = monitor.snapshot
        WidgetCard(widget: .network, title: Text("Network")) {
            row("arrow.down", s.down)
            row("arrow.up", s.up)
        }
        .onAppear { monitor.acquire() }
        .onDisappear { monitor.release() }
    }

    private func row(_ symbol: String, _ rate: Double) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold))
            Text(verbatim: SystemMonitorFormat.bytes(rate) + "/s").font(.system(size: 17, weight: .semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.top, 4)
    }
}

struct PinboardBatteryCard: View {
    @StateObject private var status = SystemStatusService()
    @State private var health: BatteryHealth?

    var body: some View {
        let b = status.status.battery
        WidgetCard(widget: .battery, title: Text("Battery")) {
            if let level = b.level {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: "\(level)%").font(.system(size: 36, weight: .semibold)).monospacedDigit()
                    if b.isCharging { Image(systemName: "bolt.fill").font(.system(size: 14)) }
                }
                if let h = health {
                    if let pct = h.healthPercent {
                        HStack(spacing: 4) { Text("Health"); Text(verbatim: "\(pct)%") }
                            .font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.85))
                    }
                    HStack(spacing: 4) { Text("Cycles"); Text(verbatim: "\(h.cycleCount)") }
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.75))
                }
            } else {
                Text("No Battery").font(.system(size: 13)).foregroundColor(.white.opacity(0.85))
            }
        }
        .onAppear { status.acquire(); health = BatteryHealthReader.read() }
        .onDisappear { status.release() }
    }
}

@MainActor
private final class TopAppsModel: ObservableObject {
    @Published var rows: [TopProcess] = []
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 1
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func refresh() {
        Task.detached(priority: .utility) {
            let top = TopProcessReader.read(limit: 4)
            await MainActor.run { [weak self] in self?.rows = top }
        }
    }
}

struct PinboardTopAppsCard: View {
    @StateObject private var model = TopAppsModel()
    var body: some View {
        WidgetCard(widget: .topApps, title: Text("Top Apps")) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.rows, id: \.name) { p in
                    HStack {
                        Text(verbatim: p.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(verbatim: String(format: "%.0f%%", p.cpu)).font(.system(size: 12, weight: .bold)).monospacedDigit()
                    }
                }
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}

@MainActor
private final class BatteriesModel: ObservableObject {
    @Published var devices: [BluetoothDevice] = []
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 20
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func refresh() {
        Task {
            let all = await BluetoothDeviceReader.read()
            devices = all.filter { $0.isConnected && $0.lowestBattery != nil }
        }
    }
}

struct PinboardBatteriesCard: View {
    @StateObject private var status = SystemStatusService()
    @StateObject private var model = BatteriesModel()

    var body: some View {
        WidgetCard(widget: .batteries, title: Text("Batteries")) {
            VStack(alignment: .leading, spacing: 7) {
                if let level = status.status.battery.level { line("laptopcomputer", Text("This Mac"), level) }
                ForEach(model.devices.prefix(4)) { d in line(d.symbolName, Text(verbatim: d.name), d.lowestBattery ?? 0) }
                if model.devices.isEmpty {
                    Text("No connected devices report a battery").font(.system(size: 11)).foregroundColor(.white.opacity(0.75))
                }
            }
        }
        .onAppear { status.acquire(); model.start() }
        .onDisappear { status.release(); model.stop() }
    }

    private func line(_ symbol: String, _ name: Text, _ level: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13)).frame(width: 20)
            name.font(.system(size: 12, weight: .medium)).lineLimit(1)
            Spacer(minLength: 4)
            Capsule().fill(Color.white.opacity(0.22)).frame(width: 60, height: 7)
                .overlay(alignment: .leading) {
                    Capsule().fill(level < 20 ? Color.red : Color.white).frame(width: 60 * CGFloat(level) / 100, height: 7)
                }
            Text(verbatim: "\(level)%").font(.system(size: 12, weight: .bold)).monospacedDigit().frame(width: 38, alignment: .trailing)
        }
    }
}
