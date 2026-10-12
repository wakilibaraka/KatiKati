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
            HStack(spacing: 6) {
                tabButton(.home, symbol: "house.fill")
                tabButton(.shelf, symbol: "tray.fill")
            }
            Spacer(minLength: metrics.closedSize.width)
            HStack(spacing: 8) {
                if let level = power.status.battery.level {
                    HStack(spacing: 4) {
                        Text(verbatim: "\(level)%").font(.system(size: 12, weight: .medium)).monospacedDigit()
                        Image(systemName: Self.batterySymbol(level: level, charging: power.status.battery.isCharging))
                            .font(.system(size: 14))
                    }
                    .foregroundStyle(.white)
                }
                Button { (NSApp.delegate as? AppDelegate)?.openSettings(nil) } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 12, weight: .semibold))
                        .frame(width: side, height: side)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help(Text("Settings"))
            }
        }
        .foregroundStyle(.white)
        .frame(height: NotchLayoutSpec.headerHeight(closedHeight: metrics.closedSize.height))
        .onAppear { power.acquire() }
        .onDisappear { power.release() }
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
        .help(tab == .home ? Text("Home") : Text("Shelf"))
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
