import AppKit
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
        switch self {
        case .wifi: return URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")
        case .battery: return URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")
        case .volume: return URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")
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
        NowPlayingPopup(state: service.state, theme: .auto, access: service.playerAccess,
                        onToggle: { service.togglePlayPause() }, onNext: { service.nextTrack() },
                        onPrevious: { service.previousTrack() }, onSeek: { service.seek(to: $0) })
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

/// Phase 16h / redesigned 2026-10-22 (owner screenshot): the Control Center content.
///
/// **The chrome is the dock's.** `\.dockThemeStyle` and `\.themeTuning` are injected by the host, so
/// every preset the Appearance page offers — plus the vibrancy/contrast knobs — restyles this panel
/// the way it restyles the bar: the plate takes that preset's own overlay tint and rim, cards wear
/// the same `SettingsIridescentPalette` the Appearance swatches are drawn from, and text takes the
/// dock's label tints. Nothing here picks its own accent.
///
/// Layout, top to bottom: header (clock + battery), system & peripherals with live percentages,
/// Wi-Fi / Bluetooth bento, now playing, the switch grid (4 or 5 per row, see `ControlCenterGrid`),
/// the network row, three sliders, the utility row and the account footer.
struct ControlCenterView: View {
    @ObservedObject var engine: QuickToggleEngine
    let order: [QuickToggleID]
    /// Phase 16l/16n: user widgets. Battery/batteries drive the peripherals card, network the row.
    let widgetTiles: [TileKind]
    var style: ControlCenterStyle = .classic
    @StateObject private var status = SystemStatusService()
    @ObservedObject private var nowPlaying = NowPlayingService.shared
    @State private var confirming: QuickToggleID?
    /// Phase 16i: read once on appear; nil when the private API is unavailable (slider hidden).
    @State private var brightness: Double? = DisplayServicesBrightness.current()
    @State private var keyLight: Double? = KeyboardBacklight.isAvailable ? KeyboardBacklight.current() : nil
    /// 57a: wheel travel left over between events on the volume row.
    @State private var volumeScroll = ControlCenterScroll.State()
    /// Connected Bluetooth devices that report a battery. Read once per open and on demand — the read
    /// shells out to `system_profiler`, so it is never polled.
    @State private var peripherals: [BluetoothDevice] = []
    @State private var peripheralsLoading = true

    var onSettings: () -> Void = {}
    var onLauncher: () -> Void = {}
    var onCapture: () -> Void = {}
    var onDrawer: () -> Void = {}
    var onQuit: () -> Void = {}

    /// Shared with the host so the panel's plate and this wash cannot drift apart.
    static let cornerRadius: CGFloat = 22
    static let ipadCornerRadius: CGFloat = 30
    private var isPad: Bool { style == .ipad }
    private var panelRadius: CGFloat { isPad ? Self.ipadCornerRadius : Self.cornerRadius }
    private var cardRadius: CGFloat { isPad ? 20 : Metrics.cardRadius }

    @Environment(\.dockThemeStyle) private var dockThemeStyle
    @Environment(\.themeTuning) private var themeTuning
    @Environment(\.colorScheme) private var colorScheme

    private enum Metrics {
        static let padding: CGFloat = 12
        static let sectionGap: CGFloat = 9
        static let cardRadius: CGFloat = 16
        static let cardPadding: CGFloat = 10
        static let circle: CGFloat = 38
        static let gridGap: CGFloat = 7
        /// One switch row: circle + gap + label. The grid's capacity is measured in these.
        static let gridPitch: CGFloat = 61
        static let rowGap: CGFloat = 7
        static let barHeight: CGFloat = 3
    }

    private var theme: DockThemeTokens { .resolved(for: colorScheme, style: dockThemeStyle) }
    private var palette: SettingsIridescentPalette { .resolve(style: dockThemeStyle, colorScheme: colorScheme) }
    /// Dock label tints: black on the light column, white on the dark one, so text flips with the plate.
    private var ink: Color { theme.labelActive.color }
    private var inkSoft: Color { theme.labelSubtitle.color }

    private var connectivity: [QuickToggleID] { [.wifi, .bluetooth] }
    private var quickActions: [QuickToggleID] { order.filter { !connectivity.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionGap) {
            header
            peripheralsCard
            HStack(spacing: 8) {
                ForEach(connectivity, id: \.self) { id in connectivityCard(id) }
            }
            nowPlayingCard
            switchGrid
            if widgetTiles.contains(.network) {
                card(padding: 9) { ControlCenterNetworkRow() }
            }
            sliderRows
            utilityRow
            card(padding: 8) { ControlCenterAccountRow() }
        }
        .padding(Metrics.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(plateWash)
        .overlay(plateRim)
        .onAppear { engine.refresh(); status.acquire() }
        .onDisappear { status.release() }
        .task { await refreshPeripherals() }
    }

    // MARK: - Panel chrome (the dock theme's own)

    /// The preset's plate tint, exactly as the bar's backdrop computes it (`DockPanelBackdrop`).
    /// `nil` for Auto/System: those presets tint nothing, so neither does this panel.
    @ViewBuilder
    private var plateWash: some View {
        if !isPad, let top = dockThemeStyle.plateOverlay(baseTint: theme.styleTokens.baseTint,
                                                 vibrancy: themeTuning.vibrancy,
                                                 contrast: themeTuning.contrast,
                                                 translucency: themeTuning.translucency) {
            RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
                .fill(DockGlassBackdrop.overlayPaint(
                    top: top,
                    bottom: dockThemeStyle.plateOverlayBottom(
                        baseTintBottom: theme.styleTokens.baseTintBottom,
                        vibrancy: themeTuning.vibrancy,
                        contrast: themeTuning.contrast,
                        translucency: themeTuning.translucency)))
                .allowsHitTesting(false)
        }
    }

    private var plateRim: some View {
        RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
            .strokeBorder(theme.panelRimStyle, lineWidth: theme.panelRimLineWidth)
            .padding(0.25)
            .allowsHitTesting(false)
    }

    private var cardStroke: Color {
        isPad ? Color.white.opacity(colorScheme == .dark ? 0.10 : 0.65) : Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.07)
    }

    private var cardFill: AnyShapeStyle {
        if isPad { return AnyShapeStyle(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.55)) }
        return AnyShapeStyle(LinearGradient(colors: [Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.05),
                                              palette.cardTintBottom],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var activeFill: AnyShapeStyle {
        AnyShapeStyle(LinearGradient(colors: [palette.primaryAccent.opacity(0.30), palette.secondaryAccent.opacity(0.13)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func card<Content: View>(active: Bool = false, padding: CGFloat = Metrics.cardPadding,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .fill(active ? activeFill : cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .strokeBorder(active ? AnyShapeStyle(palette.primaryAccent.opacity(0.45))
                                         : AnyShapeStyle(cardStroke),
                                  lineWidth: 1)
            )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 7) {
            Text("Quick Settings")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(ink)
            clockPill
            Spacer(minLength: 4)
            batteryPill
        }
        .padding(.horizontal, 1)
    }

    private var clockPill: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(verbatim: Self.clockFormatter.string(from: context.date))
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(inkSoft)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private var batteryPill: some View {
        let battery = status.status.battery
        return HStack(spacing: 4) {
            Image(systemName: battery.isCharging ? "bolt.fill" : "battery.75")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(battery.isCharging ? Color.green : palette.primaryAccent)
            // Fixed slot: a missing reading must not resize the header.
            Text(verbatim: battery.level.map { "\($0)%" } ?? "–")
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(ink)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
        .overlay(Capsule().strokeBorder(cardStroke, lineWidth: 0.5))
        .help(Text(verbatim: battery.facts.summary ?? ""))
    }

    // MARK: - System & peripherals

    @ViewBuilder
    private var peripheralsCard: some View {
        let showsThisMac = widgetTiles.contains(.battery)
        let showsDevices = widgetTiles.contains(.batteries)
        if showsThisMac || showsDevices {
            card {
                VStack(alignment: .leading, spacing: Metrics.rowGap) {
                    HStack(spacing: 6) {
                        Text("System & Peripherals")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(ink)
                        if status.status.battery.isCharging {
                            Text("Charging")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.green)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.green.opacity(0.14)))
                        }
                        // 59e: the OS's own power saving, shown where the reading is.
                        if status.status.battery.facts.isLowPowerMode {
                            Text("Low Power")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.orange)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.orange.opacity(0.14)))
                        }
                        Spacer(minLength: 0)
                        Button { Task { await refreshPeripherals() } } label: {
                            HStack(spacing: 4) {
                                Text(verbatim: deviceCount(peripheralCount))
                                    .font(.system(size: 10.5, weight: .medium))
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundStyle(inkSoft)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(Text("Refresh"))
                    }
                    if showsThisMac {
                        deviceRow(symbol: "laptopcomputer",
                                  name: String(localized: "This Mac"),
                                  // 59d: time to empty/full, charging watts, heat.
                                  detail: status.status.battery.facts.summary,
                                  level: status.status.battery.level,
                                  charging: status.status.battery.isCharging,
                                  low: (status.status.battery.level ?? 100) <= 20 && !status.status.battery.isCharging)
                    }
                    if showsDevices {
                        if peripheralsLoading && peripherals.isEmpty {
                            ProgressView().controlSize(.small)
                        } else {
                            ForEach(peripherals) { device in
                                deviceRow(symbol: device.symbolName,
                                          name: device.name,
                                          detail: device.batteryBreakdown,
                                          level: device.lowestBattery,
                                          charging: false,
                                          low: device.isLowBattery)
                            }
                            if peripherals.isEmpty {
                                Text("No connected devices report a battery")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(inkSoft)
                            }
                        }
                    }
                }
            }
        }
    }

    private var peripheralCount: Int {
        (widgetTiles.contains(.battery) && status.status.battery.level != nil ? 1 : 0) + peripherals.count
    }

    private func deviceRow(symbol: String, name: String, detail: String?, level: Int?,
                           charging: Bool, low: Bool) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(inkSoft)
                    .frame(width: 18)
                Text(verbatim: name)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(ink)
                if let detail {
                    Text(verbatim: "· " + detail)
                        .font(.system(size: 9.5))
                        .lineLimit(1)
                        .foregroundStyle(inkSoft)
                }
                Spacer(minLength: 4)
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(Color.green)
                }
                Text(verbatim: level.map { "\($0)%" } ?? "–")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(low ? Color.red : ink)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(levelGradient(charging: charging, low: low))
                        .frame(width: proxy.size.width * CGFloat(level ?? 0) / 100)
                }
            }
            .frame(height: Metrics.barHeight)
            .padding(.leading, 24)
        }
        .accessibilityElement(children: .combine)
    }

    private func levelGradient(charging: Bool, low: Bool) -> LinearGradient {
        let colors: [Color] = charging ? [Color(red: 0.20, green: 0.78, blue: 0.45), Color(red: 0.13, green: 0.66, blue: 0.40)]
            : low ? [Color(red: 0.95, green: 0.30, blue: 0.30), Color(red: 0.98, green: 0.55, blue: 0.25)]
            : [palette.primaryAccent, palette.secondaryAccent]
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    private func accentIcon(symbol: String, on: Bool, size: CGFloat = 32) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(on ? Color.white : inkSoft)
            .frame(width: size, height: size)
            .background(Circle().fill(on ? AnyShapeStyle(palette.pillGradient)
                                          : AnyShapeStyle(Color.primary.opacity(0.09))))
            .overlay(Circle().strokeBorder(on ? Color.white.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 1))
            .shadow(color: on ? palette.glowColor : .clear, radius: 6, y: 2)
    }

    // MARK: - Wi-Fi / Bluetooth

    private func connectivityCard(_ id: QuickToggleID) -> some View {
        let on = engine.states[id] ?? false
        return card(active: on, padding: 0) {
            ZStack(alignment: .topTrailing) {
                Button { engine.perform(id) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        accentIcon(symbol: id.symbolName, on: on)
                        VStack(alignment: .leading, spacing: 1) {
                            id.title
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(ink)
                                .lineLimit(1)
                            Text(verbatim: connectivityDetail(id, on: on))
                                .font(.system(size: 10.5))
                                .foregroundStyle(inkSoft)
                                .lineLimit(1)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { openSettings(for: id) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(inkSoft)
                        .padding(9)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Text("Open System Settings…"))
            }
        }
    }

    private func connectivityDetail(_ id: QuickToggleID, on: Bool) -> String {
        guard on else { return String(localized: "Off") }
        switch id {
        case .wifi:
            let wifi = status.status.wifi
            guard wifi.isPoweredOn else { return String(localized: "Off") }
            return wifi.ssid.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Not Connected")
        case .bluetooth:
            return deviceCount(peripherals.count)
        default:
            return ""
        }
    }

    /// "1 Device" / "4 Devices" — the count plus a localized noun.
    private func deviceCount(_ count: Int) -> String {
        let noun = count == 1 ? String(localized: "Device") : String(localized: "Devices")
        return "\(count) " + noun
    }

    private func openSettings(for id: QuickToggleID) {
        let raw = id == .wifi ? "x-apple.systempreferences:com.apple.wifi-settings-extension"
                              : "x-apple.systempreferences:com.apple.BluetoothSettings"
        guard let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Now playing

    private var nowPlayingCard: some View {
        let state = nowPlaying.state
        let hasTrack = state.title != nil
        return card(padding: 9) {
            VStack(spacing: 6) {
                HStack(spacing: 9) {
                    artwork(state)
                    VStack(alignment: .leading, spacing: 1) {
                        Group {
                            if let title = state.title {
                                Text(verbatim: title)
                            } else {
                                Text("Nothing Playing")
                            }
                        }
                        .font(.system(size: 12.5, weight: hasTrack ? .semibold : .regular))
                        .foregroundStyle(hasTrack ? ink : inkSoft)
                        .lineLimit(1)
                        // Non-breaking space: keeps the second line (and the card height) when no artist.
                        Text(verbatim: state.artist ?? " ")
                            .font(.system(size: 10.5))
                            .foregroundStyle(inkSoft)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    transport("backward.end.fill", String(localized: "Previous")) { nowPlaying.previousTrack() }
                    transport(state.isPlaying ? "pause.fill" : "play.fill",
                              String(localized: state.isPlaying ? "Pause" : "Play")) { nowPlaying.togglePlayPause() }
                    transport("forward.end.fill", String(localized: "Next")) { nowPlaying.nextTrack() }
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.10))
                            Capsule()
                                .fill(LinearGradient(colors: [palette.primaryAccent, palette.secondaryAccent],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: proxy.size.width * CGFloat((state.progress(at: context.date) ?? 0)))
                        }
                    }
                    .frame(height: 3)
                }
                .opacity(hasTrack ? 1 : 0)
            }
        }
        .disabled(!hasTrack)
        .opacity(hasTrack ? 1 : 0.85)
    }

    private func artwork(_ state: NowPlayingState) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(LinearGradient(colors: [palette.primaryAccent.opacity(0.9), palette.secondaryAccent.opacity(0.8)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 38, height: 38)
            .overlay(
                Group {
                    if let data = state.artworkData, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            )
    }

    private func transport(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(ink)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: label))
        .accessibilityLabel(Text(verbatim: label))
    }

    // MARK: - Switch grid

    /// The grid is the panel's spring: it takes whatever height the fixed sections leave (the panel
    /// fills the space between the menu bar and the dock) and its rows sit centred in it. When that
    /// height cannot hold four rows at four per row, the grid goes five per row instead — that is the
    /// 4→5 step, measured here rather than guessed from the screen size.
    private var switchGrid: some View {
        GeometryReader { proxy in
            let rowsFit = max(1, Int(proxy.size.height / Metrics.gridPitch))
            let columns = ControlCenterGrid.columns(count: quickActions.count, rowsFit: rowsFit)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns),
                      alignment: .center,
                      spacing: Metrics.gridGap) {
                ForEach(quickActions, id: \.self) { id in cell(id) }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .frame(minHeight: gridMinHeight, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.18), value: quickActions.count)
    }

    /// Never collapse to nothing on a short screen: the grid keeps the height four rows need.
    private var gridMinHeight: CGFloat {
        CGFloat(ControlCenterGrid.rows(count: quickActions.count, columns: ControlCenterGrid.baseColumns)) * Metrics.gridPitch
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(on || armed ? Color.white : ink)
                    .frame(width: Metrics.circle, height: Metrics.circle)
                    .background(Circle().fill(armed ? AnyShapeStyle(Color.red.opacity(0.9))
                                                    : on ? AnyShapeStyle(palette.pillGradient)
                                                         : AnyShapeStyle(Color.primary.opacity(0.09))))
                    .overlay(Circle().strokeBorder(on || armed ? Color.white.opacity(0.30)
                                                               : Color.white.opacity(0.06),
                                                   lineWidth: 1))
                    .overlay(armed ? Image(systemName: "exclamationmark")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                        .offset(x: 13, y: -13) : nil)
                    .shadow(color: on || armed ? palette.glowColor : .clear, radius: 6, y: 2)
                    .scaleEffect(armed ? 1.06 : 1)
                id.title
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .foregroundStyle(inkSoft)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, isPad ? 6 : 0)
            .background(isPad ? RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(on ? activeFill : cardFill) : nil)
            .overlay(isPad ? RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(on ? palette.primaryAccent.opacity(0.45) : cardStroke, lineWidth: 1) : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(gone ? 0.35 : 1)
        .disabled(gone)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: on)
        .accessibilityAddTraits(on ? .isSelected : [])
        .contextMenu {
            if id == .vpn {
                ForEach(engine.vpnServices, id: \.id) { service in
                    Button {
                        engine.toggleVPNService(service)
                    } label: {
                        if service.connected {
                            Label(service.name, systemImage: "checkmark")
                        } else {
                            Text(verbatim: service.name)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sliders

    @ViewBuilder
    private var sliderRows: some View {
        VStack(spacing: 6) {
            volumeRow
            if let brightness {
                sliderRow(icon: "sun.max.fill",
                          value: Binding(get: { brightness }, set: { self.brightness = $0; DisplayServicesBrightness.set($0) }))
            }
            if let keyLight {
                sliderRow(icon: "keyboard",
                          value: Binding(get: { keyLight }, set: { self.keyLight = $0; KeyboardBacklight.set($0) }))
            }
        }
    }

    private var volumeRow: some View {
        let volume = status.status.volume
        return sliderRow(icon: volume.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                         value: Binding(get: { Double(volume.level) }, set: { _ = status.setVolume(Float($0)) }))
            // Scrolling anywhere on the row nudges the volume. The catcher claims wheel events only, so the
            // slider underneath keeps its drag and clicks.
            .overlay {
                VolumeScrollCatcher { deltaY, precise in
                    guard let next = ControlCenterScroll.consume(
                        deltaY: deltaY, precise: precise, level: status.currentVolumeLevel,
                        state: &volumeScroll) else { return }
                    _ = status.setVolume(Float(next))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
    }

    /// iPadOS skin: a thick capsule whose fill is the value, icon on the left and number on the right.
    private func padSliderRow(icon: String, value: Binding<Double>) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [palette.primaryAccent, palette.secondaryAccent],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(44, proxy.size.width * CGFloat(value.wrappedValue)))
                HStack {
                    Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(verbatim: "\(Int((value.wrappedValue * 100).rounded()))")
                        .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                }
                .foregroundStyle(ink)
                .padding(.horizontal, 14)
                .allowsHitTesting(false)
            }
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                value.wrappedValue = Double(min(1, max(0, drag.location.x / proxy.size.width)))
            })
        }
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityValue(Text(verbatim: "\(Int((value.wrappedValue * 100).rounded()))"))
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 0.05 : -0.05
            value.wrappedValue = min(1, max(0, value.wrappedValue + step))
        }
    }

    private func sliderRow(icon: String, value: Binding<Double>) -> some View {
        if isPad { return AnyView(padSliderRow(icon: icon, value: value)) }
        return AnyView(sliderRowClassic(icon: icon, value: value))
    }

    private func sliderRowClassic(icon: String, value: Binding<Double>) -> some View {
        card(padding: 8) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(inkSoft)
                    .frame(width: 18)
                Slider(value: value, in: 0...1)
                    .controlSize(.small)
                    .tint(palette.primaryAccent)
                Text(verbatim: "\(Int((value.wrappedValue * 100).rounded()))")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(inkSoft)
                    .frame(width: 26, alignment: .trailing)
            }
        }
    }

    // MARK: - Bottom rows

    private var utilityRow: some View {
        HStack(spacing: 6) {
            utility("gearshape", "KatiKati Settings", onSettings)
            utility("square.grid.2x2", "Launcher", onLauncher)
            utility("camera.viewfinder", "Capture", onCapture)
            utility("rectangle.stack", "Drawer", onDrawer)
            utility("power", "Quit", onQuit)
        }
    }

    private func utility(_ symbol: String, _ label: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(cardFill))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(cardStroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Peripherals

    /// Connected peripherals with a battery reading, at most four (the card is a list, not a scroll view).
    @MainActor private func refreshPeripherals() async {
        peripheralsLoading = true
        let all = await BluetoothDeviceReader.read()
        peripherals = Array(all.filter { $0.isConnected && $0.lowestBattery != nil }.prefix(4))
        peripheralsLoading = false
    }
}


