import SwiftUI

/// The three statuses the combined chip exposes; each opens its own popover (Phase 7A-5).
enum StatusKind: CaseIterable, Hashable {
    case wifi, battery, volume

    var popupSize: CGSize {
        switch self {
        case .wifi, .battery: return CGSize(width: 240, height: 112)
        case .volume: return CGSize(width: 240, height: 124)
        }
    }

    /// System Settings pane for the popover's "Open System Settings…" button.
    var settingsURL: URL? {
        if #available(macOS 13.0, *) {
            switch self {
            case .wifi: return URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")
            case .battery: return URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")
            case .volume: return URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")
            }
        }
        switch self {
        case .wifi: return URL(string: "x-apple.systempreferences:com.apple.preference.network")
        case .battery: return URL(string: "x-apple.systempreferences:com.apple.preference.battery")
        case .volume: return URL(string: "x-apple.systempreferences:com.apple.preference.sound")
        }
    }
}

/// Edge-bar content: stacked tiles for the preset's content (notes placeholder, status trio).
struct EdgeBarContentView: View {
    let content: [EdgeBarContent]
    @ObservedObject var service: SystemStatusService
    let onStatusTap: (StatusKind, CGRect) -> Void
    let onNotesTap: (CGRect) -> Void
    let onWidgetTap: (WidgetTile, CGRect) -> Void

    var body: some View {
        VStack(spacing: EdgeBarLayout.tileSpacing) {
            ForEach(Array(content.enumerated()), id: \.offset) { _, kind in
                switch kind {
                case .notes:
                    EdgeNotesTile(onTap: onNotesTap)
                case .status:
                    StatusTrioView(status: service.status, onTap: onStatusTap)
                case let .widget(tile):
                    EdgeWidgetTile(tile: tile, onTap: onWidgetTap)
                }
            }
        }
        .padding(.vertical, EdgeBarLayout.verticalPadding)
        .frame(width: EdgeBarLayout.width)
    }
}

/// Wi-Fi + battery + volume in one compact column; each glyph is its own popover trigger.
struct StatusTrioView: View {
    let status: SystemStatus
    let onTap: (StatusKind, CGRect) -> Void

    var body: some View {
        VStack(spacing: 0) {
            row(.wifi) {
                wifiGlyph
                    .foregroundStyle(status.wifi.isConnected ? Color.primary : Color.secondary)
            }
            row(.battery) {
                Image(systemName: status.battery.symbolName)
                    .foregroundStyle(status.battery.isCharging ? Color.green : Color.primary)
            }
            row(.volume) {
                Image(systemName: status.volume.symbolName)
            }
        }
        .padding(.vertical, 8)
        .frame(width: EdgeBarLayout.width, height: EdgeBarLayout.statusTileHeight)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06))
        )
    }

    /// Variable-value symbols need macOS 13; on 12 the plain glyph carries the state.
    @ViewBuilder private var wifiGlyph: some View {
        if #available(macOS 13.0, *) {
            Image(systemName: status.wifi.symbolName, variableValue: status.wifi.symbolVariableValue)
        } else {
            Image(systemName: status.wifi.symbolName)
        }
    }

    private func row<Glyph: View>(_ kind: StatusKind, @ViewBuilder glyph: () -> Glyph) -> some View {
        StatusTrioRow(kind: kind, onTap: onTap, glyph: glyph())
    }
}

private struct StatusTrioRow<Glyph: View>: View {
    let kind: StatusKind
    let onTap: (StatusKind, CGRect) -> Void
    let glyph: Glyph

    var body: some View {
        GeometryReader { proxy in
            Button {
                onTap(kind, proxy.frame(in: .global))
            } label: {
                glyph
                    .font(.system(size: 17, weight: .medium))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: EdgeBarLayout.statusRowHeight)
    }
}

/// Popover content for one status (hosted by `EdgeFlyoutController`).
struct StatusPopupView: View {
    let kind: StatusKind
    @ObservedObject var service: SystemStatusService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch kind {
            case .wifi: wifi
            case .battery: battery
            case .volume: volume
            }
            Spacer(minLength: 0)
            Button("Open System Settings…") {
                if let url = kind.settingsURL { NSWorkspace.shared.open(url) }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(14)
        .frame(width: kind.popupSize.width, height: kind.popupSize.height, alignment: .topLeading)
    }

