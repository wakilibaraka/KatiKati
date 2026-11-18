import AppKit
import SwiftUI

/// DeXign Studio Dock II Live System Telemetry / CPU Sparkline wing widget.
/// Powered by `DockTelemetryFeed` (`SystemMonitorController` + `PowerThermal` + opt-in IOHID sensors).
struct DockTelemetryWidgetView: View {
    @Environment(\.widgetSize) private var size
    @Environment(\.dockPopoverEdge) private var popoverEdge
    @ObservedObject private var feed = DockTelemetryFeed.shared
    @State private var showDetails = false

    var body: some View {
        let state = feed.state
        let cpuText: String = {
            if let ghz = state.frequencyGHz {
                return String(format: "CPU: %.1f GHz", ghz)
            }
            return "CPU: \(SystemMonitorFormat.percent(state.cpuUsage))"
        }()
        let tempText: String = {
            if let temp = state.temperatureCelsius {
                return "\(Int(temp.rounded()))°C"
            }
            return state.thermalState.name
        }()
        let sparkValues: [Double] = {
            if state.cpuHistory.isEmpty {
                let seed = max(0.08, state.cpuUsage)
                return [seed * 0.72, seed * 0.88, seed * 0.82, seed, seed * 0.94]
            }
            if state.cpuHistory.count == 1 {
                let single = state.cpuHistory[0]
                return [single * 0.85, single, single]
            }
            return state.cpuHistory
        }()

        ZStack(alignment: .bottom) {
            ThermalSparklineCanvas(values: sparkValues)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 18)
                .padding(.bottom, 2)

            HStack(spacing: 6) {
                Text(verbatim: size == .small ? SystemMonitorFormat.percent(state.cpuUsage) : cpuText)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(DockWidgetStyle.ink)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(verbatim: tempText)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(thermalColor(for: state))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.top, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        .accessibilityLabel(Text(verbatim: "\(cpuText) \(tempText)"))
        .accessibilityAddTraits(.isButton)
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

/// DeXign Studio warm orange → amber → olive-green gradient sparkline curve.
private struct ThermalSparklineCanvas: View {
    let values: [Double]

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

            let gradient = Gradient(colors: [
                Color(red: 0.96, green: 0.42, blue: 0.14).opacity(0.65),
                Color(red: 0.88, green: 0.68, blue: 0.18).opacity(0.42),
                Color(red: 0.36, green: 0.64, blue: 0.30).opacity(0.28)
            ])
            ctx.fill(
                fillPath,
                with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
            )
            ctx.stroke(
                strokePath,
                with: .linearGradient(
                    Gradient(colors: [Color(red: 0.98, green: 0.52, blue: 0.16), Color(red: 0.64, green: 0.80, blue: 0.32)]),
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
                        detail: nil
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