/// 57a: takes wheel events over one Control Center row and hands their travel to a closure. Every other event
/// falls through, so buttons and the volume slider keep working — same `hitTest` shape as
/// `WheelScrollInterceptorView`, without the scroll-view coupling.
private struct VolumeScrollCatcher: NSViewRepresentable {
    let onScroll: (CGFloat, Bool) -> Void

    func makeNSView(context: Context) -> VolumeScrollCatcherView { VolumeScrollCatcherView() }

    func updateNSView(_ nsView: VolumeScrollCatcherView, context: Context) { nsView.onScroll = onScroll }
}

private final class VolumeScrollCatcherView: NSView {
    var onScroll: ((CGFloat, Bool) -> Void)?

    /// Flexible, or SwiftUI gives a content-less view a zero frame and it never receives a wheel event.
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard super.hitTest(point) != nil, NSApp.currentEvent?.type == .scrollWheel else { return nil }
        return self
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.deltaY != 0 else { return super.scrollWheel(with: event) }
        onScroll?(event.deltaY, event.hasPreciseScrollingDeltas)
    }
}

// MARK: - Control Center compact widget rows (Phase 16r)

/// Live down/up rates; samples only while the row is on screen. The parent card supplies the chrome.
private struct ControlCenterNetworkRow: View {
    @ObservedObject private var monitor = ProductivityServices.shared.systemMonitor

