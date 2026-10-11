import SwiftUI

/// The Pinboard FAB glyph (Phase 7B-V1): Wi-Fi arcs inside a ring that fills with the battery level. The ring turns
/// amber under 20 % and red under 10 %, pulses softly while charging, and shows a slashed Wi-Fi when offline.
struct WifiBatteryRingIcon: View {
    let battery: BatteryStatus
    let wifi: WiFiStatus
    let size: CGFloat
    @State private var pulse = false

    private var fraction: Double { Double(battery.level ?? 100) / 100 }
    private var ringColor: Color {
        guard let level = battery.level else { return Color(red: 0.35, green: 0.85, blue: 0.95) }
        if battery.isCharging { return Color(red: 0.30, green: 0.85, blue: 0.45) }
        return level < 10 ? .red : (level < 20 ? .orange : Color(red: 0.35, green: 0.85, blue: 0.95))
    }

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(red: 0.42, green: 0.36, blue: 0.98), Color(red: 0.20, green: 0.72, blue: 0.96)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().stroke(Color.white.opacity(0.22), lineWidth: size * 0.09)
                .padding(size * 0.06)
            Circle().trim(from: 0, to: fraction)
                .stroke(ringColor, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(size * 0.06)
                .opacity(battery.isCharging && pulse ? 0.55 : 1)
            wifiMark
        }
        .frame(width: size, height: size)
        .onAppear {
            guard battery.isCharging else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var wifiMark: some View {
        if #available(macOS 13.0, *) {
            Image(systemName: wifi.symbolName, variableValue: wifi.symbolVariableValue)
                .font(.system(size: size * 0.40, weight: .bold)).foregroundColor(.white)
        } else {
            Image(systemName: wifi.symbolName).font(.system(size: size * 0.40, weight: .bold))
                .foregroundColor(.white.opacity(wifi.isConnected ? 1 : 0.6))
        }
    }
}

/// Binds the icon to live status. A private service instance, ref-counted to the view's lifetime.
struct PinboardFABGlyph: View {
    @StateObject private var service = SystemStatusService()
    let size: CGFloat

    var body: some View {
        WifiBatteryRingIcon(battery: service.status.battery, wifi: service.status.wifi, size: size)
            .onAppear { service.acquire() }
            .onDisappear { service.release() }
    }
}
