import SwiftUI

private func batteryTint(_ level: Int?, charging: Bool = false) -> Color {
    if charging { return DockWidgetStyle.good }
    guard let level else { return DockWidgetStyle.ink.opacity(DockWidgetStyle.secondaryOpacity) }
    return level <= 20 ? DockWidgetStyle.bad : level <= 40 ? DockWidgetStyle.warn : DockWidgetStyle.good
}

private func batteryText(_ level: Int?) -> String { level.map { "\($0)%" } ?? "–" }

private extension PeripheralWidgetLayoutStyle {
    var shortTitle: LocalizedStringKey {
        switch self {
        case .status: return "Status"
        case .ring: return "Ring"
        case .iconOnly: return "Icons"
        }
    }
}

/// P1 + P2: Dock bar peripherals widget with `Status`, `Ring` (`DockRing`), and `Icon only` modes,
/// green charging bolt badge, and `+N` overflow chip.
struct DevicesDockChip: View {
    @Environment(\.widgetSize) private var size
    @ObservedObject private var feed = DockDevicesFeed.shared
    @AppStorage(PeripheralWidgetPrefs.layoutKey) private var layoutRaw = PeripheralWidgetLayoutStyle.status.rawValue
    @AppStorage(PeripheralWidgetPrefs.orderKey) private var orderRaw = "[]"
    @AppStorage(PeripheralWidgetPrefs.hiddenKey) private var hiddenRaw = "[]"
    @AppStorage(PeripheralWidgetPrefs.pinnedKey) private var pinnedID = ""

    var body: some View {
        let style = PeripheralWidgetPrefs.style(from: layoutRaw)
        let width = BarSection.devices.widgetWidth(for: size)
        let planned = PeripheralWidgetPrefs.slice(
            devices: feed.devices,
            availableWidth: width,
            style: style,
            order: PeripheralWidgetPrefs.decodeIDs(orderRaw),
            hiddenIDs: Set(PeripheralWidgetPrefs.decodeIDs(hiddenRaw)),
            pinnedID: pinnedID
        )
        let shown = planned.visible

        HStack(spacing: style == .ring ? 7 : 8) {
            if shown.isEmpty {
                Image(systemName: "headphones").font(.system(size: 17)).opacity(DockWidgetStyle.secondaryOpacity)
                if size != .small { Text("No devices").dockCaption() }
            } else {
                ForEach(shown) { device in
                    itemView(device, style: style)
                }
                if planned.overflowCount > 0 {
                    Text(verbatim: "+\(planned.overflowCount)")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(DockWidgetStyle.ink.opacity(0.82))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
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

    @ViewBuilder
    private func itemView(_ device: BluetoothDevice, style: PeripheralWidgetLayoutStyle) -> some View {
        let tint = batteryTint(device.lowestBattery, charging: device.isCharging)
        switch style {
        case .status:
            let density = WidgetDensityPolicy.resolve(dockHeight: 58, widgetSize: size)
            HStack(spacing: 5) {
                deviceGlyph(device, size: 15)
                VStack(alignment: .leading, spacing: 0) {
                    if density.showsDeviceName {
                        Text(verbatim: device.name)
                            .dockCaption()
                            .lineLimit(1)
                            .frame(maxWidth: 72, alignment: .leading)
                    }
                    HStack(spacing: 2) {
                        if device.isCharging {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(DockWidgetStyle.good)
                        }
                        Text(verbatim: batteryText(device.lowestBattery))
                            .font(.system(size: 13, weight: .medium)).monospacedDigit()
                            .foregroundStyle(tint)
                    }
                }
            }
        case .ring:
            ZStack(alignment: .topTrailing) {
                DockRing(
                    fraction: Double(device.lowestBattery ?? 0) / 100.0,
                    tint: tint,
                    lineWidth: 2.6
                ) {
                    Image(systemName: device.richSymbolName)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(DockWidgetStyle.ink)
                }
                .frame(width: 26, height: 26)
                if device.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(DockWidgetStyle.good)
                        .offset(x: 2, y: -2)
                }
            }
        case .iconOnly:
            deviceGlyph(device, size: 15, tint: tint)
        }
    }

    private func deviceGlyph(_ device: BluetoothDevice, size: CGFloat, tint: Color = DockWidgetStyle.ink) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: device.richSymbolName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(tint)
            if device.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DockWidgetStyle.good)
                    .offset(x: 4, y: -3)
            }
        }
    }
}

/// Side-rail tile: the lowest-battery (or pinned) device's glyph over its level.
struct RailDevicesTile: View {
    @ObservedObject private var feed = DockDevicesFeed.shared
    @AppStorage(PeripheralWidgetPrefs.pinnedKey) private var pinnedID = ""
    @AppStorage(PeripheralWidgetPrefs.hiddenKey) private var hiddenRaw = "[]"