    var body: some View {
        let snapshot = monitor.snapshot
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.up").font(.system(size: 12, weight: .medium)).frame(width: 18)
            Text("Network").font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 0)
            Image(systemName: "arrow.down").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            Text(verbatim: SystemMonitorFormat.bytes(snapshot.down) + "/s").font(.system(size: 11)).monospacedDigit()
            Image(systemName: "arrow.up").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            Text(verbatim: SystemMonitorFormat.bytes(snapshot.up) + "/s").font(.system(size: 11)).monospacedDigit()
        }
        .onAppear { monitor.acquire() }
        .onDisappear { monitor.release() }
    }
}

// MARK: - Control Center account row (Phase 16u)

/// The current macOS user (avatar + name) with a gear button; both open Users & Groups
/// ("Manage accounts"). Read once per open; picture falls back to a person glyph.
private struct ControlCenterAccountRow: View {
    @State private var user: CurrentUser?

    var body: some View {
        Button(action: CurrentUserReader.openUsersGroups) {
            HStack(spacing: 10) {
                avatar
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: user?.fullName ?? NSUserName())
                        .font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Text("Manage accounts").font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "gearshape").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task { user = CurrentUserReader.read() }
    }

    @ViewBuilder
    private var avatar: some View {
        if let data = user?.avatar, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable().scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 33)).foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
        }
    }
}

