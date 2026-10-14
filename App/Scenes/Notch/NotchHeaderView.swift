import AppKit
import SwiftUI

/// Header row of the full notch skin: tabs (Home, Shelf) on the left of the hardware notch, settings
/// and battery on the right. The middle stays empty so the notch itself is never drawn over.
struct NotchHeaderView: View {
    @ObservedObject var model: NotchModel
    let metrics: NotchMetrics
    @StateObject private var power = SystemStatusService()

    var body: some View {
        let side = NotchLayoutSpec.headerButtonSize
        HStack(spacing: 0) {
            HStack(spacing: NotchLayoutSpec.headerSpacing) {
                tabButton(.home, symbol: "house.fill")
                tabButton(.tools, symbol: "square.grid.2x2.fill")
            }
            Spacer(minLength: metrics.closedSize.width)
            HStack(spacing: NotchLayoutSpec.headerSpacing) {
                volume
                if let level = power.status.battery.level {
                    HStack(spacing: 4) {
                        Text(verbatim: "\(level)%").font(.system(size: 12, weight: .medium)).monospacedDigit()
                        Image(systemName: Self.batterySymbol(level: level, charging: power.status.battery.isCharging))
                            .font(.system(size: 14))
                    }
                    .foregroundStyle(.white)
                }
                Button { model.collapse(); model.openSettings() } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 12, weight: .semibold))
                        .frame(width: side, height: side)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help(Text("KatiKati Settings"))
            }
        }
        .foregroundStyle(.white)
        .frame(height: NotchLayoutSpec.headerHeight(closedHeight: metrics.closedSize.height))
        .onAppear { power.acquire() }
        .onDisappear { power.release() }
    }

    /// Compact output-volume control: speaker glyph (tap = mute toggle is left to the system) + slider.
    private var volume: some View {
        HStack(spacing: 4) {
            Image(systemName: power.status.volume.isMuted || power.status.volume.level == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                .frame(width: 16)
            Slider(value: Binding(get: { Double(power.status.volume.level) },
                                  set: { _ = power.setVolume(Float($0)) }), in: 0...1)
                .controlSize(.mini)
                .frame(width: NotchLayoutSpec.volumeSliderWidth)
        }
        .padding(.trailing, 4)
    }

    private func tabButton(_ tab: NotchTab, symbol: String) -> some View {
        let side = NotchLayoutSpec.headerButtonSize
        let selected = model.tab == tab
        return Button { withAnimation(.easeInOut(duration: 0.2)) { model.tab = tab } } label: {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .frame(width: side, height: side)
                .background(Circle().fill(Color.white.opacity(selected ? 0.22 : 0.0)))
        }
        .buttonStyle(.plain)
        .help(tab == .home ? Text("Home") : Text("Tools"))
    }

    static func batterySymbol(level: Int, charging: Bool) -> String {
        if charging { return "battery.100.bolt" }
        switch level {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}