    private var wifi: some View {
        let wifi = service.status.wifi
        return VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "Wi-Fi").font(.headline)
            if !wifi.isPoweredOn {
                Text("Wi-Fi Off").foregroundStyle(.secondary)
            } else if let ssid = wifi.ssid, wifi.isConnected {
                Text(verbatim: ssid)
            } else if wifi.isConnected {
                Text(verbatim: "\(wifi.rssi ?? 0) dBm").foregroundStyle(.secondary).monospacedDigit()
            } else {
                Text("Not Connected").foregroundStyle(.secondary)
            }
        }
    }

    private var battery: some View {
        let battery = service.status.battery
        return VStack(alignment: .leading, spacing: 4) {
            Text("Battery").font(.headline)
            if let level = battery.level {
                Text(verbatim: "\(level)%").font(.title2.weight(.semibold)).monospacedDigit()
                Group {
                    if battery.isCharging { Text("Charging") }
                    else if battery.isPluggedIn { Text("Plugged In") }
                    else { Text("On Battery") }
                }
                .foregroundStyle(.secondary)
            } else {
                Text("No Battery").foregroundStyle(.secondary)
            }
        }
    }

    private var volume: some View {
        let volume = service.status.volume
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Volume").font(.headline)
                Spacer()
                Group {
                    if volume.isMuted { Text("Muted") } else { Text(verbatim: "\(volume.percent)%") }
                }
                .foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: Binding(
                get: { Double(volume.level) },
                set: { service.setVolume(Float($0)) }
            ), in: 0...1)
        }
    }
}

private struct EdgeNotesTile: View {
    let onTap: (CGRect) -> Void

    var body: some View {
        GeometryReader { proxy in
            Button {
                onTap(proxy.frame(in: .global))
            } label: {
                Image(systemName: "note.text")
                    .font(.system(size: 20, weight: .medium))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: EdgeBarLayout.width, height: EdgeBarLayout.notesTileHeight)
    }
}

/// A glyph tile for one widget (weather, now playing, …); the tap reports its frame for flyout placement.
private struct EdgeWidgetTile: View {
    let tile: WidgetTile
    let onTap: (WidgetTile, CGRect) -> Void

    private var symbol: String {
        switch tile {
        case .weather: return "cloud.sun.fill"
        case .nowPlaying: return "music.note"
        case .bluetooth: return "wave.3.right.circle.fill"
        }
    }

    private var label: Text {
        switch tile {
        case .weather: return Text("Weather")
        case .nowPlaying: return Text("Now Playing")
        case .bluetooth: return Text("Bluetooth")
        }
    }

    var body: some View {
        GeometryReader { proxy in
            Button {
                onTap(tile, proxy.frame(in: .global))
            } label: {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                    .symbolRenderingMode(.multicolor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(label)
        }
        .frame(width: EdgeBarLayout.width, height: EdgeBarLayout.widgetTileHeight)
    }
}

/// Now-playing flyout: reuses the strip chip's popup view with a shared `NowPlayingService`.
struct NowPlayingFlyoutView: View {
    @ObservedObject var service: NowPlayingService

    var body: some View {
        NowPlayingPopup(state: service.state, theme: .auto, onToggle: { service.togglePlayPause() })
            .padding(12)
    }
}

/// Bluetooth flyout (7A-8b): connected devices first with battery, a refresh button, and a link to
/// System Settings. The list is read only when the flyout opens (or on refresh) — never polled.
struct BluetoothFlyoutView: View {
    @State private var devices: [BluetoothDevice] = []
    @State private var loading = true

    static let size = CGSize(width: 300, height: 260)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Bluetooth").font(.headline)
                Spacer()
                if loading { ProgressView().controlSize(.small) }
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help(Text("Refresh"))
            }
            if devices.isEmpty && !loading {
                Text("No Bluetooth Devices").foregroundStyle(.secondary).font(.callout)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(devices) { row($0) }
                    }
                }
            }
            Button("Open System Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") { NSWorkspace.shared.open(url) }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(14)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .task { await load() }
    }

    private func row(_ d: BluetoothDevice) -> some View {
        HStack(spacing: 8) {
            Image(systemName: d.symbolName).frame(width: 22)
            Text(verbatim: d.name).lineLimit(1)
            Spacer(minLength: 4)
            if let level = d.lowestBattery {
                Text(verbatim: "\(level)%").monospacedDigit().foregroundStyle(level <= 20 ? Color.red : Color.secondary)
            }
            Circle().fill(d.isConnected ? Color.green : Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
        }
        .opacity(d.isConnected ? 1 : 0.55)
    }

    @MainActor private func load() async {
        loading = true
        devices = await BluetoothDeviceReader.read()
        loading = false
    }
}
