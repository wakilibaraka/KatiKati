import SwiftUI

/// Dock widget: every mounted drive's free space at a glance. S = the boot drive's free space,
/// M/L = the same plus how many volumes are mounted. The hover card is the DiskView panel: one row
/// per volume with its capacity pair and bar.
struct DrivesDockChip: View {
    @Environment(\.widgetSize) private var size
    @ObservedObject private var feed = DockDrivesFeed.shared

    var body: some View {
        let boot = feed.volumes.first
        HStack(spacing: 7) {
            Image(systemName: "internaldrive")
                .font(.system(size: 15, weight: .medium))
                .opacity(DockWidgetStyle.secondaryOpacity)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: boot.map { SystemMonitorFormat.bytes(Double($0.freeBytes)) } ?? "–")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                // The caption is a number, not a word: no new localized plural for a chip.
                if size != .small, let boot {
                    Text(verbatim: "\(SystemMonitorFormat.percent(boot.usedFraction)) used")
                        .dockCaption()
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxHeight: .infinity)
        .dockWidgetChip()
        .dockHoverPreview { DrivesPreviewCard() }
        .onAppear { feed.retain() }
        .onDisappear { feed.release() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: boot?.capacityText ?? "–"))
        .accessibilityAddTraits(.isButton)
    }
}

/// Side-rail tile: the boot drive's used ring around a drive glyph.
struct RailDrivesTile: View {
    @ObservedObject private var feed = DockDrivesFeed.shared

    var body: some View {
        let boot = feed.volumes.first
        DockRing(fraction: boot?.usedFraction ?? 0, tint: DrivesStyle.tint(for: boot?.usedFraction ?? 0), lineWidth: 3) {
            Image(systemName: "internaldrive")
                .font(.system(size: 11, weight: .semibold))
        }
        .frame(width: 28, height: 28)
        .dockWidgetRailTile()
        .dockHoverPreview { DrivesPreviewCard() }
        .onAppear { feed.retain() }
        .onDisappear { feed.release() }
        .accessibilityLabel(Text(verbatim: boot?.capacityText ?? "–"))
    }
}

/// The DiskView panel: a bar per volume, blue until the volume is nearly full and red after.
struct DrivesPreviewCard: View {
    @ObservedObject private var feed = DockDrivesFeed.shared

    var body: some View {
        DockPreviewCard {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(feed.volumes) { volume in
                    volumeRow(volume)
                }
            }
            .onAppear { feed.retain() }
            .onDisappear { feed.release() }
        }
    }

    private func volumeRow(_ volume: DriveVolume) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: volume.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(verbatim: volume.capacityText)
                    .dockCaption()
                if volume.isRemovable {
                    Button {
                        DrivesActions.eject(volume)
                    } label: {
                        Image(systemName: "eject")
                            .font(.system(size: 10, weight: .semibold))
                            .opacity(DockWidgetStyle.secondaryOpacity)
                    }
                    .buttonStyle(.borderless)
                    .help(Text("Eject"))
                }
            }
            CapacityBar(fraction: volume.usedFraction)
        }
        .contentShape(Rectangle())
        .onTapGesture { DrivesActions.open(volume) }
    }
}

/// DiskView's capacity bar: 6 pt, inset in the row, blue until 90 % then red.
struct CapacityBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                Capsule()
                    .fill(DrivesStyle.tint(for: fraction))
                    .frame(width: max(2, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 6)
    }
}

enum DrivesStyle {
    static let bar = Color(red: 0.25, green: 0.55, blue: 1.0)

    static func tint(for fraction: Double) -> Color {
        fraction > 0.9 ? DockWidgetStyle.bad : fraction > 0.75 ? DockWidgetStyle.warn : bar
    }
}

enum DrivesActions {
    static func open(_ volume: DriveVolume) {
        NSWorkspace.shared.open(URL(fileURLWithPath: volume.mountPath))
    }

    /// `unmountAndEjectDevice` throws for a busy volume; the alert is the only place the reason can go.
    static func eject(_ volume: DriveVolume) {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: URL(fileURLWithPath: volume.mountPath))
        } catch {
            NSSound.beep()
        }
    }
}
