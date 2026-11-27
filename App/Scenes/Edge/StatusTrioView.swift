import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
    @AppStorage(PeripheralWidgetPrefs.orderKey) private var orderRaw = "[]"
    @AppStorage(PeripheralWidgetPrefs.hiddenKey) private var hiddenRaw = "[]"
    @AppStorage(PeripheralWidgetPrefs.pinnedKey) private var pinnedID = ""

    static let size = CGSize(width: 300, height: 260)

    private var orderedDevices: [BluetoothDevice] {
        PeripheralWidgetPrefs.arranged(
            devices: devices,
            order: PeripheralWidgetPrefs.decodeIDs(orderRaw),
            hiddenIDs: Set(PeripheralWidgetPrefs.decodeIDs(hiddenRaw)),
            pinnedID: pinnedID,
            includeHidden: true
        )
    }

    var body: some View {
        let hiddenSet = Set(PeripheralWidgetPrefs.decodeIDs(hiddenRaw).map { $0.lowercased() })
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Bluetooth").font(.headline)
                Spacer()
                if loading { ProgressView().controlSize(.small) }
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help(Text("Refresh"))
            }
            if orderedDevices.isEmpty && !loading {
                Text("No Bluetooth Devices").foregroundStyle(.secondary).font(.callout)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(orderedDevices) { device in
                            row(device, hidden: hiddenSet.contains(device.id.lowercased()))
                        }
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

    private func row(_ d: BluetoothDevice, hidden: Bool) -> some View {
        let isPinned = !pinnedID.isEmpty && pinnedID.caseInsensitiveCompare(d.id) == .orderedSame
        return HStack(spacing: 8) {
            Image(systemName: d.richSymbolName).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: d.name).lineLimit(1)
                if let breakdown = d.batteryBreakdown {
                    Text(verbatim: breakdown).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Spacer(minLength: 4)
            if d.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.green)
            }
            if let level = d.lowestBattery {
                Text(verbatim: "\(level)%").monospacedDigit().foregroundStyle(d.isCharging ? Color.green : (level <= 20 ? Color.red : Color.secondary))
            }
            Button {
                pinnedID = isPinned ? "" : d.id
            } label: {
                Image(systemName: isPinned ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(isPinned ? Color.yellow : Color.secondary.opacity(0.6))
            }
            .buttonStyle(.borderless)
            Circle().fill(d.isConnected ? Color.green : Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
        }
        .opacity((d.isConnected && !hidden) ? 1 : 0.5)
    }

    @MainActor private func load() async {
        loading = true
        await DockDevicesFeed.shared.refreshIfStale(maxAge: 2)
        devices = DockDevicesFeed.shared.allDevices
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
/// The Bluetooth rune, drawn rather than borrowed: macOS ships no Bluetooth SF Symbol, and one
/// vector mark keeps the tile, the grid cell and the Dock widget telling the same story.
struct BluetoothRune: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.minX, y = rect.minY
        let side = min(rect.width, rect.height)
        var p = Path()
        for stroke in BluetoothRuneGeometry.points(in: side) {
            guard let first = stroke.first else { continue }
            p.move(to: CGPoint(x: x + first.x, y: y + first.y))
            for point in stroke.dropFirst() { p.addLine(to: CGPoint(x: x + point.x, y: y + point.y)) }
        }
        return p
    }
}

/// One rune at any optical size; the stroke scales with the square so a 12 pt Dock mark and a
/// 32 pt tile mark stay equally legible.
struct BluetoothGlyph: View {
    var side: CGFloat = 16
    var color: Color = .primary

    var body: some View {
        BluetoothRune()
            .stroke(color, style: StrokeStyle(lineWidth: BluetoothRuneGeometry.lineWidth(for: side),
                                             lineCap: .round, lineJoin: .round))
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

/// The edge deck's second job once Control Centre moves to the menu bar: a compact list of the
/// apps running without a window, reading the same store the drawer tab uses.
struct BackgroundActivityDeckView: View {
    @ObservedObject private var store = BackgroundAppsStore.shared
    @Environment(\.dockThemeStyle) private var dockThemeStyle
    @Environment(\.colorScheme) private var colorScheme

    private var theme: DockThemeTokens { .resolved(for: colorScheme, style: dockThemeStyle) }
    private var palette: SettingsIridescentPalette { .resolve(style: dockThemeStyle, colorScheme: colorScheme) }
    private var ink: Color { theme.labelActive.color }
    private var inkSoft: Color { theme.labelSubtitle.color }

    /// What a person would call their own background activity: `BackgroundActivity` drops the OS
    /// machinery and nested helpers, so this list never shows loginwindow or WindowManager.
    private var items: [BackgroundActivity.Item] {
        BackgroundActivity.visible(store.facts
            .filter { !store.ignored.contains($0.bundleID) }
            .map { BackgroundActivity.Item(
                bundleID: $0.bundleID,
                name: AppDisplayNameResolver.displayName(for: $0.bundleID),
                policy: $0.policy,
                isHelper: $0.isHelper) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(inkSoft)
                Text("Background Apps").font(.system(size: 13, weight: .semibold)).foregroundStyle(ink)
                Spacer(minLength: 6)
                if !items.isEmpty { countBadge }
            }
            if items.isEmpty {
                Text("None").font(.system(size: 11)).foregroundStyle(inkSoft)
            } else {
                ForEach(items, id: \.bundleID) { item in row(item) }
            }
            Spacer(minLength: 0)
            if !store.ignored.isEmpty { hiddenBar }
            homeBar
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The visible way out, right on the deck that took the new job: what happened, and one click
    /// back to the standalone Control Centre. The alert on the switch is the first telling; this is
    /// the one that stays until the owner decides.
    private var homeBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(inkSoft)
            Text("Control Centre is now in the Menu Bar")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(inkSoft)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button { useEdgeInstead() } label: {
                Text("Use Edge Instead")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.09)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(Text("Use Edge Instead"))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.primary.opacity(0.045)))
    }

    /// Hiding a row writes the same ignore list the drawer uses; it is a preference, not a
    /// deletion. This keeps the way back on the deck that did the hiding, and Settings › Behavior
    /// carries the same reset.
    private var hiddenBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(inkSoft)
            Text(verbatim: "\(store.ignored.count)")
                .font(.system(size: 10, weight: .semibold)).monospacedDigit().foregroundStyle(inkSoft)
            Spacer(minLength: 4)
            Button { store.unignoreAll() } label: {
                Text("Show Hidden Apps")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(Text("Show Hidden Apps"))
        }
        .padding(.horizontal, 5)
    }

    private func useEdgeInstead() {
        UserDefaults.standard.set(ControlCenterSurfaceMode.edge.rawValue,
                                  forKey: ControlCenterSurfaceMode.storageKey)
        NotificationCenter.default.post(name: .controlCenterSurfaceDidChange, object: nil)
        // The notification closes this deck; reopen in place as the Control Centre grid so the undo
        // is something the owner sees, not just a preference that changed underneath them.
        DispatchQueue.main.async { AppDelegate.shared?.toggleControlCenter() }
    }

    private var countBadge: some View {
        Text(verbatim: "\(items.count)")
            .font(.system(size: 10, weight: .semibold)).monospacedDigit()
            .foregroundStyle(inkSoft)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
    }

