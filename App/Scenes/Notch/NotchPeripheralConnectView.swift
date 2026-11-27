import SwiftUI

/// Visual mode for the AirPods / Bluetooth peripheral notch card (N1 + N2).
enum PeripheralBadgeState: Equatable, Sendable {
    case connected
    case disconnected
    case low

    init(event: PeripheralEvent) {
        switch event {
        case .connected: self = .connected
        case .disconnected: self = .disconnected
        case .low: self = .low
        }
    }

    var accent: Color {
        switch self {
        case .connected: return IslandTheme.Accent.green
        case .disconnected: return IslandTheme.Ink.secondary
        case .low: return IslandTheme.Accent.red
        }
    }
}

/// Notchy-style circular device glyph with an animated drawing ring and status badge.
struct NotchPeripheralConnectBadge: View {
    let device: BluetoothDevice
    let state: PeripheralBadgeState
    var size: CGFloat = 44

    @State private var ringProgress: Double = 0
    @State private var badgeShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var targetProgress: Double {
        switch state {
        case .connected: return 1.0
        case .disconnected: return 0.35
        case .low: return Double(device.lowestBattery ?? 15) / 100.0
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            IslandProgressRing(
                value: reduceMotion ? targetProgress : ringProgress,
                color: state.accent,
                track: state.accent.opacity(0.22),
                size: size,
                thickness: 3.2
            ) {
                Image(systemName: device.richSymbolName)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(state == .disconnected ? IslandTheme.Ink.secondary : .white)
            }

            if badgeShown || reduceMotion {
                Image(systemName: state == .connected ? "checkmark.circle.fill" : (state == .low ? "exclamationmark.circle.fill" : "minus.circle.fill"))
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(state.accent)
                    .background(Circle().fill(Color.black).padding(1))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onAppear {
            if reduceMotion {
                ringProgress = targetProgress
                badgeShown = true
            } else {
                withAnimation(.spring(response: 0.46, dampingFraction: 0.82)) {
                    ringProgress = targetProgress
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                        badgeShown = true
                    }
                }
            }
        }
    }
}

/// Non-island skins (`boring` / `classic` / `liquid`) drop-out pill for N1 + N2 peripheral events.
struct NotchPeripheralPillView: View {
    @ObservedObject var model: NotchTrackPillModel
    let event: PeripheralEvent

    private var device: BluetoothDevice {
        switch event {
        case let .connected(d), let .disconnected(d), let .low(d): return d
        }
    }

    private var badgeState: PeripheralBadgeState { PeripheralBadgeState(event: event) }

    private var subtitle: String {
        switch event {
        case .connected(let d):
            if let breakdown = d.batteryBreakdown { return breakdown }
            if let level = d.lowestBattery { return "\(level)%" }
            return String(localized: "Connected")
        case .disconnected:
            return String(localized: "Disconnected")
        case .low(let d):
            let pct = d.lowestBattery.map { "\($0)%" } ?? ""
            return pct.isEmpty ? String(localized: "Low Battery") : "\(String(localized: "Low Battery")) · \(pct)"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            NotchPeripheralConnectBadge(device: device, state: badgeState, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: device.name)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: 165, alignment: .leading)
                Text(verbatim: subtitle)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(badgeState == .low ? IslandTheme.Accent.red : .white.opacity(0.68))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.black))
        .overlay(Capsule().stroke(badgeState.accent.opacity(0.45), lineWidth: 1))
        .shadow(color: badgeState.accent.opacity(0.25), radius: 10)
        .padding(14)
        .scaleEffect(model.shown ? 1 : 0.6, anchor: .top)
        .offset(y: model.shown ? 0 : -16)
        .opacity(model.shown ? 1 : 0)
        .contentShape(Capsule())
        .onTapGesture { model.dismiss() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(device.name), \(subtitle)"))
    }
}
