import SwiftUI

/// Quick Settings FAB button displaying a central Wi-Fi icon
/// surrounded by a circular ring of 12 discrete dots indicating macOS system volume level (0-100%).
/// Preserves fluid spring animations, tactile feel, and exact 40x40 squircle sizing.
public struct WiFiVolumeFABView: View {
    @StateObject private var status = SystemStatusService()
    @State private var isHovered = false
    var onTap: (() -> Void)?

    public init(onTap: (() -> Void)? = nil) {
        self.onTap = onTap
    }

    public var body: some View {
        let volume = status.status.volume
        let volumeLevel = volume.isMuted ? 0.0 : Double(volume.level)
        let activeDots = volume.isMuted ? 0 : Int(round(volumeLevel * 12.0))

        ZStack {
            // Container backdrop matching DynamicGaugeFABView
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.11, green: 0.12, blue: 0.16).opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isHovered ? Color.white.opacity(0.28) : Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(isHovered ? 0.32 : 0.16), radius: isHovered ? 6 : 3, x: 0, y: 2)

            // Circular ring of 12 discrete volume dots
            volumeDotsRing(activeCount: activeDots, isMuted: volume.isMuted)

            // Central Wi-Fi symbol
            Image(systemName: "wifi")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(isHovered ? 1.0 : 0.92))
        }
        .frame(width: 40, height: 40)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isHovered)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onTap?()
        }
        .onAppear {
            status.acquire()
        }
        .onDisappear {
            status.release()
        }
        .help(Text(verbatim: volume.isMuted ? "Quick Settings • Muted" : "Quick Settings • Volume: \(volume.percent)%"))
    }

    // MARK: - 12 Volume Dots Ring

    private func volumeDotsRing(activeCount: Int, isMuted: Bool) -> some View {
        let radius: Double = 14.0
        return ZStack {
            ForEach(0..<12, id: \.self) { index in
                let angle = -90.0 + Double(index) * 30.0
                let rad = angle * .pi / 180.0
                let x = radius * cos(rad)
                let y = radius * sin(rad)
                let isActive = !isMuted && index < activeCount

                Circle()
                    .fill(isActive ? Color.white.opacity(0.95) : Color.white.opacity(isMuted ? 0.08 : 0.18))
                    .frame(width: 2.4, height: 2.4)
                    .offset(x: CGFloat(x), y: CGFloat(y))
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isActive)
            }
        }
        .frame(width: 40, height: 40)
    }
}