    private func row(_ item: BackgroundActivity.Item) -> some View {
        HStack(spacing: 10) {
            iconTile(item)
            Text(verbatim: item.name)
                .font(.system(size: 12, weight: .medium)).foregroundStyle(ink).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.primary.opacity(0.055)))
        .nativeContextMenu { menu(for: item) }
    }

    /// Row right-click, in the shared menu grammar: the app's icon and name, Open / Show / Quit
    /// tiles, then the same actions as rows plus hiding the app from this deck.
    private func menu(for item: BackgroundActivity.Item) -> NSMenu {
        let nsMenu = NSMenu()
        let appIcon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        nsMenu.addItem(DockMenuChrome.header(
            icon: appIcon,
            title: item.name,
            status: nil,
            tiles: [
                .init(symbol: "arrow.up.forward.app", caption: String(localized: "Open")) { activate(item) },
                .init(symbol: "eye", caption: String(localized: "Show")) { show(item) },
                .init(symbol: "power", caption: String(localized: "Quit App")) { quit(item) },
            ],
            menu: nsMenu
        ))
        nsMenu.addItem(.separator())
        MenuChrome.action(String(localized: "Open"), symbol: "arrow.up.forward.app", in: nsMenu) { activate(item) }
        MenuChrome.action(String(localized: "Show"), symbol: "eye", in: nsMenu) { show(item) }
        MenuChrome.action(String(localized: "Quit App"), symbol: "power", in: nsMenu) { quit(item) }
        nsMenu.addItem(.separator())
        MenuChrome.action(String(localized: "Hide from Background Apps"), symbol: "eye.slash", in: nsMenu) {
            store.ignore(item.bundleID)
        }
        return nsMenu
    }

    private func runningApp(_ item: BackgroundActivity.Item) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: item.bundleID).first
    }

    private func activate(_ item: BackgroundActivity.Item) {
        guard let app = runningApp(item) else { launch(item); return }
        if app.isHidden { _ = app.unhide() }
        if !app.activate(options: [.activateIgnoringOtherApps]) { launch(item) }
    }

    private func show(_ item: BackgroundActivity.Item) {
        guard let app = runningApp(item) else { launch(item); return }
        _ = app.unhide()
        if !app.activate(options: [.activateIgnoringOtherApps]) { launch(item) }
    }

    /// A windowless agent can refuse `activate` because it has nothing to raise. Opening the
    /// bundle through LaunchServices reaches it either way, and for a hidden regular app it is
    /// also what brings the window back.
    private func launch(_ item: BackgroundActivity.Item) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func quit(_ item: BackgroundActivity.Item) {
        runningApp(item)?.terminate()
    }

    /// A real bundle icon when the app resolves one; otherwise a monogram in the panel's accent
    /// gradient, so no row is ever a bare white placeholder.
    @ViewBuilder
    private func iconTile(_ item: BackgroundActivity.Item) -> some View {
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        if let icon, !icon.representations.isEmpty, !icon.isTemplate {
            Image(nsImage: icon).resizable().interpolation(.high)
                .frame(width: 26, height: 26)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [palette.primaryAccent.opacity(0.85),
                                                  palette.secondaryAccent.opacity(0.75)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(verbatim: BackgroundActivity.monogram(for: item.name, bundleID: item.bundleID))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 26, height: 26)
        }
    }
}

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
    @State private var brightness: Double? = DisplayBrightness.levelForCursorScreen()
    /// MD-5: the external panel's own volume; nil when it does not answer VCP `0x62` (row hidden).
    @State private var displayVolume: Double?
    @State private var keyLight: Double? = KeyboardBacklight.isAvailable ? KeyboardBacklight.current() : nil
    /// 57a: wheel travel left over between events on the volume row.
    @State private var volumeScroll = ControlCenterScroll.State()
    /// Connected Bluetooth devices that report a battery. Read once per open and on demand — the read
    /// shells out to `system_profiler`, so it is never polled.
    @State private var peripherals: [BluetoothDevice] = []
    @State private var peripheralsLoading = true
    /// `CC-4` edit mode: while on, a card can be dragged in front of another. It is a local state, not
    /// a stored preference — the panel's Esc / outside-click behaviour is unchanged.
    @State private var editing = false
    @State private var dragging: ControlCenterTileID?
    /// The layout the last drop produced, so the cards move now instead of on the next open.
    @State private var editedLayout: ControlCenterLayoutSpec?

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
    /// The bar's subtitle tint, floored: this panel's copy sits on a translucent card over the
    /// wallpaper, where the bar's value reads as a smudge.
    private var inkSoft: Color {
        theme.labelSubtitle.withMinimumOpacity(ControlCenterReadability.minimumSecondaryAlpha).color
    }

    private var connectivity: [QuickToggleID] { [.wifi, .bluetooth] }
    private var quickActions: [QuickToggleID] { order.filter { !connectivity.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionGap) {
            ForEach(Array(packedSections.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: Metrics.sectionGap) {
                    ForEach(row.tiles, id: \.id) { tile in
                        packedTile(tile).frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(Metrics.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(plateWash)
        .overlay(plateRim)
        .onAppear { engine.refresh(); status.acquire() }
        .onDisappear { status.release() }
        .task {
            await refreshPeripherals()
            // DDC read once per open, off the view build so the popover never waits on I2C.
            displayVolume = DisplayBrightness.volumeForCursorScreen()
        }
    }

    // MARK: - Preset layout

    private var storedPreset: ControlCenterPreset {
        ControlCenterPreset.parse(UserDefaults.standard.string(forKey: ControlCenterPreset.storageKey))
    }

    /// A Custom layout only wins when it decodes; otherwise the preset renders, so a truncated
    /// preferences value can never empty the panel.
    private var layoutSpec: ControlCenterLayoutSpec {
        let preset = storedPreset
        // An edit made in this open wins over what was read at open, so the drop is visible at once.
        if let editedLayout { return editedLayout }
        if preset == .custom,
           let stored = ControlCenterLayoutCodec.decode(UserDefaults.standard.string(forKey: ControlCenterLayoutCodec.storageKey)),
           stored.preset == .custom {
            return stored
        }
        return .preset(preset == .custom ? .classic : preset)
    }

    /// `CC-4`: a card is a drag source only in edit mode, so a normal click never starts a drag.
    @ViewBuilder
    private func packedTile(_ tile: ControlCenterTileSpec) -> some View {
        if editing {
            sectionView(tile.id)
                .opacity(dragging == tile.id ? 0.4 : 1)
                .onDrag {
                    dragging = tile.id
                    return NSItemProvider(object: tile.id.token as NSString)
                }
                .onDrop(of: [.utf8PlainText], delegate: ControlCenterDropDelegate(
                    target: tile.id, dragging: $dragging, move: performMove))
        } else {
            sectionView(tile.id)
        }
    }

    /// Writes the drop as a Custom layout. `ControlCenterLayoutCodec.store` sets both the layout and
    /// the preset, so a relaunch reopens in Custom at the order the user just made.
    private func performMove(_ moving: ControlCenterTileID, before target: ControlCenterTileID) {
        guard let next = layoutSpec.move(moving, before: target) else { return }
        ControlCenterLayoutCodec.store(next)
        editedLayout = next
    }

    private var panelWidth: CGFloat {
        ControlCenterSize.parse(UserDefaults.standard.string(forKey: ControlCenterSize.storageKey)).width
    }

    /// Section cards speak the packer's columns: a standard section shares its row, wider ones take
    /// the full width. Below 400 pt every row becomes one column.
    private var packedSections: [ControlCenterPackedRow] {
        let columns = ControlCenterPacker.columns(width: panelWidth)
        let tiles = layoutSpec.tiles.map { tile -> ControlCenterTileSpec in
            tile.size == .standard
                ? ControlCenterTileSpec(id: tile.id, size: .wide)
                : ControlCenterTileSpec(id: tile.id, size: .hero)
        }
        return ControlCenterPacker.rows(tiles, columns: columns)
    }

    private var dedupeOptions: ControlCenterDedupeOptions { .stored() }

    /// Music surfaces that already show a now-playing card. The notch wins over the dock widget,
    /// but either one is enough to suppress this panel's card.
    private var musicSurfaces: Set<ControlCenterMusicSurface> {
        let defaults = UserDefaults.standard
        var surfaces: Set<ControlCenterMusicSurface> = []
        if defaults.object(forKey: "com.katikati.liveIsland.notch") as? Bool ?? false { surfaces.insert(.notch) }
        if defaults.object(forKey: "com.katikati.music.widgetEnabled") as? Bool ?? false { surfaces.insert(.dock) }
        return surfaces
    }

    private var hidesNowPlaying: Bool {
        ControlCenterDedupe.hidesNowPlaying(surfacesOn: musicSurfaces, options: dedupeOptions)
    }

    private var hidesSystemRow: Bool {
        ControlCenterDedupe.hidesSystemRow(hasBatteryPill: true, options: dedupeOptions)
    }

    @ViewBuilder
    private func sectionView(_ id: ControlCenterTileID) -> some View {
        switch id {
        case .section(let section):
            switch section {
            case .header:
                header
            case .peripherals:
                if widgetTiles.contains(.battery) || widgetTiles.contains(.batteries) { peripheralsCard }
            case .connectivity:
                HStack(spacing: 8) {
                    ForEach(connectivity, id: \.self) { id in connectivityCard(id) }
                }
            case .nowPlaying:
                // The switch grid rides with now-playing, so Classic keeps its pre-preset order
                // (now-playing, grid, network) and the grid survives dedupe hiding the card.
                VStack(alignment: .leading, spacing: Metrics.sectionGap) {
                    if !hidesNowPlaying { nowPlayingCard }
                    switchGrid
                }
            case .network:
                if widgetTiles.contains(.network) { card(padding: 9, label: Text("Network")) { ControlCenterNetworkRow() } }
            case .sliders:
                sliderRows
            case .utilities:
                utilityRow
            case .account:
                card(padding: 8, label: Text("Manage accounts")) { ControlCenterAccountRow() }
            }
        case .toggle:
            EmptyView()
        }
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

    /// The Finish row tunes the card wash only; the dock theme's colours stay untouched.
    private var cardFill: AnyShapeStyle {
        let alpha = ControlCenterReadability.cardAlpha(for: ControlCenterGlassStyle.parse(
            UserDefaults.standard.string(forKey: ControlCenterGlassStyle.storageKey)))
        if isPad { return AnyShapeStyle(Color.white.opacity(colorScheme == .dark ? alpha + 0.02 : 0.55)) }
        return AnyShapeStyle(LinearGradient(colors: [Color.primary.opacity(colorScheme == .dark ? alpha : alpha * 0.75),
                                              palette.cardTintBottom],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var activeFill: AnyShapeStyle {
        AnyShapeStyle(LinearGradient(colors: [palette.primaryAccent.opacity(0.30), palette.secondaryAccent.opacity(0.13)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    /// `label` names the card for VoiceOver, so a card reads as one group ("System & Peripherals,
    /// group") instead of a run of loose buttons. Cards whose own heading already says the name keep
    /// that heading out of the tree, so the name is never read twice.
    private func card<Content: View>(active: Bool = false, padding: CGFloat = Metrics.cardPadding,
                                     label: Text? = nil,
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
            .accessibilityElement(children: .contain)
            .modifier(ControlCenterCardLabel(label: label))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 7) {
            Text("Quick Settings")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(ink)
            clockPill
            Spacer(minLength: 4)
            editPill
            batteryPill
        }
        .padding(.horizontal, 1)
    }

    /// `CC-4` toolbar pill: the only way in and out of edit mode, so a drag is never accidental.
    private var editPill: some View {
        Button {
            editing.toggle()
            if !editing { editedLayout = nil }
            dragging = nil
        } label: {
            Text(editing ? "Done" : "Edit")
                .font(.system(size: ControlCenterReadability.captionSize, weight: .semibold))
                .foregroundStyle(editing ? Color.white : ink)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(editing ? AnyShapeStyle(palette.pillGradient)
                                                  : AnyShapeStyle(Color.primary.opacity(0.08))))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(Text(editing ? "Done" : "Edit"))
        .accessibilityLabel(Text(editing ? "Done" : "Edit"))
    }

    private var clockPill: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(verbatim: Self.clockFormatter.string(from: context.date))
                .font(.system(size: ControlCenterReadability.captionSize, weight: .medium))
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
        // One reading, not an image description followed by a loose number.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Battery"))
        .accessibilityValue(Text(verbatim: battery.level.map { "\($0)%" } ?? "–"))
    }

    // MARK: - System & peripherals

    @ViewBuilder
    private var peripheralsCard: some View {
        // Single battery readout: the header pill keeps the number, so the redundant row goes.
        let showsThisMac = widgetTiles.contains(.battery) && !hidesSystemRow
        let showsDevices = widgetTiles.contains(.batteries)
        if showsThisMac || showsDevices {
            card(label: Text("System & Peripherals")) {
                VStack(alignment: .leading, spacing: Metrics.rowGap) {
                    HStack(spacing: 6) {
                        Text("System & Peripherals")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(ink)
                            // The card's own group label already says this.
                            .accessibilityHidden(true)
                        if status.status.battery.isCharging {
                            Text("Charging")
                                .font(.system(size: ControlCenterReadability.detailSize, weight: .semibold))
                                .foregroundStyle(Color.green)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.green.opacity(0.14)))
                        }
                        // 59e: the OS's own power saving, shown where the reading is.
                        if status.status.battery.facts.isLowPowerMode {
                            Text("Low Power")
                                .font(.system(size: ControlCenterReadability.detailSize, weight: .semibold))
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
                                    .font(.system(size: ControlCenterReadability.captionSize))
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
                        .font(.system(size: ControlCenterReadability.detailSize))
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

    @ViewBuilder
    private func accentIcon(symbol: String, on: Bool, size: CGFloat = 32, rune: Bool = false) -> some View {
        Group {
            if rune {
                BluetoothGlyph(side: size * 0.52, color: on ? .white : inkSoft)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(on ? Color.white : inkSoft)
            }
        }
            .frame(width: size, height: size)
            .background(Circle().fill(on ? AnyShapeStyle(palette.pillGradient)
                                          : AnyShapeStyle(Color.primary.opacity(0.09))))
            .overlay(Circle().strokeBorder(on ? Color.white.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 1))
            .shadow(color: on ? palette.glowColor : .clear, radius: 6, y: 2)
    }

    // MARK: - Wi-Fi / Bluetooth

    private func connectivityCard(_ id: QuickToggleID) -> some View {
        let on = engine.states[id] ?? false
        return card(active: on, padding: 0, label: id.title) {
            ZStack(alignment: .topTrailing) {
                Button { engine.perform(id) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        accentIcon(symbol: id.symbolName, on: on, rune: id == .bluetooth)
                        VStack(alignment: .leading, spacing: 1) {
                            id.title
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(ink)
                                .lineLimit(1)
                            Text(verbatim: connectivityDetail(id, on: on))
                                .font(.system(size: ControlCenterReadability.captionSize))
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
        return card(padding: 9, label: Text("Now Playing")) {
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

    /// The grid's 18 pt mark, with the rune where a symbol does not exist.
    @ViewBuilder
    private func gridGlyph(_ id: QuickToggleID, active: Bool) -> some View {
        if engine.flash == id {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? Color.white : ink)
        } else if id == .bluetooth {
            BluetoothGlyph(side: 18, color: active ? .white : ink)
        } else {
            Image(systemName: id.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? Color.white : ink)
        }
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
                gridGlyph(id, active: on || armed)
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
                    .font(.system(size: ControlCenterReadability.captionSize, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(ControlCenterReadability.minimumLabelScale)
                    // A toggle's name is the panel's primary copy, not a subtitle.
                    .foregroundStyle(ink)
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
        // A switch has to say whether it is on, not just look different.
        .accessibilityValue(Text(on ? "On" : "Off"))
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
                sliderRow(icon: "sun.max.fill", label: Text("Brightness"),
                          value: Binding(get: { brightness }, set: { self.brightness = $0; DisplayBrightness.setOnCursorScreen($0) }))
            }
            if let displayVolume {
                sliderRow(icon: "speaker.wave.2.fill", label: Text("Display Volume"),
                          value: Binding(get: { displayVolume }, set: { self.displayVolume = $0; DisplayBrightness.setVolumeOnCursorScreen($0) }))
            }
            if let keyLight {
                sliderRow(icon: "keyboard", label: Text("Keyboard"),
                          value: Binding(get: { keyLight }, set: { self.keyLight = $0; KeyboardBacklight.set($0) }))
            }
        }
    }

    private var volumeRow: some View {
        let volume = status.status.volume
        return sliderRow(icon: volume.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                         label: Text("Volume"),
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
    /// The label rides inside the capsule (the classic skin puts it above the card). This panel has
    /// two speaker rows — system volume and the external display's own volume — so without the text
    /// they are indistinguishable both to the eye and to VoiceOver.
    private func padSliderRow(icon: String, label: Text? = nil, value: Binding<Double>) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [palette.primaryAccent, palette.secondaryAccent],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(44, proxy.size.width * CGFloat(value.wrappedValue)))
                HStack(spacing: 6) {
                    Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                    if let label {
                        label.font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    Spacer(minLength: 4)
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
        .accessibilityLabel(label ?? Text(verbatim: ""))
        .accessibilityValue(Text(verbatim: "\(Int((value.wrappedValue * 100).rounded()))"))
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 0.05 : -0.05
            value.wrappedValue = min(1, max(0, value.wrappedValue + step))
        }
    }

    private func sliderRow(icon: String, label: Text? = nil, value: Binding<Double>) -> some View {
        if isPad { return AnyView(padSliderRow(icon: icon, label: label, value: value)) }
        return AnyView(sliderRowClassic(icon: icon, label: label, value: value))
    }

    /// Classic skin: the row's name is drawn in the leading column, next to its glyph. This panel has
    /// two speaker rows (system volume and the external display's own volume) and the value numbers
    /// alone never say which is which, so the name is part of the drawing, not only of the AX tree —
    /// `card(label:)` names the group for VoiceOver, which is invisible on screen.
    private func sliderRowClassic(icon: String, label: Text? = nil, value: Binding<Double>) -> some View {
        card(padding: 8, label: label) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(inkSoft)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                if let label {
                    label.font(.system(size: 11, weight: .medium))
                        .foregroundStyle(inkSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: 84, alignment: .leading)
                        .accessibilityHidden(true)
                }
                Slider(value: value, in: 0...1)
                    .controlSize(.small)
                    .tint(palette.primaryAccent)
                Text(verbatim: "\(Int((value.wrappedValue * 100).rounded()))")
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(inkSoft)
                    .frame(width: 26, alignment: .trailing)
                    .accessibilityHidden(true)
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
                    .font(.system(size: ControlCenterReadability.detailSize, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(ControlCenterReadability.minimumLabelScale)
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
        await DockDevicesFeed.shared.refreshIfStale(maxAge: 5)
        peripherals = Array(DockDevicesFeed.shared.devices.filter { $0.lowestBattery != nil }.prefix(4))
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
                // The card's own group label already says this.
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Image(systemName: "arrow.down").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            Text(verbatim: SystemMonitorFormat.bytes(snapshot.down) + "/s").font(.system(size: 11.5)).monospacedDigit()
            Image(systemName: "arrow.up").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            Text(verbatim: SystemMonitorFormat.bytes(snapshot.up) + "/s").font(.system(size: 11.5)).monospacedDigit()
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
                    Text("Manage accounts").font(.system(size: ControlCenterReadability.captionSize))
                        .foregroundStyle(Color.primary.opacity(ControlCenterReadability.minimumSecondaryAlpha))
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
            toggleBtn(icon: "wave.3.forward", active: bluetoothOn, rune: true) { bluetoothOn.toggle() }
            toggleBtn(icon: micMuted ? "mic.slash.fill" : "mic.fill", active: !micMuted) { micMuted.toggle() }
            toggleBtn(icon: "moon.fill", active: dndOn) { dndOn.toggle() }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }

    private func toggleBtn(icon: String, active: Bool, rune: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if rune {
                    BluetoothGlyph(side: 11, color: active ? .blue : .secondary)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(active ? .blue : .secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - MB-6: Menu Bar Creative Hub (Hop 2x2 Box Grid + OnlySwitch Tabs)

struct MenuBarCreativeHubView: View {
    var onDismiss: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    /// Pointer tip, in points from the panel's leading edge; the controller passes the icon centre.
    var caretX: CGFloat = 190

    static let panelWidth: CGFloat = 380
    static let panelHeight: CGFloat = 560

    @ObservedObject private var engine = QuickToggleEngine.shared
    @ObservedObject private var scheduler = HubScheduleCoordinator.shared
    @StateObject private var status = SystemStatusService()
    @State private var selectedTab: MenuBarHubTab = MenuBarHubTab.visibleTabs().first ?? .switches
    @State private var query = ""
    @State private var boxSlots: [HubActionSlotID] = HubActionSlotID.slots()
    @State private var btAudioDevices: [BluetoothDevice] = []
    @State private var listeningMode: String? = AudioOutputSwitcher.bluetoothListeningMode()
    @State private var brightness: Double? = DisplayBrightness.levelForCursorScreen()
    /// MD-5: external volume, read once per open; nil hides the slider.
    @State private var displayVolume: Double?
    @State private var keyLight: Double? = KeyboardBacklight.isAvailable ? KeyboardBacklight.current() : nil
    @State private var shortcutNames: [String] = []
    @State private var shortcutsLoaded = false
    @State private var evolutions: [EvolutionItem] = EvolutionItem.parse(UserDefaults.standard.data(forKey: EvolutionItem.defaultsKey))
    @State private var showAddEvolution = false
    @State private var evoTitle = ""
    @State private var evoScript = ""
    @State private var evoShell: EvolutionItem.Shell = .sh
    @State private var showAddSchedule = false
    @State private var schedTarget: QuickToggleID = .keepAwake
    @State private var schedDesiredState = true
    @State private var schedIsDaily = false
    @State private var schedMinutes = 30
    @State private var schedTime = Date()
    @State private var surfaceVersion = 0
    /// Tier B: empty (the default) keeps every opt-in module out of the tree entirely.
    @AppStorage(HubModule.storageKey) private var modulesRaw = ""
    @State private var showUninstaller = false
    /// SN-6: saved display arrangements, loaded once per open.
    @State private var arrangements: [DisplayArrangement] = []
    @State private var calendarMonth = Date()
    @AppStorage(HubActionLayout.widthsKey) private var boxWidthsRaw = "half,half,half,half"
    @ObservedObject private var keepAwake = KeepAwakeService.shared
    @AppStorage(HubAppearancePreset.storageKey) private var appearanceRaw = HubAppearancePreset.default.rawValue
    @AppStorage("com.katikati.stayawake.preset") private var awakePresetRaw = 30
    @State private var disk: DiskUsage?
    @State private var lidNeedsAdmin = false

    @Environment(\.dockThemeStyle) private var dockThemeStyle
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: DockThemeTokens { .resolved(for: colorScheme, style: dockThemeStyle) }
    private var palette: SettingsIridescentPalette { .resolve(style: dockThemeStyle, colorScheme: colorScheme) }
    private var ink: Color { theme.labelActive.color }
    private var appearance: HubAppearancePreset { HubAppearancePreset.parse(appearanceRaw) }
    /// Secondary ink comes from the primary ink, never a washed tint, so one preset value raises every
    /// subtitle and caption together.
    private var inkSoft: Color { ink.opacity(appearance.secondaryInk) }
    private var cardFill: Color { Color.primary.opacity((colorScheme == .dark ? 0.08 : 0.05) * appearance.cardScale) }
    private var cardStroke: Color { Color.primary.opacity((colorScheme == .dark ? 0.12 : 0.08) * appearance.cardScale) }
    private var awakePreset: StayAwakePreset { StayAwakePreset(rawValue: awakePresetRaw) ?? .m30 }
    private var tabs: [MenuBarHubTab] { MenuBarHubTab.visibleTabs() }
    private var modules: Set<HubModule> { HubModule.enabled(modulesRaw) }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: HubCaretPlan.height)
            hubBody
        }
        .frame(width: Self.panelWidth, height: Self.panelHeight + HubCaretPlan.height, alignment: .top)
        .background {
            // One plate: the body's backdrop is masked to body + pointer, and one rim strokes the
            // combined outline, so the joint cannot show a material or rim seam.
            ZStack {
                DockPanelBackdrop(theme: theme, cornerRadius: 0,
                                  usesLiquidGlass: DockGlassPresentation.shouldAttemptTaskbarComposite)
                // The finish's scrim: glass keeps a small legibility floor, the solid presets buy contrast.
                Color(colorScheme == .dark ? .black : .white).opacity(appearance.plateScrim)
                palette.primaryAccent.opacity(appearance.accentTint)
            }
                .mask(HubPlateShape(caretCenter: plateCaretX).fill(Color.black))
        }
        .overlay {
            HubPlateShape(caretCenter: plateCaretX)
                .stroke(theme.panelRimStyle, lineWidth: theme.panelRimLineWidth)
        }
        .sheet(isPresented: $showUninstaller) { HubUninstallerSheet() }
        .onAppear {
            engine.refresh(); status.acquire(); boxSlots = HubActionSlotID.slots()
            arrangements = DisplayArrangementStore.load()
            if !tabs.contains(selectedTab), let first = tabs.first { selectedTab = first }
            // MD-5: the external panel's own volume, read once per open (nil hides the slider).
            displayVolume = DisplayBrightness.volumeForCursorScreen()
        }
        .onDisappear { status.release() }
        .onChange(of: selectedTab) { _, _ in query = "" }
        .task {
            await DockDevicesFeed.shared.refreshIfStale(maxAge: 5)
            btAudioDevices = DockDevicesFeed.shared.devices.filter { $0.lowestBattery != nil }
            disk = SystemMonitorSampler.disk()
        }
    }

    private var plateCaretX: CGFloat {
        HubCaretPlan.centerX(iconCenter: caretX, panelWidth: Self.panelWidth)
    }

    private var hubBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerBar
            tabContent
        }
        .padding(12)
        .frame(width: Self.panelWidth, height: Self.panelHeight, alignment: .top)
    }

    private var headerBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(tabs) { tab in
                    let active = selectedTab == tab
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.8)) { selectedTab = tab }
                    } label: {
                        Image(systemName: tab.symbolName).font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(active ? Color.white : inkSoft).frame(width: 30, height: 26)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(active ? AnyShapeStyle(palette.pillGradient) : AnyShapeStyle(Color.clear)))
                    }.buttonStyle(.plain)
                }
            }
            .padding(2).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(cardFill))

            Spacer(minLength: 4)

            Menu {
                ForEach(HubAppearancePreset.allCases) { preset in
                    Button { appearanceRaw = preset.rawValue } label: {
                        if preset == appearance { Label(preset.title, systemImage: "checkmark") }
                        else { Text(verbatim: preset.title) }
                    }
                }
            } label: {
                Image(systemName: "circle.lefthalf.filled").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(inkSoft).frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(cardFill))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help(Text("Appearance"))

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape").font(.system(size: 12, weight: .medium)).foregroundStyle(inkSoft)
                    .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(cardFill))
            }.buttonStyle(.plain).help(Text("Open Settings…"))
        }
    }

    private var boxWidths: [HubActionWidth] {
        let parsed = boxWidthsRaw.split(separator: ",").compactMap { HubActionWidth(rawValue: String($0)) }
        return (0..<4).map { $0 < parsed.count ? parsed[$0] : .half }
    }

    /// Two half tiles share a row; a full tile takes the whole row. Building rows here (instead of a
    /// LazyVGrid) is what lets one tile span the panel without a second layout pass.
    private var boxRows: [[HubActionRowEntry]] {
        let widths = boxWidths
        var rows: [[HubActionRowEntry]] = []
        var index = 0
        while index < boxSlots.count {
            var row = [HubActionRowEntry(index: index, slot: boxSlots[index])]
            if widths[index] == .half, index + 1 < boxSlots.count, widths[index + 1] == .half {
                row.append(HubActionRowEntry(index: index + 1, slot: boxSlots[index + 1]))
                index += 1
            }
            rows.append(row)
            index += 1
        }
        return rows
    }

    private var actionBoxGrid: some View {
        LazyVStack(spacing: 8) {
            ForEach(Array(boxRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row) { entry in boxTile(slot: entry.slot, index: entry.index) }
                }
            }
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
                    boxTitle(slot).font(.system(size: 12, weight: .semibold)).foregroundStyle(ink).lineLimit(1)
                    Text(on ? String(localized: "On") : String(localized: "Off")).font(.system(size: 10.5, weight: .medium))
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
            Section("Size") {
                Button { setBoxWidth(index, .half) } label: {
                    Label("Half Width", systemImage: boxWidths[index] == .half ? "checkmark" : "rectangle.lefthalf.filled")
                }
                Button { setBoxWidth(index, .full) } label: {
                    Label("Full Width", systemImage: boxWidths[index] == .full ? "checkmark" : "rectangle.fill")
                }
            }
            Button { moveBox(index, by: -1) } label: { Label("Move Left", systemImage: "arrow.left") }
                .disabled(index == 0)
            Button { moveBox(index, by: 1) } label: { Label("Move Right", systemImage: "arrow.right") }
                .disabled(index == boxSlots.count - 1)
            Menu {
                ForEach(HubActionSlotID.allCases) { candidate in
                    Button { replaceBox(index, with: candidate) } label: { boxTitle(candidate) }
                }
            } label: { Text("Replace") }
            Divider()
            Button(role: .destructive) { removeBox(index) } label: { Label("Remove", systemImage: "trash") }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .switches: switchesBody
        case .statusAudio: statusAudioBody
        case .shortcutsEvolutions: shortcutsEvolutionsBody
        case .schedules: schedulesBody
        }
    }

    private var switchesBody: some View {
        let items = HubSwitchCatalog.filter(HubSwitchCatalog.orderedSwitches(), query: query) { switchLabel($0) }
            .filter { !$0.isDuplicated(by: boxSlots) && !Self.isKeepAwake($0) }
        return ScrollView {
            VStack(spacing: 6) {
                // Page one's own actions, not global chrome repeated above every tab.
                actionBoxGrid
                // SN-2: snApp lives in the Hub rather than on a second status item, so the menu bar
                // keeps the one consolidated icon this app settled on.
                snapPickerRow
                displayModeRow
                arrangementRow
                keepAwakeCard
                pageSearchField
                if let buds = btAudioDevices.first, let level = buds.lowestBattery {
                    airPodsPill(device: buds, battery: level)
                }
                ForEach(items) { item in switchRow(item) }
                if modules.contains(.uninstaller) {
                    Button { showUninstaller = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.primaryAccent).frame(width: 18)
                            Text("Uninstaller").font(.system(size: 11.5, weight: .medium)).foregroundStyle(ink)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 9))
                                .foregroundStyle(inkSoft)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(cardFill))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// SN-6: the modes the panel really advertises, HiDPI rows included. Each apply is provisional for
    /// fifteen seconds, so a mode the screen cannot show reverts on its own.
    private var displayModeRow: some View {
        Menu {
            let screen = NSScreen.main
            let displayID = screen.flatMap { DisplayModeService.displayID(for: $0) }
            let options = displayID.map { id in
                DisplayModeService.modes(for: id).map { DisplayModeService.option(for: $0) }
            } ?? []
            ForEach(DisplayModeCatalog.sorted(options)) { option in
                Button(option.label) {
                    guard let screen else { return }
                    DisplayModeSwitcher.shared.apply(option, on: screen)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "display").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.primaryAccent).frame(width: 18)
                Text("Display Mode").font(.system(size: 11.5, weight: .medium)).foregroundStyle(ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(inkSoft)
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(cardFill))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    /// SN-6: where the displays sit, saved and re-applied by display UUID.
    private var arrangementRow: some View {
        Menu {
            Button("Save Current Arrangement") { saveArrangement() }
            if !arrangements.isEmpty {
                Divider()
                ForEach(arrangements) { preset in
                    Button(preset.name) { DisplayModeService.applyArrangement(preset) }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.3.group").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.primaryAccent).frame(width: 18)
                Text("Arrangements").font(.system(size: 11.5, weight: .medium)).foregroundStyle(ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(inkSoft)
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(cardFill))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private func saveArrangement() {
        guard let preset = DisplayModeService.captureArrangement(named: "Arrangement \(arrangements.count + 1)") else { return }
        arrangements.append(preset)
        DisplayArrangementStore.save(arrangements)
    }

    /// Opens the layout grid next to the Hub's own caret, then gets out of its way.
    private var snapPickerRow: some View {
        Button {
            onDismiss()
            DispatchQueue.main.async { SnapPickerController.shared.present() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.split.2x2").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.primaryAccent).frame(width: 18)
                Text("Window Layouts").font(.system(size: 11.5, weight: .medium)).foregroundStyle(ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(inkSoft)
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(cardFill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func isKeepAwake(_ item: HubSwitchID) -> Bool {
        if case .system(.keepAwake) = item { return true }
        return false
    }

    private var pageSearchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(inkSoft)
            TextField(String(localized: "Search"), text: $query)
                .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(ink)
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(cardFill))
    }

    /// Keep Awake grown from a bare toggle into a timer: the chips choose how long a manual hold lasts,
    /// and lid-closed is opt-in next to it (the service still owns the admin prompt and the battery floor).
    private var keepAwakeCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(keepAwake.decision.hold ? palette.primaryAccent : ink)
                    .frame(width: 28, height: 28).background(Circle().fill(cardFill))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Keep Awake").font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
                    Text(verbatim: keepAwakeStatusLine).font(.system(size: 10, weight: .medium))
                        .foregroundStyle(inkSoft).lineLimit(1)
                }
                Spacer(minLength: 0)
                Toggle(isOn: Binding(get: { keepAwake.manualOn }, set: { on in
                    keepAwake.setManual(on, duration: on ? awakePreset.duration : nil)
                })) { EmptyView() }
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
            HStack(spacing: 4) {
                ForEach(StayAwakePreset.allCases, id: \.self) { option in
                    let active = keepAwake.manualOn && option == awakePreset
                    Button {
                        awakePresetRaw = option.rawValue
                        keepAwake.setManual(true, duration: option.duration)
                    } label: {
                        Text(verbatim: option.label)
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(active ? Color.white : inkSoft)
                            .frame(maxWidth: .infinity, minHeight: 22)
                            .background(Capsule().fill(active ? AnyShapeStyle(palette.pillGradient) : AnyShapeStyle(cardFill)))
                    }.buttonStyle(.plain)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "laptopcomputer").font(.system(size: 11)).foregroundStyle(inkSoft).frame(width: 16)
                Text("Lid closed").font(.system(size: 11, weight: .medium)).foregroundStyle(ink)
                Spacer(minLength: 0)
                Toggle(isOn: Binding(get: { keepAwake.lidClosedEnabled }, set: { on in
                    Task { lidNeedsAdmin = !(await keepAwake.setLidClosed(on)) }
                })) { EmptyView() }
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                .help(Text("Keep running with the lid shut"))
            }
            if lidNeedsAdmin {
                Text("Admin approval was not given").font(.system(size: 9.5)).foregroundStyle(.orange)
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardFill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(cardStroke, lineWidth: 1))
    }

    private var keepAwakeStatusLine: String {
        guard keepAwake.decision.hold else { return String(localized: "Off") }
        if keepAwake.decision.reason == .manual, let end = keepAwake.manualEnd {
            return String(format: String(localized: "Until %@"), end.formatted(date: .omitted, time: .shortened))
        }
        if keepAwake.manualOn { return String(localized: "Until you turn it off") }
        return String(localized: "AI agents")
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
            Image(systemName: switchSymbol(item)).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? palette.primaryAccent : ink)
                .frame(width: 28, height: 28)
                .background(Circle().fill(cardFill))
            Text(verbatim: switchLabel(item)).font(.system(size: 12, weight: .semibold)).foregroundStyle(ink).lineLimit(1)
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
        // Same 28 pt glyph well and 7.5 pt inset as the action tiles, so every row is 43 pt tall.
        .padding(.horizontal, 9).padding(.vertical, 7.5)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardFill))
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
                storageCard
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
                    hubSlider(icon: vol.symbolName, label: Text("Volume"), value: Binding(get: { Double(vol.level) }, set: { _ = status.setVolume(Float($0)) }))
                    if modules.contains(.audioMixer) {
                        Divider().overlay(cardStroke)
                        HubAudioMixerSection()
                    }
                }
                .padding(9).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardFill))
                if brightness != nil || keyLight != nil || displayVolume != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: "sun.max.fill").font(.system(size: 10.5)).foregroundStyle(palette.primaryAccent)
                            Text("Display & Keyboard").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(ink)
                            Spacer()
                        }
                        if let brightness {
                            hubSlider(icon: "sun.max.fill", label: Text("Brightness"), value: Binding(get: { brightness }, set: { self.brightness = $0; DisplayBrightness.setOnCursorScreen($0) }))
                        }
                        if let displayVolume {
                            hubSlider(icon: "speaker.wave.2.fill", label: Text("Display Volume"), value: Binding(get: { displayVolume }, set: { self.displayVolume = $0; DisplayBrightness.setVolumeOnCursorScreen($0) }))
                        }
                        if let keyLight {
                            hubSlider(icon: "keyboard", label: Text("Keyboard"), value: Binding(get: { keyLight }, set: { self.keyLight = $0; KeyboardBacklight.set($0) }))
                        }
                    }
                    .padding(9).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardFill))
                }
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
                if modules.contains(.agents) { HubAgentCard() }
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

    /// Page two owns the machine's story: battery, network and now the boot volume. One read on
    /// appear, not a poll — the hub never wakes the disk just to keep a percentage honest.
    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "internaldrive.fill").font(.system(size: 10.5)).foregroundStyle(palette.primaryAccent)
                Text("Storage").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(ink)
                Spacer()
                Text(verbatim: disk.map { "\($0.usedPercent)%" } ?? "–")
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(inkSoft)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule().fill(palette.primaryAccent.gradient)
                        .frame(width: proxy.size.width * CGFloat(disk?.usedFraction ?? 0))
                }
            }
            .frame(height: 5)
            HStack(spacing: 4) {
                Text("Used").font(.system(size: 10)).foregroundStyle(inkSoft)
                Text(verbatim: disk?.usedLabel ?? "–").font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(ink)
                Spacer(minLength: 0)
                Text("Available").font(.system(size: 10)).foregroundStyle(inkSoft)
                Text(verbatim: disk?.availableLabel ?? "–").font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(ink)
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardFill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(cardStroke, lineWidth: 1))
    }

    /// iPadOS-style level: a 34 pt capsule with a large white knob and the glyph sitting in the fill.
    /// The native slider is kept underneath at near-zero opacity so dragging, keyboard and
    /// Accessibility (AXSlider) behave exactly as before; only the drawing is bolder. The name sits in
    /// a leading column rather than inside the capsule: the fill can be as narrow as the knob, and text
    /// riding on it would change colour as the value moved. This hub has the same two-speaker problem as
    /// the Control Centre panel — system volume in one card, the external panel's own volume in another.
    private func hubSlider(icon: String, label: Text, value: Binding<Double>) -> some View {
        let fraction = min(max(value.wrappedValue, 0), 1)
        return HStack(spacing: 7) {
            label.font(.system(size: 11, weight: .semibold))
                .foregroundStyle(inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 92, alignment: .leading)
                .accessibilityHidden(true)
            GeometryReader { geo in
                let height = geo.size.height
                let knob = height - 8
                let travel = max(0, geo.size.width - knob - 6)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08))
                    // Neutral, like Control Center: the fill is ink, not an accent gradient.
                    Capsule().fill(ink.opacity(colorScheme == .dark ? 0.9 : 0.82))
                        .frame(width: max(height, geo.size.width * fraction))
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(colorScheme == .dark ? Color.black.opacity(0.72) : Color.white)
                        .padding(.leading, 12)
                    Circle().fill(.white)
                        .frame(width: knob, height: knob)
                        .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
                        .offset(x: 3 + travel * fraction)
                    Slider(value: value, in: 0...1)
                        .controlSize(.small)
                        .tint(.clear)
                        .opacity(0.02)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    value.wrappedValue = min(max((drag.location.x - 3) / max(travel, 1), 0), 1)
                })
            }
            .frame(height: 34)
            Text(verbatim: "\(Int((fraction * 100).rounded()))")
                .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .foregroundStyle(inkSoft).frame(width: 28, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Text(verbatim: "\(Int((fraction * 100).rounded()))"))
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 0.05 : -0.05
            value.wrappedValue = min(1, max(0, value.wrappedValue + step))
        }
    }

    // MARK: - MB-7: Shortcuts & Evolutions + Schedules

    private var shortcutsEvolutionsBody: some View {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredEvos = q.isEmpty ? evolutions : evolutions.filter { $0.title.localizedCaseInsensitiveContains(q) }
        let filteredSC = q.isEmpty ? shortcutNames : shortcutNames.filter { $0.localizedCaseInsensitiveContains(q) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                pageSearchField
                HStack {
                    Text("Custom").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(ink)
                    Spacer()
                    Button { showAddEvolution.toggle() } label: {
                        Label(String(localized: "Add"), systemImage: "plus").font(.system(size: 10.5, weight: .medium))
                    }.buttonStyle(.plain).foregroundStyle(palette.primaryAccent)
                }
                if showAddEvolution { addEvolutionForm }
                ForEach(filteredEvos) { evo in
                    HStack(spacing: 8) {
                        Image(systemName: evo.symbolName).font(.system(size: 11)).foregroundStyle(palette.primaryAccent).frame(width: 18)
                        Text(verbatim: evo.title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(ink).lineLimit(1)
                        Spacer()
                        Button { Task { _ = await EvolutionRunner.run(evo) } } label: {
                            Text("Run").font(.system(size: 10, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(cardFill))
                        }.buttonStyle(.plain)
                        Button { deleteEvolution(evo.id) } label: {
                            Image(systemName: "trash").font(.system(size: 10)).foregroundStyle(inkSoft)
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(cardFill))
                }

                HStack {
                    Text("Shortcuts").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(ink)
                    Spacer()
                    Button { Task { shortcutNames = await ShortcutsCatalogRunner.listNames() } } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 10.5)).foregroundStyle(inkSoft)
                    }.buttonStyle(.plain).help(Text("Refresh"))
                }.padding(.top, 2)

                if filteredSC.isEmpty {
                    Text("None").font(.system(size: 10.5)).foregroundStyle(inkSoft).padding(.vertical, 4)
                } else {
                    ForEach(filteredSC, id: \.self) { name in
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill").font(.system(size: 11)).foregroundStyle(palette.primaryAccent).frame(width: 18)
                            Text(verbatim: name).font(.system(size: 11.5)).foregroundStyle(ink).lineLimit(1)
                            Spacer()
                            Button { Task { _ = await ShortcutsCatalogRunner.runShortcut(named: name) } } label: {
                                Text("Run").font(.system(size: 10, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(cardFill))
                            }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(cardFill))
                    }
                }
            }
        }
        .task {
            guard !shortcutsLoaded else { return }
            shortcutsLoaded = true
            shortcutNames = await ShortcutsCatalogRunner.listNames()
        }
    }

    private var addEvolutionForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(String(localized: "Name"), text: $evoTitle).textFieldStyle(.roundedBorder).font(.system(size: 11))
            TextField(String(localized: "Command"), text: $evoScript).textFieldStyle(.roundedBorder).font(.system(size: 11))
            HStack {
                Picker(selection: $evoShell) {
                    Text(verbatim: "sh").tag(EvolutionItem.Shell.sh)
                    Text(verbatim: "osascript").tag(EvolutionItem.Shell.appleScript)
                } label: { EmptyView() }.labelsHidden().pickerStyle(.segmented).frame(width: 130)
                Spacer()
                Button("Cancel") { showAddEvolution = false }.font(.system(size: 10.5))
                Button("Save") { saveEvolution() }
                    .font(.system(size: 10.5, weight: .semibold))
                    .disabled(evoTitle.trimmingCharacters(in: .whitespaces).isEmpty || evoScript.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(8).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(cardFill))
    }

    private func saveEvolution() {
        let item = EvolutionItem(title: evoTitle.trimmingCharacters(in: .whitespaces), shell: evoShell, runScript: evoScript)
        evolutions.append(item)
        UserDefaults.standard.set(EvolutionItem.encode(evolutions), forKey: EvolutionItem.defaultsKey)
        evoTitle = ""; evoScript = ""; showAddEvolution = false
    }

    private func deleteEvolution(_ id: UUID) {
        evolutions.removeAll { $0.id == id }
        UserDefaults.standard.set(EvolutionItem.encode(evolutions), forKey: EvolutionItem.defaultsKey)
    }

    private var schedulesBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                pageSearchField
                HStack {
                    Text("Schedule").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(ink)
                    Spacer()
                    Button { showAddSchedule.toggle() } label: {
                        Label(String(localized: "Add"), systemImage: "plus").font(.system(size: 10.5, weight: .medium))
                    }.buttonStyle(.plain).foregroundStyle(palette.primaryAccent)
                }
                if showAddSchedule { addScheduleForm }
                if scheduler.rules.isEmpty {
                    Text("None").font(.system(size: 10.5)).foregroundStyle(inkSoft).padding(.vertical, 4)
                } else {
                    ForEach(scheduler.rules) { rule in scheduleRow(rule) }
                }
                calendarCard
            }
        }
        .onAppear { scheduler.reload() }
    }

    /// A month view under the schedule list. Pure grid from `HubCalendarGrid`; the month names and
    /// weekday letters come from the user's calendar, so no new copy is needed.
    private var calendarCard: some View {
        let calendar = Calendar.current
        let cells = HubCalendarGrid.cells(for: calendarMonth, calendar: calendar)
        let symbols = HubCalendarGrid.weekdaySymbols(calendar)
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(verbatim: formatter.string(from: calendarMonth))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
                Spacer()
                monthArrow("chevron.left", delta: -1)
                monthArrow("chevron.right", delta: 1)
            }
            HStack(spacing: 0) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                    Text(verbatim: symbol).font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(inkSoft).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: HubCalendarGrid.columns), spacing: 2) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    calendarDay(cell)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardFill))
    }

    private func monthArrow(_ symbol: String, delta: Int) -> some View {
        Button {
            guard let next = Calendar.current.date(byAdding: .month, value: delta, to: calendarMonth) else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.85)) { calendarMonth = next }
        } label: {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(inkSoft).frame(width: 22, height: 22)
                .background(Circle().fill(cardFill))
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private func calendarDay(_ cell: HubCalendarCell) -> some View {
        if let day = cell.day {
            Text(verbatim: "\(day)")
                .font(.system(size: 11, weight: cell.isToday ? .bold : .medium)).monospacedDigit()
                .foregroundStyle(cell.isToday ? Color.white : ink)
                .frame(maxWidth: .infinity, minHeight: 24)
                .background {
                    if cell.isToday {
                        Circle().fill(palette.primaryAccent).frame(width: 24, height: 24)
                    }
                }
        } else {
            Color.clear.frame(height: 24)
        }
    }

    private var addScheduleForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker(selection: $schedTarget) {
                    ForEach(QuickToggleID.allCases.filter { !$0.isAction }, id: \.self) { id in id.title.tag(id) }
                } label: { EmptyView() }.labelsHidden().frame(maxWidth: .infinity)
                Picker(selection: $schedDesiredState) {
                    Text("On").tag(true); Text("Off").tag(false)
                } label: { EmptyView() }.labelsHidden().pickerStyle(.segmented).frame(width: 84)
            }
            HStack {
                Picker(selection: $schedIsDaily) {
                    Text("Timer").tag(false); Text("Daily").tag(true)
                } label: { EmptyView() }.labelsHidden().pickerStyle(.segmented).frame(width: 120)
                Spacer()
                if schedIsDaily {
                    DatePicker(selection: $schedTime, displayedComponents: .hourAndMinute) { EmptyView() }.labelsHidden()
                } else {
                    Stepper(value: $schedMinutes, in: 5...240, step: 5) {
                        Text(verbatim: "\(schedMinutes)m").font(.system(size: 11)).monospacedDigit()
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { showAddSchedule = false }.font(.system(size: 10.5))
                Button("Save") { saveSchedule() }.font(.system(size: 10.5, weight: .semibold))
            }
        }
        .padding(8).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(cardFill))
    }

    private func scheduleRow(_ rule: HubScheduleRule) -> some View {
        let title = HubSwitchID(token: rule.targetToken).map(switchLabel) ?? rule.targetToken
        let kindLabel: String = {
            switch rule.kind {
            case .afterMinutes(let m): return "\(m)m"
            case .daily(let h, let m): return String(format: "%02d:%02d", h, m)
            }
        }()
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "\(title) · \(rule.desiredState ? String(localized: "On") : String(localized: "Off"))")
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(ink).lineLimit(1)
                Text(verbatim: kindLabel).font(.system(size: 9.5)).monospacedDigit().foregroundStyle(inkSoft)
            }
            Spacer()
            Toggle(isOn: Binding(get: { rule.isEnabled }, set: { next in
                var list = scheduler.rules
                if let idx = list.firstIndex(where: { $0.id == rule.id }) { list[idx].isEnabled = next }
                scheduler.save(list)
            })) { EmptyView() }.labelsHidden().toggleStyle(.switch).controlSize(.mini)
            Button {
                scheduler.save(scheduler.rules.filter { $0.id != rule.id })
            } label: {
                Image(systemName: "trash").font(.system(size: 10)).foregroundStyle(inkSoft)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(cardFill))
    }

    private func setBoxWidth(_ index: Int, _ width: HubActionWidth) {
        guard boxWidths.indices.contains(index) else { return }
        var widths = boxWidths
        widths[index] = width
        boxWidthsRaw = HubActionLayout.serializeWidths(widths)
    }

    private func replaceBox(_ index: Int, with slot: HubActionSlotID) {
        guard boxSlots.indices.contains(index) else { return }
        var next = boxSlots
        next[index] = slot
        saveBoxes(next)
    }

    private func moveBox(_ index: Int, by delta: Int) {
        let target = index + delta
        guard boxSlots.indices.contains(index), boxSlots.indices.contains(target) else { return }
        var next = boxSlots
        next.swapAt(index, target)
        saveBoxes(next)
    }

    /// Removing keeps four tiles: the gap is filled from the default order with an action that is
    /// not already on the grid, so the panel never shrinks to a ragged row.
    private func removeBox(_ index: Int) {
        guard boxSlots.indices.contains(index) else { return }
        var next = boxSlots
        next.remove(at: index)
        if let filler = (HubActionSlotID.defaultSlots + HubActionSlotID.allCases).first(where: { !next.contains($0) }) {
            next.append(filler)
        }
        saveBoxes(next)
    }

    private func saveBoxes(_ slots: [HubActionSlotID]) {
        let trimmed = Array(slots.prefix(4))
        boxSlots = trimmed
        UserDefaults.standard.set(HubActionSlotID.serialize(trimmed), forKey: HubActionSlotID.defaultsKey)
    }

    private func saveSchedule() {
        let kind: HubScheduleRule.Kind
        if schedIsDaily {
            let c = Calendar.current.dateComponents([.hour, .minute], from: schedTime)
            kind = .daily(hour: c.hour ?? 9, minute: c.minute ?? 0)
        } else {
            kind = .afterMinutes(schedMinutes)
        }
        let rule = HubScheduleRule(targetToken: HubSwitchID.system(schedTarget).token, desiredState: schedDesiredState, kind: kind)
        scheduler.save(scheduler.rules + [rule])
        showAddSchedule = false
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

// MARK: - MB-9: Agents (opt-in)

/// Title row shared by the opt-in module cards; each card supplies its own trailing accessory.
struct HubModuleCardHeader<Accessory: View>: View {
    let symbol: String
    let title: String
    let accessory: Accessory

    @Environment(\.dockThemeStyle) private var dockThemeStyle
    @Environment(\.colorScheme) private var colorScheme

    init(symbol: String, title: String, @ViewBuilder accessory: () -> Accessory) {
        self.symbol = symbol
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        let theme = DockThemeTokens.resolved(for: colorScheme, style: dockThemeStyle)
        let palette = SettingsIridescentPalette.resolve(style: dockThemeStyle, colorScheme: colorScheme)
        return HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.primaryAccent)
            Text(LocalizedStringKey(title)).font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(theme.labelActive.color)
            Spacer(minLength: 0)
            accessory
        }
    }
}

