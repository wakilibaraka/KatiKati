import AppKit
import SwiftUI

/// DeXign Studio Dock II Live Telemetry wing widget supporting CPU, RAM, Network, Disk, and Battery.
/// Powered by `DockTelemetryFeed` (`SystemMonitorController` + `PowerThermal` + opt-in IOHID sensors).
struct DockTelemetryWidgetView: View {
    var preset: DockWidgetPresetType = .telemetry

    @Environment(\.widgetSize) private var size
    @Environment(\.dockWingVertical) private var isVertical
    @Environment(\.dockPopoverEdge) private var popoverEdge
    @ObservedObject private var feed = DockTelemetryFeed.shared
    @State private var showDetails = false

    private struct DisplaySpec {
        let primary: String
        let trailing: String
        let trailingColor: Color
        let values: [Double]
        let fillColors: [Color]
        let strokeColors: [Color]
    }

    var body: some View {
        let spec = resolveSpec(for: feed.state)
        let sparkValues = normalizedSparkValues(spec.values, seedFloor: 0.08)

        Group {
            if isVertical {
                verticalBody(spec: spec, sparkValues: sparkValues)
            } else {
                ZStack(alignment: .bottom) {
                    ThermalSparklineCanvas(
                        values: sparkValues,
                        fillColors: spec.fillColors,
                        strokeColors: spec.strokeColors
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 18)
                    .padding(.bottom, 2)

                    HStack(spacing: 6) {
                        Text(verbatim: spec.primary)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(DockWidgetStyle.ink)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        Text(verbatim: spec.trailing)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(spec.trailingColor)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.top, 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .popover(isPresented: $showDetails, arrowEdge: popoverEdge) {
            DockTelemetryPreviewCard(onOpenActivityMonitor: {
                showDetails = false
                SystemDockActions.openActivityMonitor()
            })
        }
        .onTapGesture {
            showDetails.toggle()
        }
        .onAppear { feed.retain() }
        .onDisappear { feed.release() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(spec.primary) \(spec.trailing)"))
        .accessibilityAddTraits(.isButton)
    }

    private func verticalBody(spec: DisplaySpec, sparkValues: [Double]) -> some View {
        let compactValue = verticalPrimaryMetric(for: feed.state)
        let shortTag = verticalTagLabel
        return ZStack(alignment: .bottom) {
            ThermalSparklineCanvas(
                values: sparkValues,
                fillColors: spec.fillColors,
                strokeColors: spec.strokeColors
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, size == .small ? 18 : 30)
            .padding(.bottom, size == .small ? 2 : 16)

            VStack(spacing: 2) {
                Text(verbatim: shortTag)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(DockWidgetStyle.ink.opacity(0.62))
                    .lineLimit(1)
                Text(verbatim: compactValue)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(DockWidgetStyle.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 0)
                if size != .small {
                    Text(verbatim: spec.trailing)
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(spec.trailingColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var verticalTagLabel: String {
        switch preset {
        case .ram: return "RAM"
        case .network: return "NET"
        case .disk: return "SSD"
        case .battery: return "BAT"
        default: return "CPU"
        }
    }

    private func verticalPrimaryMetric(for state: DockTelemetryState) -> String {
        switch preset {
        case .ram: return SystemMonitorFormat.percent(state.memoryFraction)
        case .network: return DockVpnRateFormat.formatted(state.downBytesPerSec)
        case .disk: return SystemMonitorFormat.percent(state.diskUsedFraction)
        case .battery: return SystemMonitorFormat.percent(state.batteryFraction ?? 1.0)
        default: return SystemMonitorFormat.percent(state.cpuUsage)
        }
    }

    private func normalizedSparkValues(_ history: [Double], seedFloor: Double) -> [Double] {
        if history.isEmpty {
            return [seedFloor * 0.72, seedFloor * 0.88, seedFloor * 0.82, seedFloor, seedFloor * 0.94]
        }
        if history.count == 1 {
            let single = history[0]
            return [single * 0.85, single, single]
        }
        return history
    }

    private func resolveSpec(for state: DockTelemetryState) -> DisplaySpec {
        switch preset {
        case .ram:
            let mem = MemoryUsage(used: state.memoryUsedBytes, total: state.memoryTotalBytes)
            let pctStr = SystemMonitorFormat.percent(state.memoryFraction)
            let primary = size == .small ? pctStr : (size == .large && mem.total > 0 ? "RAM: \(mem.formattedGigabytesPair)" : "RAM: \(pctStr)")
            let badgeColor: Color = switch mem.pressureLevel {
            case .normal: Color(red: 0.30, green: 0.84, blue: 0.62)
            case .warning: DockWidgetStyle.warn
            case .critical: DockWidgetStyle.bad
            }
            let values = state.ramHistory.isEmpty ? [max(0.08, state.memoryFraction)] : state.ramHistory
            return DisplaySpec(
                primary: primary,
                trailing: mem.pressureLabel,
                trailingColor: badgeColor,
                values: values,
                fillColors: [Color(red: 0.22, green: 0.82, blue: 0.72).opacity(0.58), Color(red: 0.14, green: 0.56, blue: 0.82).opacity(0.32), Color(red: 0.12, green: 0.42, blue: 0.66).opacity(0.18)],
                strokeColors: [Color(red: 0.34, green: 0.90, blue: 0.76), Color(red: 0.24, green: 0.68, blue: 0.96)]
            )

        case .network:
            let down = DockVpnRateFormat.formatted(state.downBytesPerSec)
            let up = DockVpnRateFormat.formatted(state.upBytesPerSec)
            let primary = size == .small ? "↓\(down)" : "↓ \(down)"
            let trailing = size == .small ? "↑" : "↑ \(up)"
            return DisplaySpec(
                primary: primary,
                trailing: trailing,
                trailingColor: Color(red: 0.44, green: 0.80, blue: 0.98),
                values: state.networkHistory,
                fillColors: [Color(red: 0.24, green: 0.72, blue: 0.98).opacity(0.60), Color(red: 0.28, green: 0.46, blue: 0.92).opacity(0.32), Color(red: 0.16, green: 0.28, blue: 0.64).opacity(0.16)],
                strokeColors: [Color(red: 0.42, green: 0.84, blue: 1.0), Color(red: 0.46, green: 0.58, blue: 0.98)]
            )

        case .disk:
            let pct = SystemMonitorFormat.percent(state.diskUsedFraction)
            let freeStr = state.diskTotalBytes > 0 ? "\(SystemMonitorFormat.bytes(Double(state.diskFreeBytes))) free" : "SSD"
            return DisplaySpec(
                primary: size == .small ? pct : "SSD: \(pct)",
                trailing: size == .small ? freeStr.replacingOccurrences(of: " free", with: "") : freeStr,
                trailingColor: Color(red: 0.72, green: 0.68, blue: 0.98),
                values: [state.diskUsedFraction, state.diskUsedFraction, state.diskUsedFraction],
                fillColors: [Color(red: 0.56, green: 0.52, blue: 0.96).opacity(0.55), Color(red: 0.36, green: 0.44, blue: 0.84).opacity(0.28), Color(red: 0.20, green: 0.24, blue: 0.54).opacity(0.16)],
                strokeColors: [Color(red: 0.72, green: 0.68, blue: 1.0), Color(red: 0.44, green: 0.62, blue: 0.96)]
            )

        case .battery:
            let frac = state.batteryFraction ?? 1.0
            let pct = SystemMonitorFormat.percent(frac)
            let bolt = state.batteryCharging ? " ⚡" : ""
            let trailing = state.batteryWatts.map { String(format: "%.0fW", $0) } ?? state.thermalState.name
            return DisplaySpec(
                primary: size == .small ? "\(pct)\(bolt)" : "Bat: \(pct)\(bolt)",
                trailing: trailing,
                trailingColor: frac < 0.2 ? DockWidgetStyle.bad : Color(red: 0.42, green: 0.90, blue: 0.56),
                values: [frac, frac, frac],
                fillColors: [Color(red: 0.28, green: 0.86, blue: 0.48).opacity(0.58), Color(red: 0.62, green: 0.84, blue: 0.30).opacity(0.30), Color(red: 0.20, green: 0.52, blue: 0.28).opacity(0.16)],
                strokeColors: [Color(red: 0.42, green: 0.94, blue: 0.58), Color(red: 0.76, green: 0.88, blue: 0.34)]
            )

        default:
            let cpuText = state.frequencyGHz.map { String(format: "CPU: %.1f GHz", $0) } ?? "CPU: \(SystemMonitorFormat.percent(state.cpuUsage))"
            let tempText = state.temperatureCelsius.map { "\(Int($0.rounded()))°C" } ?? state.thermalState.name
            return DisplaySpec(
                primary: size == .small ? SystemMonitorFormat.percent(state.cpuUsage) : cpuText,
                trailing: tempText,
                trailingColor: thermalColor(for: state),
                values: state.cpuHistory.isEmpty ? [max(0.08, state.cpuUsage)] : state.cpuHistory,
                fillColors: [Color(red: 0.96, green: 0.42, blue: 0.14).opacity(0.65), Color(red: 0.88, green: 0.68, blue: 0.18).opacity(0.42), Color(red: 0.36, green: 0.64, blue: 0.30).opacity(0.28)],
                strokeColors: [Color(red: 0.98, green: 0.52, blue: 0.16), Color(red: 0.64, green: 0.80, blue: 0.32)]
            )
        }
    }

    private func thermalColor(for state: DockTelemetryState) -> Color {
        if let temp = state.temperatureCelsius {
            if temp >= 85 { return DockWidgetStyle.bad }
            if temp >= 68 { return DockWidgetStyle.warn }
            return DockWidgetStyle.ink
        }
        switch state.thermalState {
        case .critical, .serious: return DockWidgetStyle.bad
        case .fair: return DockWidgetStyle.warn
        case .nominal: return DockWidgetStyle.ink
        }
    }
}

/// Gradient sparkline curve reused across CPU, RAM, Network, Disk, and Battery telemetry wings.
private struct ThermalSparklineCanvas: View {
    let values: [Double]
    var fillColors: [Color]
    var strokeColors: [Color]

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1, size.width > 2, size.height > 2 else { return }
            let step = size.width / CGFloat(values.count - 1)
            let points = values.enumerated().map { idx, raw in
                let v = min(max(raw, 0.04), 1.0)
                return CGPoint(
                    x: CGFloat(idx) * step,
                    y: size.height - 2 - CGFloat(v) * (size.height - 4)
                )
            }

            var strokePath = Path()
            strokePath.move(to: points[0])
            for i in 1..<points.count {
                let prev = points[i - 1]
                let curr = points[i]
                let mid = CGPoint(x: (prev.x + curr.x) / 2, y: (prev.y + curr.y) / 2)
                strokePath.addQuadCurve(to: mid, control: prev)
            }
            if let last = points.last {
                strokePath.addLine(to: last)
            }

            var fillPath = strokePath
            fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
            fillPath.addLine(to: CGPoint(x: 0, y: size.height))
            fillPath.closeSubpath()

            let gradient = Gradient(colors: fillColors)
            ctx.fill(
                fillPath,
                with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
            )
            ctx.stroke(
                strokePath,
                with: .linearGradient(
                    Gradient(colors: strokeColors),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                ),
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

private struct DockTelemetryPreviewCard: View {
    @ObservedObject private var feed = DockTelemetryFeed.shared
    var onOpenActivityMonitor: () -> Void = {}

    var body: some View {
        let state = feed.state
        DockPreviewCard {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                    metricCell(
                        Text("CPU Load"),
                        value: SystemMonitorFormat.percent(state.cpuUsage),
                        detail: state.frequencyGHz.map { String(format: "%.2f GHz", $0) }
                    )
                    metricCell(
                        Text("Thermal"),
                        value: state.temperatureCelsius.map { "\(Int($0.rounded()))°C" } ?? state.thermalState.name,
                        detail: state.temperatureCelsius != nil ? state.thermalState.name : nil
                    )
                    metricCell(
                        Text("Memory"),
                        value: SystemMonitorFormat.percent(state.memoryFraction),
                        detail: MemoryUsage(used: state.memoryUsedBytes, total: state.memoryTotalBytes).total > 0
                            ? MemoryUsage(used: state.memoryUsedBytes, total: state.memoryTotalBytes).formattedGigabytesPair
                            : nil
                    )
                    metricCell(
                        Text("Disk"),
                        value: SystemMonitorFormat.percent(state.diskUsedFraction),
                        detail: state.diskTotalBytes > 0 ? "\(SystemMonitorFormat.bytes(Double(state.diskFreeBytes))) free" : nil
                    )
                    metricCell(
                        Text("Battery"),
                        value: state.batteryFraction.map { SystemMonitorFormat.percent($0) } ?? "AC",
                        detail: state.batteryWatts.map { String(format: "%.0fW", $0) }
                    )
                    metricCell(
                        Text("GPU"),
                        value: state.gpuUsage.map { SystemMonitorFormat.percent($0) } ?? "–",
                        detail: "↓ \(DockVpnRateFormat.formatted(state.downBytesPerSec))"
                    )
                }

                Divider().opacity(0.25)

                Button(action: onOpenActivityMonitor) {
                    HStack {
                        Text("Open Activity Monitor")
                            .font(.system(size: 11.5, weight: .medium))
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { feed.retain() }
        .onDisappear { feed.release() }
    }

    private func metricCell(_ title: Text, value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            title.dockCaption()
            Text(verbatim: value)
                .font(.system(size: 16, weight: .semibold).monospacedDigit())
            if let detail {
                Text(verbatim: detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