// MARK: - OpenTaskbar Inline Micro-Tiles (Slice 4.3)

struct InlineTodoCapsuleView: View {
    let model: InlineTodoPillModel
    var onToggle: (String) -> Void = { _ in }
    var onAdd: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checklist")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.blue)

            if model.isEmpty {
                Button(action: onAdd) {
                    Text(model.emptyStateText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(model.topTwoItems) { item in
                        Button { onToggle(item.id) } label: {
                            HStack(spacing: 4) {
                                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 8))
                                    .foregroundStyle(item.isDone ? .green : .secondary)
                                Text(item.title)
                                    .font(.system(size: 9.5, weight: .medium))
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(model.remainingCountBadge)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }
}

struct InlineScrubbableSliderBar: View {
    let icon: String
    let label: String
    @Binding var fraction: Double
    var tintColor: Color = .blue
    @State private var dragStartFraction: Double?

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tintColor.opacity(0.35))
                    .frame(width: max(0, width * CGFloat(fraction)))

                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 9.5, weight: .semibold))
                    Text(verbatim: "\(label) \(InlineBarSliderMath.formattedPercent(fraction))")
                        .font(.system(size: 9.5, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 7)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { g in
                        if dragStartFraction == nil { dragStartFraction = fraction }
                        fraction = InlineBarSliderMath.scrubFraction(
                            startFraction: dragStartFraction ?? fraction,
                            dragDeltaX: g.translation.width,
                            totalWidth: width
                        )
                    }
                    .onEnded { _ in dragStartFraction = nil }
            )
        }
        .frame(height: 22)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }
}