/// The plate both module cards sit on, so their padding, fill and edge cannot drift apart.
private struct HubModuleCardChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 1))
    }
}

extension View {
    func hubModuleCardChrome() -> some View { modifier(HubModuleCardChrome()) }
}

/// The hub's opt-in agent card: today's spend, the loadout profile, and the approval-hook pause.
/// Created only while the module is on, so the singleton services below exist on the owner's terms.
struct HubAgentCard: View {
    @ObservedObject private var usage = AgentUsageService.shared
    @State private var hooksPaused = !ClaudeApprovalService.shared.isRunning
    @Environment(\.dockThemeStyle) private var dockThemeStyle
    @Environment(\.colorScheme) private var colorScheme

    private var theme: DockThemeTokens { .resolved(for: colorScheme, style: dockThemeStyle) }
    private var inkSoft: Color { theme.labelSubtitle.color }
    private var enabledCount: Int { AgentLoadoutSummary.enabledCount(usage.loadoutItems) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HubModuleCardHeader(symbol: "sparkles", title: "Agents") {
                Text(verbatim: AgentLoadoutSummary.badge(cost: usage.snapshot.todayCost,
                                                         enabled: enabledCount,
                                                         total: usage.loadoutItems.count))
                    .font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(inkSoft)
            }
            Picker(selection: Binding(
                get: { usage.activeProfile },
                set: { usage.applyLoadoutProfile($0) }
            )) {
                ForEach(LoadoutProfile.allCases) { profile in
                    Text(verbatim: profile.title).tag(profile)
                }
            } label: { EmptyView() }
            .labelsHidden().pickerStyle(.menu).controlSize(.small)

            Toggle(isOn: Binding(
                get: { hooksPaused },
                set: { paused in
                    hooksPaused = paused
                    if paused { ClaudeApprovalService.shared.stop() } else { ClaudeApprovalService.shared.start() }
                }
            )) {
                Text("Pause").font(.system(size: 10.5)).foregroundStyle(inkSoft)
            }
            .toggleStyle(.switch).controlSize(.mini)
        }
        .hubModuleCardChrome()
    }
}

