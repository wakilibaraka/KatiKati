import SwiftUI

// Phase 33e — Page 5: Hardware HUD & Sensory Deck (Bento Card A: Silicon & Thermal, Card B: Memory & Battery)

struct NotchHardwareHudPageView: View {
    @StateObject private var power = SystemStatusService()
    @ObservedObject private var monitor = ProductivityServices.shared.systemMonitor

    private var thermal: (label: String, color: Color) {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return ("NOMINAL", .green)
        case .fair: return ("FAIR", .yellow)
        case .serious: return ("SERIOUS", .orange)
        case .critical: return ("CRITICAL", .red)
        @unknown default: return ("UNKNOWN", .gray)
        }
    }

    var body: some View {
        HStack(spacing: NotchDesignSpec.cardSpacing) {
            // Card A: Apple Silicon CPU & GPU HUD
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 22, height: 22)
                        Image(systemName: "cpu")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Text(verbatim: "Apple Silicon")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(verbatim: thermal.label)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(thermal.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(thermal.color.opacity(0.15)))
                }

                HStack(spacing: 16) {
                    // CPU gauge
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: SystemMonitorFormat.percent(monitor.snapshot.cpu))
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Text(verbatim: "CPU Load")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    // Disk (real); there is no public GPU load API, so no GPU number is shown.
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: SystemMonitorFormat.percent(monitor.snapshot.disk.total > 0 ? 1 - Double(monitor.snapshot.disk.free) / Double(monitor.snapshot.disk.total) : 0))
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Text(verbatim: "Disk Used")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                Spacer(minLength: 0)

                // Thermal state
                HStack(spacing: 6) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 11))
                        .foregroundStyle(thermal.color)
                    Text(verbatim: "Thermal state: \(thermal.label.capitalized)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(NotchDesignSpec.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(NotchDesignSpec.cardFillOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(NotchDesignSpec.cardStrokeOpacity), lineWidth: NotchDesignSpec.cardStrokeWidth)
                    )
            )

            // Card B: Unified Memory & Battery Energy Deck
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 22, height: 22)
                        Image(systemName: "memorychip")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Text(verbatim: "Unified Memory")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    if let level = power.status.battery.level {
                        HStack(spacing: 4) {
                            Text(verbatim: "\(level)%")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                            Image(systemName: power.status.battery.isCharging ? "bolt.fill" : "battery.100")
                                .font(.system(size: 10))
                                .foregroundStyle(power.status.battery.isCharging ? .green : .white)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                }

                // RAM readout
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64(monitor.snapshot.memory.used), countStyle: .memory))
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text(verbatim: "of \(ByteCountFormatter.string(fromByteCount: Int64(monitor.snapshot.memory.total), countStyle: .memory)) (\(SystemMonitorFormat.percent(monitor.snapshot.memory.fraction)))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer(minLength: 0)

                // Memory bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12)).frame(height: 6)
                        Capsule().fill(Color.purple).frame(width: geo.size.width * CGFloat(min(1, max(0, monitor.snapshot.memory.fraction))), height: 6)
                    }
                }
                .frame(height: 6)
            }
            .padding(NotchDesignSpec.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(NotchDesignSpec.cardFillOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(NotchDesignSpec.cardStrokeOpacity), lineWidth: NotchDesignSpec.cardStrokeWidth)
                    )
            )
        }
        .onAppear { power.acquire(); monitor.acquire() }
        .onDisappear { power.release(); monitor.release() }
    }
}