struct InlineAudioOutputSwitcher: View {
    let devices: [String]
    @Binding var selectedIndex: Int

    var body: some View {
        HStack(spacing: 4) {
            Button {
                selectedIndex = InlineBarSliderMath.cycleAudioDeviceIndex(
                    currentIndex: selectedIndex,
                    totalDevices: devices.count,
                    forward: false
                )
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)

            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 9, weight: .semibold))

            Text(devices.indices.contains(selectedIndex) ? devices[selectedIndex] : "Speaker")
                .font(.system(size: 9.5, weight: .medium))
                .lineLimit(1)

            Button {
                selectedIndex = InlineBarSliderMath.cycleAudioDeviceIndex(
                    currentIndex: selectedIndex,
                    totalDevices: devices.count,
                    forward: true
                )
            } label: {
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }
}

struct InlineQuickTogglePill: View {
    @Binding var wifiOn: Bool
    @Binding var bluetoothOn: Bool
    @Binding var micMuted: Bool
    @Binding var dndOn: Bool

    var body: some View {
        HStack(spacing: 6) {
            toggleBtn(icon: "wifi", active: wifiOn) { wifiOn.toggle() }
            toggleBtn(icon: "wave.3.forward", active: bluetoothOn) { bluetoothOn.toggle() }
            toggleBtn(icon: micMuted ? "mic.slash.fill" : "mic.fill", active: !micMuted) { micMuted.toggle() }
            toggleBtn(icon: "moon.fill", active: dndOn) { dndOn.toggle() }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }

    private func toggleBtn(icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(active ? .blue : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - MB-6: Menu Bar Creative Hub (Hop 2x2 Box Grid + OnlySwitch Tabs)

struct MenuBarCreativeHubView: View {
    var onDismiss: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    @ObservedObject private var engine = QuickToggleEngine.shared
    @StateObject private var status = SystemStatusService()
    @State private var selectedTab: MenuBarHubTab = MenuBarHubTab.visibleTabs().first ?? .switches
    @State private var query = ""
    @State private var boxSlots: [HubActionSlotID] = HubActionSlotID.slots()
    @State private var btAudioDevices: [BluetoothDevice] = []
    @State private var listeningMode: String? = AudioOutputSwitcher.bluetoothListeningMode()
    @State private var brightness: Double? = DisplayServicesBrightness.current()
    @State private var keyLight: Double? = KeyboardBacklight.isAvailable ? KeyboardBacklight.current() : nil
    @State private var surfaceVersion = 0

    @Environment(\.dockThemeStyle) private var dockThemeStyle
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: DockThemeTokens { .resolved(for: colorScheme, style: dockThemeStyle) }
    private var palette: SettingsIridescentPalette { .resolve(style: dockThemeStyle, colorScheme: colorScheme) }
    private var ink: Color { theme.labelActive.color }
    private var inkSoft: Color { theme.labelSubtitle.color }
    private var cardFill: Color { Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05) }
    private var cardStroke: Color { Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08) }
    private var tabs: [MenuBarHubTab] { MenuBarHubTab.visibleTabs() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerBar
            actionBoxGrid
            tabContent
        }
        .padding(12)
        .frame(width: 344, height: 472, alignment: .top)
        .background {
            DockPanelBackdrop(theme: theme, cornerRadius: 20, usesLiquidGlass: DockGlassPresentation.shouldAttemptTaskbarComposite)
        }
        .dockPanelRim(cornerRadius: 20, style: theme.panelRimStyle, lineWidth: theme.panelRimLineWidth,
                      usesLiquidGlass: DockGlassPresentation.shouldAttemptTaskbarComposite, highlighted: false)
        .onAppear {
            engine.refresh(); status.acquire(); boxSlots = HubActionSlotID.slots()
            if !tabs.contains(selectedTab), let first = tabs.first { selectedTab = first }
        }
        .onDisappear { status.release() }
        .task {
            let all = await BluetoothDeviceReader.read()
            btAudioDevices = all.filter { $0.isConnected && $0.lowestBattery != nil }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(tabs) { tab in
                    let active = selectedTab == tab
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.8)) { selectedTab = tab }
                    } label: {
                        Image(systemName: tab.symbolName).font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(active ? Color.white : inkSoft).frame(width: 28, height: 24)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(active ? AnyShapeStyle(palette.pillGradient) : AnyShapeStyle(Color.clear)))
                    }.buttonStyle(.plain)
                }
            }
            .padding(2).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(cardFill))

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(inkSoft)
                TextField(String(localized: "Search"), text: $query).textFieldStyle(.plain).font(.system(size: 11)).foregroundStyle(ink)
            }
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(cardFill))

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape").font(.system(size: 12, weight: .medium)).foregroundStyle(inkSoft)
                    .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(cardFill))
            }.buttonStyle(.plain).help(Text("Open Settings…"))
        }
    }

    private var actionBoxGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(Array(boxSlots.enumerated()), id: \.offset) { index, slot in boxTile(slot: slot, index: index) }
        }
    }

    private func boxTile(slot: HubActionSlotID, index: Int) -> some View {
        let on = boxState(slot)
        return Button { performBox(slot) } label: {
            HStack(spacing: 8) {
                Image(systemName: boxSymbol(slot)).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(on ? Color.white : ink).frame(width: 28, height: 28)
                    .background(Circle().fill(on ? AnyShapeStyle(palette.pillGradient) : AnyShapeStyle(cardFill)))
                VStack(alignment: .leading, spacing: 1) {
                    boxTitle(slot).font(.system(size: 11, weight: .semibold)).foregroundStyle(ink).lineLimit(1)
                    Text(on ? String(localized: "On") : String(localized: "Off")).font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(on ? palette.primaryAccent : inkSoft)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? palette.primaryAccent.opacity(0.16) : cardFill))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? palette.primaryAccent.opacity(0.45) : cardStroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.72), value: on)
        .contextMenu {
            ForEach(HubActionSlotID.allCases) { candidate in
                Button {
                    var next = boxSlots; next[index] = candidate; boxSlots = next
                    UserDefaults.standard.set(HubActionSlotID.serialize(next), forKey: HubActionSlotID.defaultsKey)
                } label: { boxTitle(candidate) }
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .switches: switchesBody
        case .statusAudio: statusAudioBody
        default:
            Text(verbatim: selectedTab.rawValue).font(.caption).foregroundStyle(inkSoft)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var switchesBody: some View {
        let items = HubSwitchCatalog.filter(HubSwitchCatalog.orderedSwitches(), query: query) { switchLabel($0) }
        return ScrollView {
            VStack(spacing: 6) {
                if let buds = btAudioDevices.first, let level = buds.lowestBattery {
                    airPodsPill(device: buds, battery: level)
                }
                ForEach(items) { item in switchRow(item) }
            }
        }
    }

    private func airPodsPill(device: BluetoothDevice, battery: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: device.symbolName).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.primaryAccent)
                Text(verbatim: device.name).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(ink).lineLimit(1)
                Spacer()
                Text(verbatim: "\(battery)%").font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(battery <= 20 ? Color.red : ink)
            }
            if AudioOutputSwitcher.canSetBluetoothListeningMode() {
                HStack(spacing: 4) {
                    ForEach(BluetoothListeningMode.allCases) { mode in
                        let active = listeningMode == mode.rawValue
                        Button {
                            if AudioOutputSwitcher.setBluetoothListeningMode(mode.rawValue) { listeningMode = mode.rawValue }
                        } label: {
                            Image(systemName: mode.symbolName).font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(active ? Color.white : inkSoft).frame(maxWidth: .infinity, minHeight: 22)
                                .background(Capsule().fill(active ? AnyShapeStyle(palette.pillGradient) : AnyShapeStyle(cardFill)))
                        }.buttonStyle(.plain).help(Text(verbatim: mode.title))
                    }
                }
            }
        }
        .padding(9).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardFill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(cardStroke, lineWidth: 1))
    }

    private func switchRow(_ item: HubSwitchID) -> some View {
        let on = switchState(item)
        return HStack(spacing: 9) {
            Image(systemName: switchSymbol(item)).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(on ? palette.primaryAccent : inkSoft).frame(width: 22)
            Text(verbatim: switchLabel(item)).font(.system(size: 12, weight: .medium)).foregroundStyle(ink).lineLimit(1)
            Spacer()
            if case .system(let q) = item, q.isAction {
                Button { engine.perform(q) } label: {
                    Image(systemName: engine.flash == q ? "checkmark" : "play.fill").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ink).padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(cardFill))
                }.buttonStyle(.plain)
            } else {
                Toggle(isOn: Binding(get: { on }, set: { toggleSwitch(item, to: $0) })) { EmptyView() }
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(cardFill))
    }

    private var statusAudioBody: some View {
        let bat = status.status.battery
        let wifi = status.status.wifi
        let vol = status.status.volume
        let outputs = AudioOutputSwitcher.devices(input: false)
        return ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    telemetryCard(symbol: bat.symbolName, title: String(localized: "Battery"),
                                  value: bat.level.map { "\($0)%" } ?? "–",
                                  detail: bat.facts.summary ?? (bat.isCharging ? String(localized: "Charging") : String(localized: "On Battery")))
                    telemetryCard(symbol: wifi.symbolName, title: String(localized: "Network"),
                                  value: status.status.wiredEthernetConnected ? String(localized: "Network") : (wifi.ssid ?? (wifi.isConnected ? String(localized: "On") : String(localized: "Offline"))),
                                  detail: wifi.rssi.map { "\($0) dBm" } ?? (wifi.isPoweredOn ? String(localized: "Not Connected") : String(localized: "Wi-Fi Off")))
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Audio Output").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(ink)
                        Spacer()
                        Button { _ = status.toggleMute() } label: {
                            Image(systemName: vol.symbolName).font(.system(size: 11)).foregroundStyle(vol.isMuted ? Color.red : inkSoft)
                        }.buttonStyle(.plain)
                    }
                    ForEach(outputs) { dev in
                        Button { _ = AudioOutputSwitcher.setDefault(dev.id, input: false); surfaceVersion += 1 } label: {
                            HStack(spacing: 6) {
                                Image(systemName: dev.isDefault ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 10.5)).foregroundStyle(dev.isDefault ? palette.primaryAccent : inkSoft)
                                Text(verbatim: dev.name).font(.system(size: 11)).foregroundStyle(ink).lineLimit(1)
                                Spacer()
                            }
                        }.buttonStyle(.plain)
                    }
                    hubSlider(icon: vol.symbolName, value: Binding(get: { Double(vol.level) }, set: { _ = status.setVolume(Float($0)) }))
                    if let brightness {
                        hubSlider(icon: "sun.max.fill", value: Binding(get: { brightness }, set: { self.brightness = $0; DisplayServicesBrightness.set($0) }))
                    }
                    if let keyLight {
                        hubSlider(icon: "keyboard", value: Binding(get: { keyLight }, set: { self.keyLight = $0; KeyboardBacklight.set($0) }))
                    }
                }
                .padding(9).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardFill))
                if !btAudioDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(btAudioDevices) { dev in
                            HStack(spacing: 6) {
                                Image(systemName: dev.symbolName).font(.system(size: 11)).foregroundStyle(inkSoft).frame(width: 16)
                                Text(verbatim: dev.name).font(.system(size: 11)).foregroundStyle(ink).lineLimit(1)
                                Spacer()
                                if let lvl = dev.lowestBattery {
                                    Text(verbatim: "\(lvl)%").font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
                                        .foregroundStyle(lvl <= 20 ? Color.red : inkSoft)
                                }
                            }
                        }
                    }
                    .padding(9).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardFill))
                }
            }
        }
    }

    private func telemetryCard(symbol: String, title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(palette.primaryAccent)
                Text(verbatim: title).font(.system(size: 10.5, weight: .medium)).foregroundStyle(inkSoft)
            }
            Text(verbatim: value).font(.system(size: 14, weight: .bold)).monospacedDigit().foregroundStyle(ink).lineLimit(1)
            Text(verbatim: detail).font(.system(size: 9.5)).foregroundStyle(inkSoft).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardFill))
    }

    private func hubSlider(icon: String, value: Binding<Double>) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(inkSoft).frame(width: 16)
            Slider(value: value, in: 0...1).controlSize(.small).tint(palette.primaryAccent)
            Text(verbatim: "\(Int((value.wrappedValue * 100).rounded()))").font(.system(size: 10)).monospacedDigit()
                .foregroundStyle(inkSoft).frame(width: 24, alignment: .trailing)
        }
    }

    // MARK: - Helpers

    private func boxState(_ slot: HubActionSlotID) -> Bool {
        _ = surfaceVersion
        if slot == .muteOutput { return status.status.volume.isMuted }
        if slot == .notchToggle { return UserDefaults.standard.bool(forKey: "com.katikati.liveIsland.notch") }
        return QuickToggleID(rawValue: slot.rawValue).flatMap { engine.states[$0] } ?? false
    }

    private func performBox(_ slot: HubActionSlotID) {
        if slot == .captureOCR { onDismiss(); BarActionService.run(.ocr); return }
        if slot == .notchToggle {
            let next = !(AppDelegate.shared?.settingsStore.notchIslandEnabled ?? UserDefaults.standard.bool(forKey: "com.katikati.liveIsland.notch"))
            HubScheduleCoordinator.applySurface(.notch, enabled: next)
            surfaceVersion += 1
            return
        }
        if slot == .muteOutput { _ = status.toggleMute(); return }
        if slot == .lockScreen { onDismiss() }
        if let q = QuickToggleID(rawValue: slot.rawValue) { engine.perform(q) }
    }

    private func boxSymbol(_ slot: HubActionSlotID) -> String {
        if slot == .captureOCR { return "text.viewfinder" }
        if slot == .notchToggle { return KatiKatiSurfaceToggle.notch.symbolName }
        return QuickToggleID(rawValue: slot.rawValue)?.symbolName ?? "bolt.fill"
    }

    private func boxTitle(_ slot: HubActionSlotID) -> Text {
        if slot == .captureOCR { return Text("Capture Area") }
        if slot == .notchToggle { return Text("Notch") }
        return QuickToggleID(rawValue: slot.rawValue)?.title ?? Text(verbatim: slot.rawValue)
    }

    private func switchState(_ id: HubSwitchID) -> Bool {
        _ = surfaceVersion
        switch id {
        case .system(let q): return q == .muteOutput ? status.status.volume.isMuted : (engine.states[q] ?? false)
        case .surface(let s):
            let d = UserDefaults.standard
            switch s {
            case .notch: return AppDelegate.shared?.settingsStore.notchIslandEnabled ?? d.bool(forKey: "com.katikati.liveIsland.notch")
            case .desktopBoxes: return DesktopCanvasConfig.isFeatureEnabled()
            case .nowPlaying: return d.object(forKey: MusicSurfaceConfig.enabledKey) as? Bool ?? true
            case .lockScreenCard: return d.bool(forKey: MusicSurfaceConfig.lockScreenCardKey)
            case .metricsBar: return d.bool(forKey: MenuBarStatModel.masterEnabledKey)
            }
        case .shortcut, .evolution: return false
        }
    }

    private func toggleSwitch(_ id: HubSwitchID, to on: Bool) {
        switch id {
        case .system(let q): if q == .muteOutput { _ = status.toggleMute() } else { engine.perform(q) }
        case .surface(let s): HubScheduleCoordinator.applySurface(s, enabled: on); surfaceVersion += 1
        case .shortcut, .evolution: break
        }
    }

    private func switchSymbol(_ id: HubSwitchID) -> String {
        switch id {
        case .system(let q): return q.symbolName
        case .surface(let s): return s.symbolName
        case .shortcut: return "bolt.fill"
        case .evolution: return "terminal"
        }
    }

    private func switchLabel(_ id: HubSwitchID) -> String {
        switch id {
        case .system(let q): return q.localizedLabel
        case .surface(let s):
            switch s {
            case .notch: return String(localized: "Notch")
            case .desktopBoxes: return String(localized: "Desktop")
            case .nowPlaying: return String(localized: "Now Playing")
            case .lockScreenCard: return String(localized: "Lock Screen")
            case .metricsBar: return String(localized: "Menu Bar")
            }
        case .shortcut(let name): return name
        case .evolution(let uuid): return uuid.uuidString
        }
    }
}