// MARK: - MB-10: Audio Mixer (opt-in)

/// Per-app levels. The engine is created with this card and torn down when the tab changes, so the
/// module is off (and silent) the moment its view is gone.
/// Lives inside the Audio Output card: general output level and per-app levels are one audio story.
struct HubAudioMixerSection: View {
    @StateObject private var engine = PerAppAudioEngine()
    @Environment(\.dockThemeStyle) private var dockThemeStyle
    @Environment(\.colorScheme) private var colorScheme

    private var theme: DockThemeTokens { .resolved(for: colorScheme, style: dockThemeStyle) }
    private var palette: SettingsIridescentPalette { .resolve(style: dockThemeStyle, colorScheme: colorScheme) }
    private var ink: Color { theme.labelActive.color }
    private var inkSoft: Color { theme.labelSubtitle.color }

    private var audible: [AppAudioProcess] { engine.processes.filter(\.isRunningOutput) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HubModuleCardHeader(symbol: "slider.horizontal.3", title: "Audio Mixer") {
                Button { engine.refresh() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10)).foregroundStyle(inkSoft)
                }.buttonStyle(.plain).help(Text("Refresh"))
            }
            if engine.unavailable {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                    Text("Audio route unavailable — allow System Audio Recording.")
                        .font(.system(size: 10.5, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.orange)
            }
            if audible.isEmpty {
                Text("None").font(.system(size: 10.5)).foregroundStyle(inkSoft).padding(.vertical, 3)
            } else {
                ForEach(Array(audible.prefix(6))) { process in row(process) }
            }
        }
        .padding(.top, 2)
        .onAppear { engine.start() }
        .onDisappear { engine.stop() }
    }

    private func row(_ process: AppAudioProcess) -> some View {
        let failure = engine.failure(for: process)
        return VStack(spacing: 3) {
            HStack(spacing: 6) {
                Text(verbatim: process.name).font(.system(size: 12)).foregroundStyle(ink).lineLimit(1)
                if engine.isRouted(process) {
                    Circle().fill(palette.primaryAccent).frame(width: 5, height: 5)
                }
                Spacer(minLength: 0)
                Text(verbatim: "\(PerAppAudioRules.percent(engine.gain(for: process)))%")
                    .font(.system(size: 9.5)).monospacedDigit().foregroundStyle(inkSoft)
            }
            HStack(spacing: 6) {
                Button { engine.setMuted(!engine.isMuted(process), for: process) } label: {
                    Image(systemName: engine.isMuted(process) ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(engine.isMuted(process) ? Color.red : inkSoft)
                        .frame(width: 16)
                }.buttonStyle(.plain)
                Slider(value: Binding(
                    get: { engine.gain(for: process) },
                    set: { engine.setGain($0, for: process) }
                ), in: 0...1).controlSize(.mini).tint(palette.primaryAccent)
            }
            if let failure {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
                    Text(verbatim: failureText(failure)).font(.system(size: 9.5, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.orange)
            }
        }
    }

    /// A rejected output layout is not a level problem, so it says so instead of blaming the volume.
    private func failureText(_ failure: PerAppAudioFailure) -> String {
        failure.isLayoutMismatch
            ? String(localized: "Output layout not supported")
            : String(localized: "Volume Unavailable")
    }
}

// MARK: - MB-11: Uninstaller (opt-in)

/// On-demand app removal sheet. Uses the launcher's scan and `AppRemovalPlanner` — the same plan the
/// launcher and Command Bar use — and never hard-deletes: every path goes to the Finder Trash.
struct HubUninstallerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [UninstallerEntry] = []
    @State private var query = ""
    @State private var pending: UninstallerEntry?
    @State private var moved = 0
    @State private var loading = true

    private var visible: [UninstallerEntry] { UninstallerCatalog.filter(entries, query: query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Uninstaller").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Cancel") { dismiss() }.font(.system(size: 11))
            }
            TextField(String(localized: "Search"), text: $query)
                .textFieldStyle(.roundedBorder).font(.system(size: 11))
            if loading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        if visible.isEmpty { Text("None").font(.system(size: 11)).foregroundStyle(.secondary) }
                        ForEach(visible) { entry in appRow(entry) }
                    }
                }
                .frame(minHeight: 180)
            }
            if let pending {
                confirmCard(pending)
            } else if moved > 0 {
                Text(verbatim: "\(moved)").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 460, height: 520)
        .task {
            entries = await Task.detached(priority: .utility) {
                UninstallerCatalog.entries(from: LauncherIndexer.scanDirectories())
            }.value
            loading = false
        }
    }

    private func appRow(_ entry: UninstallerEntry) -> some View {
        Button { pending = entry } label: {
            HStack(spacing: 8) {
                Image(systemName: "app").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: entry.name).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                    Text(verbatim: entry.bundleID).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("Uninstall…").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func confirmCard(_ entry: UninstallerEntry) -> some View {
        let plan = removalPlan(entry)
        return VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: entry.name).font(.system(size: 11.5, weight: .semibold))
            ForEach(plan.paths.prefix(6), id: \.self) { path in
                Text(verbatim: path).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack {
                Spacer()
                Button("Cancel") { pending = nil }.font(.system(size: 10.5))
                Button("Move to Trash") {
                    let count = AppRemovalService.perform(plan)
                    moved += count
                    entries.removeAll { $0.id == entry.id }
                    pending = nil
                }
                .font(.system(size: 10.5, weight: .semibold))
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private func removalPlan(_ entry: UninstallerEntry) -> AppRemovalPlan {
        var plan = AppRemovalService.plan(bundleID: entry.bundleID, name: entry.name,
                                          appPath: entry.path, removal: .uninstall)
        let residue = AppRemovalService.plan(bundleID: entry.bundleID, name: entry.name,
                                             appPath: entry.path, removal: .deleteData)
        plan.paths += residue.paths.filter { !plan.paths.contains($0) }
        return plan
    }
}

private struct HubActionRowEntry: Identifiable {
    let index: Int
    let slot: HubActionSlotID
    var id: Int { index }
}

/// Body and pointer as one outline. The panel's backdrop is masked to this path and the rim is
/// stroked from the same path, so the pointer carries the panel's exact material and tint and the
/// joint has no seam line of its own.
private struct HubPlateShape: Shape {
    var cornerRadius: CGFloat = 20
    var caretCenter: CGFloat

    func path(in rect: CGRect) -> Path {
        let caretHeight = HubCaretPlan.height
        let bodyRect = CGRect(x: rect.minX, y: rect.minY + caretHeight,
                              width: rect.width, height: rect.height - caretHeight)
        let body = CGPath(roundedRect: bodyRect, cornerWidth: cornerRadius,
                          cornerHeight: cornerRadius, transform: nil)
        let half = HubCaretPlan.halfWidth
        let cx = min(max(caretCenter, bodyRect.minX + cornerRadius + half),
                     bodyRect.maxX - cornerRadius - half)
        let base = bodyRect.minY + 0.5
        let caret = CGMutablePath()
        caret.move(to: CGPoint(x: cx - half, y: base))
        caret.addQuadCurve(to: CGPoint(x: cx, y: rect.minY),
                           control: CGPoint(x: cx - half * 0.5, y: rect.minY + caretHeight * 0.12))
        caret.addQuadCurve(to: CGPoint(x: cx + half, y: base),
                           control: CGPoint(x: cx + half * 0.5, y: rect.minY + caretHeight * 0.12))
        caret.closeSubpath()
        return Path(body.union(caret))
    }
}

// MARK: - Control Centre cards: VoiceOver grouping and edit-mode drag

/// `CC-4`/VoiceOver: a card is one named group whose controls stay individually reachable. The label
/// is optional so a card without a name is still a group, just an unnamed one.
private struct ControlCenterCardLabel: ViewModifier {
    let label: Text?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let label {
            content.accessibilityLabel(label)
        } else {
            content
        }
    }
}

/// `CC-4`: a drop lands the dragged card in front of the card it was released on. The item provider is
/// never read — the drag source lives in this panel, so `dragging` already carries the identity.
private struct ControlCenterDropDelegate: DropDelegate {
    let target: ControlCenterTileID
    @Binding var dragging: ControlCenterTileID?
    let move: (ControlCenterTileID, ControlCenterTileID) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        guard let dragging else { return false }
        move(dragging, target)
        self.dragging = nil
        return true
    }
}
