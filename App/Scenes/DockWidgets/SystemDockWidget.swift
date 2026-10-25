import SwiftUI

private func loadTint(for fraction: Double) -> Color {
    fraction > 0.9 ? DockWidgetStyle.bad : fraction > 0.7 ? DockWidgetStyle.warn : DockWidgetStyle.ink
}

/// Bar widget: CPU ring and RAM / SSD readouts. S = CPU ring, M = + RAM and SSD, L = + the 30 s CPU line.
struct SystemDockChip: View {
    @Environment(\.widgetSize) private var size
    @ObservedObject private var feed = DockSystemFeed.shared

    var body: some View {
        let snap = feed.snapshot
        HStack(spacing: 8) {
            DockRing(fraction: snap.cpu, tint: loadTint(for: snap.cpu)) {
                Text(verbatim: "\(Int((snap.cpu * 100).rounded()))").font(.system(size: 11, weight: .semibold)).monospacedDigit()
            }
            .frame(width: 32, height: 32)
            if size != .small {
                VStack(alignment: .leading, spacing: 1) {
                    Text("CPU").font(.system(size: 13, weight: .medium))
                    Text(verbatim: "RAM \(SystemMonitorFormat.percent(snap.memory.fraction))").dockCaption()
                    Text(verbatim: "SSD \(SystemMonitorFormat.percent(snap.disk.usedFraction))").dockCaption()
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            if size == .large {
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
    @ObservedObject private var feed = DockSystemFeed.shared

    var body: some View {
        let snap = feed.snapshot
        DockPreviewCard {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                cell(Text("CPU"), value: SystemMonitorFormat.percent(snap.cpu),
                     history: feed.cpu.normalized(ceiling: 1), tint: loadTint(for: snap.cpu))
                cell(Text("RAM"), value: SystemMonitorFormat.percent(snap.memory.fraction),
                     history: feed.memory.normalized(ceiling: 1), tint: loadTint(for: snap.memory.fraction))
                cell(Text("SSD Read"), value: "\(SystemMonitorFormat.bytes(snap.diskRead))/s",
                     history: feed.diskRead.normalized(ceiling: feed.diskRead.values.max() ?? 1), tint: .cyan)
                cell(Text("SSD Write"), value: "\(SystemMonitorFormat.bytes(snap.diskWrite))/s",
                     history: feed.diskWrite.normalized(ceiling: feed.diskWrite.values.max() ?? 1), tint: .orange)
            }
        }
        .onAppear { feed.retain() }
        .onDisappear { feed.release() }
    }

    private func cell(_ title: Text, value: String, history: [Double], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            title.dockCaption()
            Text(verbatim: value).font(.system(size: 17, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            DockSparkline(values: history, tint: tint).frame(height: 34)
        }
    }
}
