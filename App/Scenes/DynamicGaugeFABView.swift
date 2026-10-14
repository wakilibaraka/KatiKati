import SwiftUI

/// Phase 32: Circular dynamic data FAB showing RAM percentage in center
/// and CPU pressure on the surrounding progress arc.
public struct DynamicGaugeFABView: View {
    @StateObject private var monitor = SystemMonitorController()
    @State private var isHovered = false
    var onTap: (() -> Void)?

    public init(onTap: (() -> Void)? = nil) {
        self.onTap = onTap
    }

    public var body: some View {
        let metrics = SystemGaugeMetrics.compute(
            usedMemory: monitor.snapshot.memory.used,
            totalMemory: monitor.snapshot.memory.total,
            cpuUsage: monitor.snapshot.cpu
        )

        ZStack {
            // Dark circular pod backdrop
            Circle()
                .fill(Color(red: 0.11, green: 0.12, blue: 0.15).opacity(0.88))

            // Background track
            Circle()
                .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .padding(4)

            // CPU Pressure Arc
            Circle()
                .trim(from: 0.0, to: max(0.05, CGFloat(metrics.cpuPressure)))
                .stroke(gaugeColor(for: metrics.pressureLevel),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(4)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: metrics.cpuPressure)

            // Center RAM %
            Text(verbatim: "\(metrics.ramPercentage)")
                .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 40, height: 40)
        .overlay(
            Circle()
                .stroke(isHovered ? Color.white.opacity(0.28) : Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isHovered ? 0.35 : 0.18), radius: isHovered ? 6 : 3, x: 0, y: 2)
        .scaleEffect(isHovered ? 1.08 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isHovered)
        .help("RAM: \(metrics.ramPercentage)% • CPU: \(Int(round(metrics.cpuPressure * 100)))%")
        .contentShape(Circle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onTap?()
        }
        .onAppear {
            monitor.acquire()
        }
        .onDisappear {
            monitor.release()
        }
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
