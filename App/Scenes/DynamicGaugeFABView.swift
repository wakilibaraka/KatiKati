import SwiftUI

/// Standalone circular gauge disc showing RAM percentage in center and CPU pressure on the outer arc.
public struct DynamicGaugeCompactDiscView: View {
    @StateObject private var monitor = SystemMonitorController()
    var scale: CGFloat = 1.0

    public init(scale: CGFloat = 1.0) {
        self.scale = scale
    }

    public var body: some View {
        let metrics = SystemGaugeMetrics.compute(
            usedMemory: monitor.snapshot.memory.used,
            totalMemory: monitor.snapshot.memory.total,
            cpuUsage: monitor.snapshot.cpu
        )

        ZStack {
            // Background track
            Circle()
                .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round))
                .padding(4 * scale)

            // CPU Pressure Arc
            Circle()
                .trim(from: 0.0, to: max(0.05, CGFloat(metrics.cpuPressure)))
                .stroke(gaugeColor(for: metrics.pressureLevel),
                        style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(4 * scale)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: metrics.cpuPressure)

            // Center RAM %
            Text(verbatim: "\(metrics.ramPercentage)")
                .font(.system(size: 13 * scale, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 40 * scale, height: 40 * scale)
        .onAppear { monitor.acquire() }
        .onDisappear { monitor.release() }
        .help(Text(verbatim: "RAM: \(metrics.ramPercentage)% • CPU: \(Int(round(metrics.cpuPressure * 100)))%"))
    }

    private func gaugeColor(for level: SystemGaugeMetrics.PressureLevel) -> Color {
        switch level {
        case .normal:
            return Color(red: 0.25, green: 0.85, blue: 0.55)
        case .warning:
            return Color(red: 1.0, green: 0.65, blue: 0.20)
        case .critical:
            return Color(red: 1.0, green: 0.32, blue: 0.32)
        }
    }
}


/// 57e — the drawer capsule's empty state: how many background apps the drawer is holding. The RAM /
/// CPU reading that used to be drawn here moved into the tooltip, where it costs no glyph space; the
/// disc is shown only when the count is above zero, so an empty background keeps the RAM gauge.
struct DrawerCapsuleBackgroundDiscView: View {
    let count: Int
    var scale: CGFloat = 1.0
    @StateObject private var monitor = SystemMonitorController()

    var body: some View {
        let metrics = SystemGaugeMetrics.compute(
            usedMemory: monitor.snapshot.memory.used,
            totalMemory: monitor.snapshot.memory.total,
            cpuUsage: monitor.snapshot.cpu
        )
        let label = "\(count) \(String(localized: "Background Apps"))"
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round))
                .padding(4 * scale)
            VStack(spacing: 1 * scale) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 10 * scale, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                Text(verbatim: "\(count)")
                    .font(.system(size: 15 * scale, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: 40 * scale, height: 40 * scale)
        .onAppear { monitor.acquire() }
        .onDisappear { monitor.release() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
        .help(Text(verbatim: "\(label) • RAM: \(metrics.ramPercentage)% • CPU: \(Int(round(metrics.cpuPressure * 100)))%"))
    }
}