    var body: some View {
        let visible = PeripheralWidgetPrefs.arranged(
            devices: feed.devices,
            hiddenIDs: Set(PeripheralWidgetPrefs.decodeIDs(hiddenRaw)),
            pinnedID: pinnedID
        )
        let device = visible.first(where: { !pinnedID.isEmpty && $0.id.caseInsensitiveCompare(pinnedID) == .orderedSame })
            ?? visible.min { ($0.lowestBattery ?? 101) < ($1.lowestBattery ?? 101) }
        VStack(spacing: 1) {
            Image(systemName: device?.richSymbolName ?? "headphones").font(.system(size: 14))
                .opacity(device == nil ? DockWidgetStyle.secondaryOpacity : 1)
            if let device {
                Text(verbatim: batteryText(device.lowestBattery)).font(.system(size: 11, weight: .medium)).monospacedDigit()
                    .foregroundStyle(batteryTint(device.lowestBattery, charging: device.isCharging))
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
    @AppStorage(PeripheralWidgetPrefs.layoutKey) private var layoutRaw = PeripheralWidgetLayoutStyle.status.rawValue
    @AppStorage(PeripheralWidgetPrefs.orderKey) private var orderRaw = "[]"
    @AppStorage(PeripheralWidgetPrefs.hiddenKey) private var hiddenRaw = "[]"
    @AppStorage(PeripheralWidgetPrefs.pinnedKey) private var pinnedID = ""
    @State private var customizing = false

    var body: some View {
        let order = PeripheralWidgetPrefs.decodeIDs(orderRaw)
        let hiddenSet = Set(PeripheralWidgetPrefs.decodeIDs(hiddenRaw).map { $0.lowercased() })
        let rows = PeripheralWidgetPrefs.arranged(
            devices: feed.devices,
            order: order,
            hiddenIDs: hiddenSet,
            pinnedID: pinnedID,
            includeHidden: customizing
        )

        DockPreviewCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Devices").font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 8)
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) { customizing.toggle() }
                    } label: {
                        Image(systemName: customizing ? "checkmark.circle.fill" : "slider.horizontal.3")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(customizing ? Color.accentColor : DockWidgetStyle.ink.opacity(0.7))
                    }
                    .buttonStyle(.borderless)
                    .help(Text("Customize"))
                }

                if customizing {
                    Picker(selection: $layoutRaw) {
                        ForEach(PeripheralWidgetLayoutStyle.allCases) { mode in
                            Text(mode.shortTitle).tag(mode.rawValue)
                        }
                    } label: {
                        // No new user-facing string: the row is already labelled by the section
                        // header above it, and `.labelsHidden()` keeps the picker as it was.
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                if rows.isEmpty {
                    Text("No devices").dockCaption()
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, device in
                        let isHidden = hiddenSet.contains(device.id.lowercased())
                        let isPinned = !pinnedID.isEmpty && pinnedID.caseInsensitiveCompare(device.id) == .orderedSame
                        HStack(spacing: 8) {
                            Image(systemName: device.richSymbolName).font(.system(size: 15)).frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: device.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                if let breakdown = device.batteryBreakdown { Text(verbatim: breakdown).dockCaption() }
                            }
                            .opacity(isHidden ? 0.45 : 1)
                            Spacer(minLength: 6)
                            if device.isCharging {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(DockWidgetStyle.good)
                            }
                            Text(verbatim: batteryText(device.lowestBattery))
                                .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(batteryTint(device.lowestBattery, charging: device.isCharging))
                                .opacity(isHidden ? 0.45 : 1)

                            if customizing {
                                Button {
                                    pinnedID = isPinned ? "" : device.id
                                } label: {
                                    Image(systemName: isPinned ? "star.fill" : "star")
                                        .font(.system(size: 11))
                                        .foregroundStyle(isPinned ? Color.yellow : DockWidgetStyle.ink.opacity(0.55))
                                }
                                .buttonStyle(.borderless)
                                Button {
                                    hiddenRaw = PeripheralWidgetPrefs.togglingHidden(id: device.id, in: hiddenRaw)
                                } label: {
                                    Image(systemName: isHidden ? "eye.slash" : "eye")
                                        .font(.system(size: 11))
                                        .foregroundStyle(DockWidgetStyle.ink.opacity(0.65))
                                }
                                .buttonStyle(.borderless)
                                Button {
                                    orderRaw = PeripheralWidgetPrefs.moving(id: device.id, by: -1, devices: rows, orderRaw: orderRaw, pinnedID: pinnedID)
                                } label: {
                                    Image(systemName: "chevron.up").font(.system(size: 10, weight: .semibold))
                                }
                                .buttonStyle(.borderless)
                                .disabled(index == 0)
                                Button {
                                    orderRaw = PeripheralWidgetPrefs.moving(id: device.id, by: 1, devices: rows, orderRaw: orderRaw, pinnedID: pinnedID)
                                } label: {
                                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                                }
                                .buttonStyle(.borderless)
                                .disabled(index == rows.count - 1)
                            }
                        }
                    }
                }
            }
            .frame(minWidth: customizing ? 280 : 220, alignment: .leading)
        }
        .onAppear { feed.retain() }
        .onDisappear { feed.release() }
    }
}
