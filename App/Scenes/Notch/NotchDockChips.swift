import SwiftUI

/// The closed notch when nothing is live: free storage on the left of the hardware notch, battery on the
/// right. Any live activity takes the two slots over, so the chips never compete with it.
struct NotchDockChips: View {
    let metrics: NotchMetrics
    @StateObject private var power = SystemStatusService()
    @State private var free: Int64 = 0
    @AppStorage(NotchRestContent.defaultsKey) private var rest = NotchRestContent.dockChips.rawValue

    var body: some View {
        let pair = NotchRestContent(rawValue: rest) ?? .dockChips
        HStack(spacing: 0) {
            if let left = pair.left {
                Group {
                    if left == .time {
                        TimelineView(.everyMinute) { ctx in
                            Text(verbatim: ctx.date.formatted(date: .omitted, time: .shortened))
                        }
                    } else {
                        HStack(spacing: 3) {
                            Image(systemName: "internaldrive.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(.cyan)
                            Text(verbatim: StorageScanMath.compact(free))
                        }
                    }
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: NotchGeometry.sneakSide - 14, alignment: .leading)
                .accessibilityElement(children: .combine)
            } else {
                Color.clear.frame(width: 0)
            }
            Spacer(minLength: metrics.closedSize.width - 8)
            if pair.right == .battery, let level = power.status.battery.level {
                NotchBatteryChip(level: level, battery: power.status.battery)
                    .frame(width: NotchGeometry.sneakSide - 14, alignment: .trailing)
            }
        }
        .frame(maxHeight: metrics.closedSize.height)
        // lifecycle on a real view: modifiers on an empty Group never fire
        .background(Color.clear.onAppear { power.acquire() }.onDisappear { power.release() })
        .task {
            while !Task.isCancelled {
                free = StorageScanService.freeBytes()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}

/// Percentage + a drawn battery (the SF glyphs are too wide for the 50pt slot at "100%"). Colour and bolt
/// animate on plug / unplug; the fill breathes while charging.
struct NotchBatteryChip: View {
    let level: Int
    let battery: BatteryStatus
    var scale: CGFloat = 1
    @State private var pulse = false
    @AppStorage(NotchBehavior.lowBatteryTintKey) private var tintsLow = true
    // 59b: the Notifications page owns the low level; this reads the same value.
    @ObservedObject private var alerts = PowerNotificationCenter.shared

    private var tint: Color {
        if battery.isCharging || (battery.isPluggedIn && level >= 100) { return .green }
        let threshold = alerts.rules.lowThreshold ?? NotchBehavior.defaultLowBatteryThreshold
        return tintsLow && level <= min(NotchBehavior.lowBatteryRange.upperBound, max(NotchBehavior.lowBatteryRange.lowerBound, threshold)) ? .red : .white
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(verbatim: "\(level)%")
                .font(.system(size: 10 * scale, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1).fixedSize()
                .contentTransition(.numericText(value: Double(level)))
            ZStack {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(.white.opacity(0.55), lineWidth: 1)
                    .frame(width: 16 * scale, height: 8 * scale)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(tint)
                            .frame(width: max(2, 12 * scale * CGFloat(level) / 100), height: 4.5 * scale)
                            .padding(.leading, 2)
                            .opacity(battery.isCharging && pulse ? 0.55 : 1)
                    }
                    .overlay(alignment: .trailing) {
                        RoundedRectangle(cornerRadius: 0.5).fill(.white.opacity(0.55))
                            .frame(width: 1.5 * scale, height: 3.5 * scale).offset(x: 2.5 * scale)
                    }
                if battery.isPluggedIn {
                    Image(systemName: "bolt.fill").font(.system(size: 6 * scale, weight: .heavy))
                        .foregroundStyle(.black.opacity(0.75))
                        .shadow(color: .white.opacity(0.9), radius: 0.5)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                }
            }
            .padding(.trailing, 2)
        }
        .animation(.spring(response: 0.4, dampingFraction: 1.0), value: battery.isPluggedIn)
        .animation(.easeInOut(duration: 0.4), value: tint)
        .animation(.easeInOut(duration: 0.4), value: level)
        .onAppear { updatePulse() }
        .onChange(of: battery.isCharging) { _, _ in updatePulse() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Battery \(level)%\(battery.isCharging ? ", charging" : battery.isPluggedIn ? ", plugged in" : "")"))
        // 59d: the chip is too small for time and watts, so hovering it reads them out.
        .help(Text(verbatim: battery.facts.summary ?? ""))
    }

    private func updatePulse() {
        if battery.isCharging {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { pulse = true }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { pulse = false }
        }
    }
}

/// The right-ear battery while music is the live activity (the ears never go empty of it).
struct NotchLiveBattery: View {
    @StateObject private var power = SystemStatusService()

    var body: some View {
        Group {
            if let level = power.status.battery.level { NotchBatteryChip(level: level, battery: power.status.battery) }
        }
        .onAppear { power.acquire() }
        .onDisappear { power.release() }
    }
}
