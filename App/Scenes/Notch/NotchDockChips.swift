import SwiftUI

/// The closed notch when nothing is live: free storage on the left of the hardware notch, battery on the
/// right. Any live activity takes the two slots over, so the chips never compete with it.
struct NotchDockChips: View {
    let metrics: NotchMetrics
    @StateObject private var power = SystemStatusService()
    @State private var free: Int64 = 0

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 3) {
                Image(systemName: "internaldrive.fill").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.cyan)
                Text(verbatim: StorageScanMath.compact(free))
                    .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(width: NotchGeometry.sneakSide - 14, alignment: .leading)
            .accessibilityElement(children: .combine)
            Spacer(minLength: metrics.closedSize.width - 8)
            if let level = power.status.battery.level {
                HStack(spacing: 3) {
                    Text(verbatim: "\(level)%")
                        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                    Image(systemName: NotchHeaderView.batterySymbol(level: level, charging: power.status.battery.isCharging))
                        .font(.system(size: 11)).foregroundStyle(level < 20 && !power.status.battery.isCharging ? .red : .white)
                }
                .frame(width: NotchGeometry.sneakSide - 14, alignment: .trailing)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxHeight: metrics.closedSize.height)
        .onAppear { power.acquire() }
        .onDisappear { power.release() }
        .task {
            while !Task.isCancelled {
                free = StorageScanService.freeBytes()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}
