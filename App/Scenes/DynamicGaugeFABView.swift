import SwiftUI

/// Phase 32: Circular dynamic data FAB showing RAM percentage in center
/// and CPU pressure on the surrounding progress arc.
/// Acts as the origin for the Dynamic Island, smoothly expanding to the right
/// on live events (music, timer, focus, recording, etc.) with fluid spring physics.
public struct DynamicGaugeFABView: View {
    @StateObject private var monitor = SystemMonitorController()
    @ObservedObject private var feed = LiveActivityFeed.shared
    @State private var isHovered = false
    @State private var isManuallyExpanded = false
    var onTap: (() -> Void)?

    public init(onTap: (() -> Void)? = nil) {
        self.onTap = onTap
    }

    private var hasActiveEvent: Bool {
        switch feed.activity.kind {
        case .music, .focus, .countdown, .timer, .stopwatch:
            return true
        case .clock:
            return false
        }
    }

    private var isExpanded: Bool {
        isManuallyExpanded || (isHovered && hasActiveEvent)
    }

    public var body: some View {
        let metrics = SystemGaugeMetrics.compute(
            usedMemory: monitor.snapshot.memory.used,
            totalMemory: monitor.snapshot.memory.total,
            cpuUsage: monitor.snapshot.cpu
        )

        ZStack(alignment: .leading) {
            // Container backdrop
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.11, green: 0.12, blue: 0.15).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(isHovered ? Color.white.opacity(0.28) : Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(isHovered ? 0.35 : 0.18), radius: isHovered ? 6 : 3, x: 0, y: 2)

            if isExpanded {
                expandedContent(metrics: metrics)
                    .transition(.opacity)
            } else {
                gaugeDisc(metrics: metrics)
                    .transition(.opacity)
            }
        }
        .frame(width: isExpanded ? 180 : 40, height: 40)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isExpanded)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            if hasActiveEvent {
                isManuallyExpanded.toggle()
            }
            onTap?()
        }
        .onAppear {
            monitor.acquire()
            feed.retain()
        }
        .onDisappear {
            monitor.release()
            feed.release()
        }
        .help(isExpanded ? "Live Island • Click to collapse" : "RAM: \(metrics.ramPercentage)% • CPU: \(Int(round(metrics.cpuPressure * 100)))%")
    }

    // MARK: - Compact Disc

    private func gaugeDisc(metrics: SystemGaugeMetrics) -> some View {
        ZStack {
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
    }

    // MARK: - Expanded Dynamic Island

    private func expandedContent(metrics: SystemGaugeMetrics) -> some View {
        HStack(spacing: 8) {
            // Left Mini Gauge or Event Glyph
            ZStack {
                Circle()
                    .stroke(gaugeColor(for: metrics.pressureLevel).opacity(0.25), lineWidth: 2)
                    .frame(width: 26, height: 26)

                Circle()
                    .trim(from: 0.0, to: max(0.05, CGFloat(metrics.cpuPressure)))
                    .stroke(gaugeColor(for: metrics.pressureLevel),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 26, height: 26)

                Image(systemName: LiveIslandStyle.symbolName(for: feed.activity.kind))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.leading, 8)

            // Center details
            VStack(alignment: .leading, spacing: 1) {
                Text(eventTitle)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(eventSubtitle(metrics: metrics))
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.80))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 2)

            // Right Equalizer or Waveform
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(gaugeColor(for: metrics.pressureLevel))
                    .frame(width: 2.5, height: hasActiveEvent ? 14 : 6)
                RoundedRectangle(cornerRadius: 1)
                    .fill(gaugeColor(for: metrics.pressureLevel))
                    .frame(width: 2.5, height: hasActiveEvent ? 8 : 10)
                RoundedRectangle(cornerRadius: 1)
                    .fill(gaugeColor(for: metrics.pressureLevel))
                    .frame(width: 2.5, height: hasActiveEvent ? 12 : 8)
            }
            .padding(.trailing, 10)
        }
        .frame(height: 40)
    }

    private var eventTitle: String {
        switch feed.activity.kind {
        case .music:
            return feed.nowPlayingState.title ?? LiveIslandStyle.labelString(for: .music)
        case .focus:
            return LiveIslandStyle.labelString(for: .focus)
        case .countdown:
            return LiveIslandStyle.labelString(for: .countdown)
        case .timer:
            return LiveIslandStyle.labelString(for: .timer)
        case .stopwatch:
            return LiveIslandStyle.labelString(for: .stopwatch)
        case .clock:
            return "System"
        }
    }

    private func eventSubtitle(metrics: SystemGaugeMetrics) -> String {
        if let val = LiveIslandStyle.valueString(for: feed.activity), !val.isEmpty {
            return val
        }
        return "RAM: \(metrics.ramPercentage)% • CPU: \(Int(round(metrics.cpuPressure * 100)))%"
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
