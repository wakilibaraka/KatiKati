import SwiftUI

private func loadTint(for fraction: Double) -> Color {
    fraction > 0.9 ? DockWidgetStyle.bad : fraction > 0.7 ? DockWidgetStyle.warn : DockWidgetStyle.ink
}

/// Bar widget: CPU ring and RAM / SSD readouts. S = CPU ring, M = + RAM and SSD, L = + the 30 s CPU line.
struct SystemDockChip: View {
    @Environment(\.widgetSize) private var size
    @Environment(\.dockHeight) private var dockHeight
    @ObservedObject private var feed = DockSystemFeed.shared

    var body: some View {
        let snap = feed.snapshot
        let density = WidgetDensityPolicy.resolve(dockHeight: dockHeight, widgetSize: size)
        HStack(spacing: 8) {
            DockRing(fraction: snap.cpu, tint: loadTint(for: snap.cpu)) {
                Text(verbatim: "\(Int((snap.cpu * 100).rounded()))").font(.system(size: 11, weight: .semibold)).monospacedDigit()
            }
            .frame(width: 32, height: 32)
            if density.showsSecondaryCaption {
                VStack(alignment: .leading, spacing: 1) {
                    Text("CPU").font(.system(size: 13, weight: .medium))
                    Text(verbatim: "RAM \(SystemMonitorFormat.percent(snap.memory.fraction))").dockCaption()
                    Text(verbatim: "SSD \(SystemMonitorFormat.percent(snap.disk.usedFraction))").dockCaption()
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            if density.showsSparkline {
                DockSparkline(values: feed.cpu.normalized(ceiling: 1)).frame(maxWidth: .infinity, maxHeight: 28)
            }
        }
        .frame(maxHeight: .infinity)
        .dockWidgetChip()
        .dockHoverPreview { SystemPreviewCard() }
        .onTapGesture { SystemDockActions.openActivityMonitor() }
        .onAppear { feed.retain() }
        .onDisappear { feed.release() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "CPU \(SystemMonitorFormat.percent(snap.cpu))"))
        .accessibilityAddTraits(.isButton)
    }
}

/// Side-rail tile: the CPU ring.
struct RailSystemTile: View {
    @ObservedObject private var feed = DockSystemFeed.shared

    var body: some View {
        let cpu = feed.snapshot.cpu
        DockRing(fraction: cpu, tint: loadTint(for: cpu), lineWidth: 3) {
            Text(verbatim: "\(Int((cpu * 100).rounded()))").font(.system(size: 11, weight: .semibold)).monospacedDigit()
        }
        .frame(width: 28, height: 28)
        .dockWidgetRailTile()
        .dockHoverPreview { SystemPreviewCard() }
        .onTapGesture { SystemDockActions.openActivityMonitor() }
        .onAppear { feed.retain() }
        .onDisappear { feed.release() }
        .accessibilityLabel(Text(verbatim: "CPU \(SystemMonitorFormat.percent(cpu))"))
        .accessibilityAddTraits(.isButton)
    }
}

enum SystemDockActions {
    static func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }
}

/// Hover preview: CPU, RAM, SSD read and SSD write as 2 × 2 sparklines over the last 30 seconds.
struct SystemPreviewCard: View {
    var body: some View {
        SystemPreviewTabsView()
    }
}
