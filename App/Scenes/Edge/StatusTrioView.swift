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

/// Now-playing flyout: reuses the strip chip's popup view with a shared `NowPlayingService`.
struct NowPlayingFlyoutView: View {
    @ObservedObject var service: NowPlayingService

    var body: some View {
        NowPlayingPopup(state: service.state, theme: .auto, onToggle: { service.togglePlayPause() }, onNext: { service.nextTrack() }, onPrevious: { service.previousTrack() })
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

/// Phase 16h: the Control Center content — iPad-style layout: a connectivity cluster, a volume slider,
/// a now-playing card, the one-tap switch grid, and a bottom utility row. All through the shared
/// `QuickToggleEngine` / `SystemStatusService` / `NowPlayingService`. The brightness/cluster extras land in 16i.
struct ControlCenterView: View {
    @ObservedObject var engine: QuickToggleEngine
    let order: [QuickToggleID]
    /// Phase 16l: user widgets (the six ported Pinboard tiles) hosted below the switch grid.
    let widgetTiles: [TileKind]
    @AppStorage(TilePalette.storageKey) private var palette: TilePalette = .classic
    @AppStorage(WidgetExtraPrefs.glassTilesKey) private var glassTiles = false
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var status = SystemStatusService()
    @StateObject private var nowPlaying = NowPlayingService()
    @State private var confirming: QuickToggleID?
    /// Phase 16i: read once on appear; nil when the private API is unavailable (slider hidden).
    @State private var brightness: Double? = DisplayServicesBrightness.current()
    @State private var keyLight: Double? = KeyboardBacklight.isAvailable ? KeyboardBacklight.current() : nil

    var onSettings: () -> Void = {}
    var onLauncher: () -> Void = {}
    var onCapture: () -> Void = {}
    var onPinboard: () -> Void = {}
    var onDrawer: () -> Void = {}
    var onQuit: () -> Void = {}

    private var connectivity: [QuickToggleID] { [.wifi, .bluetooth] }
    private var quickActions: [QuickToggleID] { order.filter { !connectivity.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Quick Settings").font(.headline)
            HStack(spacing: 10) {
                ForEach(connectivity, id: \.self) { id in tile(id) }
            }
            volumeRow
            if let brightness {
                slider(icon: "sun.max.fill", value: Binding(get: { brightness }, set: { self.brightness = $0; DisplayServicesBrightness.set($0) }))
            }
            if let keyLight {
                slider(icon: "keyboard", value: Binding(get: { keyLight }, set: { self.keyLight = $0; KeyboardBacklight.set($0) }))
            }
            nowPlayingCard
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 12) {
                    ForEach(quickActions, id: \.self) { id in cell(id) }
                }
                widgetsSection
            }
            Spacer(minLength: 0)
            utilityRow
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { engine.refresh(); status.acquire() }
        .onDisappear { status.release() }
    }

    private func tile(_ id: QuickToggleID) -> some View {
        let on = engine.states[id] ?? false
        return Button { engine.perform(id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: id.symbolName).font(.system(size: 18, weight: .semibold))
                    .foregroundColor(on ? .white : .primary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(on ? Color.accentColor : Color.primary.opacity(0.10)))
                id.title.font(.system(size: 13, weight: .semibold))
                subtitle(id).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(on ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private func subtitle(_ id: QuickToggleID) -> Text {
        guard id == .wifi else { return Text(verbatim: "") }
        let w = status.status.wifi
        if w.isPoweredOn, let ssid = w.ssid, w.isConnected { return Text(verbatim: ssid) }
        return Text("Not Connected")
    }

    private var volumeRow: some View {
        let v = status.status.volume
        return slider(icon: v.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                      value: Binding(get: { Double(v.level) }, set: { _ = status.setVolume(Float($0)) }))
    }

    private func slider(icon: String, value: Binding<Double>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 14)).frame(width: 22)
            Slider(value: value, in: 0...1)
            Text(verbatim: "\(Int((value.wrappedValue * 100).rounded()))").font(.system(size: 12)).monospacedDigit()
                .foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private var nowPlayingCard: some View {
        let s = nowPlaying.state
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.10))
                .frame(width: 46, height: 46).overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
            VStack(alignment: .leading, spacing: 2) {
                if let title = s.title {
                    Text(verbatim: title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(verbatim: s.artist ?? "").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("Nothing Playing").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if s.title != nil {
                Button { nowPlaying.previousTrack() } label: { Image(systemName: "backward.fill") }.buttonStyle(.plain)
                Button { nowPlaying.togglePlayPause() } label: { Image(systemName: s.isPlaying ? "pause.fill" : "play.fill") }.buttonStyle(.plain)
                Button { nowPlaying.nextTrack() } label: { Image(systemName: "forward.fill") }.buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    /// Phase 16l: user widgets hosted in the panel — the six ported tiles in the stored order.
    /// Tiles create their own services and tear them down with the panel (content is dropped on hide).
    private var widgetsSection: some View {
        Group {
            if !widgetTiles.isEmpty {
                Text("Widgets").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                ForEach(widgetTiles, id: \.self) { kind in
                    GeometryReader { geo in hostedTile(kind, width: geo.size.width) }
                        .frame(height: 150)
                }
            }
        }
    }

    private var tileEnv: TileEnv {
        TileEnv(palette: palette, isDark: colorScheme == .dark, glass: glassTiles)
    }

    @ViewBuilder
    private func hostedTile(_ kind: TileKind, width: CGFloat) -> some View {
        switch kind {
        case .calculator: CalculatorTile(env: tileEnv, width: width, height: 150)
        case .screenTime: ScreenTimeTile(env: tileEnv, width: width, height: 150)
        case .network: NetworkTile(env: tileEnv, width: width, height: 150)
        case .battery: BatteryTile(env: tileEnv, width: width, height: 150)
        case .topApps: TopAppsTile(env: tileEnv, width: width, height: 150)
        case .batteries: BatteriesTile(env: tileEnv, width: width, height: 150)
        default: EmptyView()
        }
    }

    private var utilityRow: some View {
        HStack(spacing: 6) {
            utility("gearshape", "Settings", onSettings)
            utility("square.grid.2x2", "Launcher", onLauncher)
            utility("camera.viewfinder", "Capture", onCapture)
            utility("square.grid.3x3", "Pinboard", onPinboard)
            utility("rectangle.stack", "Drawer", onDrawer)
            utility("power", "Quit", onQuit)
        }
    }

    private func utility(_ symbol: String, _ label: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 16))
                Text(label).font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private func cell(_ id: QuickToggleID) -> some View {
        let on = engine.states[id] ?? false
        let gone = engine.unavailable.contains(id)
        let armed = confirming == id
        return Button {
            if id.needsConfirm && !armed {
                confirming = id
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if confirming == id { confirming = nil } }
                return
            }
            confirming = nil
            engine.perform(id)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: engine.flash == id ? "checkmark" : id.symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(on || armed ? .white : .primary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(armed ? Color.red.opacity(0.9) : (on ? Color.accentColor : Color.primary.opacity(0.10))))
                    .overlay(armed ? Image(systemName: "exclamationmark").font(.system(size: 9, weight: .heavy)).foregroundColor(.white).offset(x: 14, y: -14) : nil)
                id.title.font(.system(size: 9, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .opacity(gone ? 0.35 : 1)
        .disabled(gone)
    }
}
