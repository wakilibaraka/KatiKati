import SwiftUI

private extension BluetoothDevice {
    var glyph: String {
        let text = "\(name) \(kind ?? "")".lowercased()
        if text.contains("airpods") { return "airpods" }
        if text.contains("head") || text.contains("buds") { return "headphones" }
        if text.contains("mouse") || text.contains("trackpad") { return "computermouse.fill" }
        if text.contains("keyboard") { return "keyboard.fill" }
        return "dot.radiowaves.left.and.right"
    }
}

private func batteryTint(_ level: Int?) -> Color {
    guard let level else { return DockWidgetStyle.ink.opacity(DockWidgetStyle.secondaryOpacity) }
    return level <= 20 ? DockWidgetStyle.bad : level <= 40 ? DockWidgetStyle.warn : DockWidgetStyle.good
}

private func batteryText(_ level: Int?) -> String { level.map { "\($0)%" } ?? "–" }

/// Bar widget: battery levels of connected AirPods, mouse, keyboard. S = the lowest device, M = up to three,
/// L = three with names.
struct DevicesDockChip: View {
    @Environment(\.widgetSize) private var size
    @ObservedObject private var feed = DockDevicesFeed.shared

    var body: some View {
        let shown = Array(feed.devices.sorted { ($0.lowestBattery != nil) && ($1.lowestBattery == nil) }.prefix(size == .small ? 1 : 3))
        HStack(spacing: 10) {
            if shown.isEmpty {
                Image(systemName: "headphones").font(.system(size: 17)).opacity(DockWidgetStyle.secondaryOpacity)
                if size != .small { Text("No devices").dockCaption() }
            } else {
                ForEach(shown) { device in
                    HStack(spacing: 5) {
                        Image(systemName: device.glyph).font(.system(size: 15))
                        VStack(alignment: .leading, spacing: 0) {
                            if size == .large { Text(verbatim: device.name).dockCaption() }
                            Text(verbatim: batteryText(device.lowestBattery))
                                .font(.system(size: 13, weight: .medium)).monospacedDigit()
                                .foregroundStyle(batteryTint(device.lowestBattery))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dockWidgetChip()
        .dockHoverPreview { DevicesPreviewCard() }
        .onAppear { feed.retain() }
        .onDisappear { feed.release() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: shown.map { "\($0.name) \(batteryText($0.lowestBattery))" }.joined(separator: ", ")))
    }
}

/// Side-rail tile: the lowest-battery device's glyph over its level.
struct RailDevicesTile: View {
    @ObservedObject private var feed = DockDevicesFeed.shared

    var body: some View {
        let device = feed.devices.min { ($0.lowestBattery ?? 101) < ($1.lowestBattery ?? 101) }
        VStack(spacing: 1) {
            Image(systemName: device?.glyph ?? "headphones").font(.system(size: 14))
                .opacity(device == nil ? DockWidgetStyle.secondaryOpacity : 1)
            if let device {
                Text(verbatim: batteryText(device.lowestBattery)).font(.system(size: 11, weight: .medium)).monospacedDigit()
                    .foregroundStyle(batteryTint(device.lowestBattery))
            }
        }
        .dockWidgetRailTile()
        .dockHoverPreview { DevicesPreviewCard() }
        .onAppear { feed.retain() }
        .onDisappear { feed.release() }
        .accessibilityLabel(Text("Devices"))
    }
}

/// Hover preview: every connected device with its battery (earbud / case breakdown when it reports one).
struct DevicesPreviewCard: View {
    @ObservedObject private var feed = DockDevicesFeed.shared

    var body: some View {
        DockPreviewCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Devices").font(.system(size: 13, weight: .semibold))
                if feed.devices.isEmpty {
                    Text("No devices").dockCaption()
                } else {
                    ForEach(feed.devices) { device in
                        HStack(spacing: 10) {
                            Image(systemName: device.glyph).font(.system(size: 16)).frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: device.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                if let breakdown = device.batteryBreakdown { Text(verbatim: breakdown).dockCaption() }
                            }
                            Spacer(minLength: 6)
                            Text(verbatim: batteryText(device.lowestBattery)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(batteryTint(device.lowestBattery))
                        }
                    }
                }
            }
        }
        .onAppear { feed.retain() }
        .onDisappear { feed.release() }
    }
}
