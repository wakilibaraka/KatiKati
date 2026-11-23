import AppKit
import SwiftUI

/// Configurable icon face shared between the in-dock 4-square `Background & Activity` tile and the detached capsule.
struct BackgroundActivityIconView: View {
    let mode: BackgroundActivityIconMode
    let memberIDs: [String]
    var scale: CGFloat = 1.0

    var body: some View {
        switch mode {
        case .grid3x3:
            if memberIDs.isEmpty {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 18 * scale, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .frame(width: 34 * scale, height: 34 * scale)
                    .accessibilityHidden(true)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(9 * scale), spacing: 3.5 * scale), count: 3),
                          alignment: .center, spacing: 3.5 * scale) {
                    ForEach(Array(memberIDs.prefix(9)), id: \.self) { id in
                        Image(nsImage: AppIconResolver.icon(for: id))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 9 * scale, height: 9 * scale)
                    }
                }
                .frame(width: 34 * scale, height: 34 * scale, alignment: .center)
                .accessibilityHidden(true)
            }
        case .ramPercent:
            DynamicGaugeCompactDiscView(scale: scale)
        case .cpuPercent:
            MonitoredGaugeDiscView(kind: .cpu, scale: scale)
        case .ramPressureRing:
            MonitoredGaugeDiscView(kind: .pressure, scale: scale)
        case .appCount:
            DrawerCapsuleBackgroundDiscView(count: memberIDs.count, scale: scale)
        }
    }
}

private struct CircularGaugeDiscView: View {
    let scale: CGFloat
    let progress: Double
    let level: SystemGaugeMetrics.PressureLevel
    let centerText: String
    let centerFontSize: CGFloat
    let helpText: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round))
                .padding(4 * scale)

            Circle()
                .trim(from: 0.0, to: max(0.05, CGFloat(progress)))
                .stroke(gaugeColor(for: level),
                        style: StrokeStyle(lineWidth: 3 * scale, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(4 * scale)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)

            Text(verbatim: centerText)
                .font(.system(size: centerFontSize * scale, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(width: 40 * scale, height: 40 * scale)
        .help(Text(verbatim: helpText))
    }

    private func gaugeColor(for level: SystemGaugeMetrics.PressureLevel) -> Color {
        switch level {
        case .normal: return Color(red: 0.25, green: 0.85, blue: 0.55)
        case .warning: return Color(red: 1.0, green: 0.65, blue: 0.20)
        case .critical: return Color(red: 1.0, green: 0.32, blue: 0.32)
        }
    }
}

/// Standalone circular gauge disc showing RAM percentage in center and CPU pressure on the outer arc.
public struct DynamicGaugeCompactDiscView: View {
    var scale: CGFloat = 1.0

    public init(scale: CGFloat = 1.0) {
        self.scale = scale
    }

    public var body: some View {
        MonitoredGaugeDiscView(kind: .ram, scale: scale)
    }
}

private struct MonitoredGaugeDiscView: View {
    enum Kind { case ram, cpu, pressure }

    let kind: Kind
    let scale: CGFloat
    @StateObject private var monitor = SystemMonitorController()

    var body: some View {
        let metrics = SystemGaugeMetrics.compute(
            usedMemory: monitor.snapshot.memory.used,
            totalMemory: monitor.snapshot.memory.total,
            cpuUsage: monitor.snapshot.cpu
        )
        let cpuPct = Int(round(metrics.cpuPressure * 100))
        let progress = (kind == .pressure) ? Double(metrics.ramPercentage) / 100.0 : metrics.cpuPressure
        let label: String = switch kind {
        case .ram: "\(metrics.ramPercentage)"
        case .cpu: "\(cpuPct)"
        case .pressure: "RAM"
        }
        CircularGaugeDiscView(
            scale: scale,
            progress: progress,
            level: metrics.pressureLevel,
            centerText: label,
            centerFontSize: kind == .pressure ? 9 : 13,
            helpText: "RAM: \(metrics.ramPercentage)% • CPU: \(cpuPct)%"
        )
        .onAppear { monitor.acquire() }
        .onDisappear { monitor.release() }
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
