import CoreGraphics
import Foundation

/// The menu-bar readout's pure model (Pass 2): which metrics exist, what styles each may show,
/// where its preferences live, and how its numbers read. No AppKit and no IOKit — the status
/// items draw and the platform samplers read; this file only decides. Dual-compiled into the
/// test target so every decision below is unit-testable.
enum MenuBarMetric: String, CaseIterable, Identifiable, Sendable {
    case cpu, memory, gpu, storage, battery, network
    var id: String { rawValue }
}

enum MenuBarMetricStyle: String, CaseIterable, Sendable {
    case percentage, barGraph, pieChart, available, used, iconOnly
    /// 59d: the battery's own readings, after BeteriApp's display types.
    case remainingTime, watts
    /// T1.1: percentage embedded inside a dynamic Green/Yellow/Red battery shell.
    case nestedPill
}

enum MenuBarBatteryPillTone: Equatable, Sendable {
    case healthy, warning, critical, charging
}

/// One tick of readings for every metric. `gpu` and `battery` are optional on purpose: a reader
/// with nothing to report ("–") is a real state and must never be faked as zero.
struct MenuBarStatValues: Equatable, Sendable {
    var cpu = 0.0
    var memory = 0.0
    var gpu: Double?
    var storageUsed = 0.0
    var storageFreeBytes = 0.0
    var storageTotalBytes = 0.0
    var battery: MenuBarBattery?
    var down = 0.0
    var up = 0.0
}

struct MenuBarBattery: Equatable, Sendable {
    var fraction = 0.0
    var isCharging = false
    /// 59c/59d: seconds to empty or full, and the watts going in.
    var secondsRemaining: Int?
    var watts: Double?
}

enum MenuBarStatModel {
    /// The master switch. Same key the old single CPU/MEM readout used, so anyone who had it on
    /// keeps a readout after the update.
    static let masterEnabledKey = "com.katikati.menuBarSystem.enabled"

    static func enabledKey(_ metric: MenuBarMetric) -> String { "com.katikati.menuBar.\(metric.rawValue).enabled" }
    static func styleKey(_ metric: MenuBarMetric) -> String { "com.katikati.menuBar.\(metric.rawValue).style" }

    /// Default-on metrics preserve the old readout: anyone who had the single CPU/MEM item on
    /// keeps a readout after the update, and flipping the master on shows the same pair.
    static func defaultEnabled(_ metric: MenuBarMetric) -> Bool { metric == .cpu || metric == .memory }

    /// An unset key reads the default — `bool(forKey:)` would silently turn every metric off.
    static func isEnabled(_ metric: MenuBarMetric, defaults: UserDefaults = .standard) -> Bool {
        (defaults.object(forKey: enabledKey(metric)) as? Bool) ?? defaultEnabled(metric)
    }

    /// Display name; the same string is the localization key used by the Settings rows and menu.
    static func displayName(_ metric: MenuBarMetric) -> String {
        switch metric {
        case .cpu: return String(localized: "CPU")
        case .memory: return String(localized: "Memory")
        case .gpu: return String(localized: "GPU")
        case .storage: return String(localized: "Storage")
        case .battery: return String(localized: "Battery")
        case .network: return String(localized: "Network")
        }
    }

    static func displayName(_ style: MenuBarMetricStyle) -> String {
        switch style {
        case .percentage: return String(localized: "Percentage")
        case .barGraph: return String(localized: "Bar Graph")
        case .pieChart: return String(localized: "Pie Chart")
        case .available: return String(localized: "Available")
        case .used: return String(localized: "Used")
        case .iconOnly: return String(localized: "Icon Only")
        case .remainingTime: return String(localized: "Time Remaining")
        case .watts: return String(localized: "Watts")
        case .nestedPill: return String(localized: "Battery Pill")
        }
    }

    static func styles(for metric: MenuBarMetric) -> [MenuBarMetricStyle] {
        switch metric {
        case .cpu, .memory, .gpu: return [.percentage, .barGraph, .pieChart]
        case .storage: return [.percentage, .available, .used]
        case .battery: return [.percentage, .nestedPill, .remainingTime, .watts, .iconOnly]
        case .network: return []
        }
    }

    static func defaultStyle(for metric: MenuBarMetric) -> MenuBarMetricStyle { .percentage }

    /// A style stored by another version or typed into `defaults` by hand is not a crash:
    /// anything the metric cannot show falls back to its default.
    static func style(_ raw: String?, for metric: MenuBarMetric) -> MenuBarMetricStyle {
        guard let raw, let style = MenuBarMetricStyle(rawValue: raw), styles(for: metric).contains(style) else {
            return defaultStyle(for: metric)
        }
        return style
    }

    /// The busy share behind the percentage styles: nil means the reader reported nothing.
    static func fraction(metric: MenuBarMetric, values: MenuBarStatValues) -> Double? {
        switch metric {
        case .cpu: return clamp01(values.cpu)
        case .memory: return clamp01(values.memory)
        case .gpu: return values.gpu.map(clamp01)
        case .storage: return clamp01(values.storageUsed)
        case .battery: return values.battery.map { clamp01($0.fraction) }
        case .network: return nil
        }
    }

    /// The status item's text; empty means the style draws an image instead (bar / pie / icon).
    static func statusText(metric: MenuBarMetric, style: MenuBarMetricStyle, values: MenuBarStatValues) -> String {
        if metric == .network {
            return menuRowText(metric: .network, values: values)
        }
        switch style {
        case .barGraph, .pieChart, .iconOnly, .nestedPill:
            return ""
        case .percentage:
            return fraction(metric: metric, values: values).map(SystemMonitorFormat.percent) ?? "–"
        case .available:
            return SystemMonitorFormat.bytes(values.storageFreeBytes)
        case .used:
            return SystemMonitorFormat.bytes(Double(values.storageTotalBytes) - values.storageFreeBytes)
        case .remainingTime:
            return PowerFacts.durationText(values.battery?.secondsRemaining) ?? "–"
        case .watts:
            return values.battery?.watts.map { String(format: "%.1f W", $0) } ?? "–"
        }
    }

    /// The click menu's one-line reading per metric — always the natural reading, whatever
    /// style the status item shows.
    static func menuRowText(metric: MenuBarMetric, values: MenuBarStatValues) -> String {
        switch metric {
        case .cpu, .memory, .gpu:
            return fraction(metric: metric, values: values).map(SystemMonitorFormat.percent) ?? "–"
        case .storage:
            let used = fraction(metric: .storage, values: values).map(SystemMonitorFormat.percent) ?? "–"
            return "\(used) · \(SystemMonitorFormat.bytes(values.storageFreeBytes))"
        case .battery:
            let reading = fraction(metric: .battery, values: values).map(SystemMonitorFormat.percent) ?? "–"
            guard let facts = PowerFacts.durationText(values.battery?.secondsRemaining) else { return reading }
            return "\(reading) · \(facts)"
        case .network:
            return "↓\(SystemMonitorFormat.bytes(values.down))/s ↑\(SystemMonitorFormat.bytes(values.up))/s"
        }
    }

    /// SF Symbol for the status button and the settings row.
    static func symbolName(metric: MenuBarMetric) -> String {
        switch metric {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .gpu: return "gpu"
        case .storage: return "internaldrive"
        case .battery: return "battery.75"
        case .network: return "network"
        }
    }

    /// Live SF Symbol for the status button: battery tracks current charge & charger state.
    static func symbolName(metric: MenuBarMetric, values: MenuBarStatValues) -> String {
        metric == .battery ? batterySymbol(values.battery) : symbolName(metric: metric)
    }

    static func batteryPillTone(_ battery: MenuBarBattery?) -> MenuBarBatteryPillTone {
        if battery?.isCharging == true { return .charging }
        let fraction = clamp01(battery?.fraction ?? 0)
        if fraction < 0.20 { return .critical }
        if fraction < 0.45 { return .warning }
        return .healthy
    }

    static func batteryPillLabel(_ battery: MenuBarBattery?) -> String {
        guard let battery else { return "–" }
        return "\(Int((clamp01(battery.fraction) * 100).rounded()))%"
    }

    /// Battery icon that tracks the level and the charger.
    static func batterySymbol(_ battery: MenuBarBattery?) -> String {
        guard let battery else { return "battery.0" }
        let base: String
        switch clamp01(battery.fraction) {
        case ..<0.15: base = "battery.0"
        case ..<0.40: base = "battery.25"
        case ..<0.65: base = "battery.50"
        case ..<0.90: base = "battery.75"
        default: base = "battery.100"
        }
        return battery.isCharging ? base + ".bolt" : base
    }

    /// Drawing data for the bar and pie styles.
    static func imageFraction(metric: MenuBarMetric, values: MenuBarStatValues) -> Double? {
        fraction(metric: metric, values: values)
    }

    private static func clamp01(_ value: Double) -> Double { min(1, max(0, value)) }
}

// MARK: - MB-1: Status Trio ring, Left-Click Creative Hub & Right-Click Simple Menu

enum MenuBarIconMode: String, CaseIterable, Sendable {
    case statusTrio, classic

    static let defaultsKey = "com.katikati.menuBar.iconMode"

    static func current(_ defaults: UserDefaults = .standard) -> MenuBarIconMode {
        defaults.string(forKey: defaultsKey).flatMap(MenuBarIconMode.init(rawValue:)) ?? .statusTrio
    }
}

enum StatusTrioStrokeWeight: String, CaseIterable, Sendable {
    case light, regular, bold

    static let defaultsKey = "com.katikati.menuBar.statusTrio.stroke"

    var lineWidth: Double {
        switch self {
        case .light: return 1.15
        case .regular: return 1.55
        case .bold: return 2.0
        }
    }

    static func current(_ defaults: UserDefaults = .standard) -> StatusTrioStrokeWeight {
        defaults.string(forKey: defaultsKey).flatMap(StatusTrioStrokeWeight.init(rawValue:)) ?? .regular
    }
}

enum MenuBarHubPrefs {
    static let semanticAlertsKey = "com.katikati.menuBar.statusTrio.semanticAlerts"
    static let compactReadoutKey = "com.katikati.menuBar.statusTrio.compactReadout"
    static let bluetoothInRingKey = "com.katikati.menuBar.statusTrio.bluetoothInRing"
}

struct StatusTrioRenderKey: Equatable, Hashable, Sendable {
    let batteryBucket: Int?
    let isCharging: Bool
    let isLowBattery: Bool
    let link: NetworkLinkKind
    let volumeDots: Int
    let isMuted: Bool
    let stroke: StatusTrioStrokeWeight
    let semanticColor: Bool
    let isDarkMenuBar: Bool
    let hasUpdateDot: Bool
    let readoutText: String?

    init(
        status: SystemStatus,
        stroke: StatusTrioStrokeWeight,
        semanticColor: Bool,
        showCompactReadout: Bool,
        showBluetoothAudio: Bool = true,
        isDarkMenuBar: Bool,
        hasUpdateDot: Bool
    ) {
        self.batteryBucket = status.battery.level.map { min(20, max(0, ($0 + 2) / 5)) }
        self.isCharging = status.battery.isCharging
        self.isLowBattery = status.isBatteryLow
        self.link = status.activeLink(showBluetoothAudio: showBluetoothAudio)
        self.volumeDots = Self.volumeDotCount(for: status.volume)
        self.isMuted = status.volume.isMuted
        self.stroke = stroke
        self.semanticColor = semanticColor
        self.isDarkMenuBar = isDarkMenuBar
        self.hasUpdateDot = hasUpdateDot
        self.readoutText = showCompactReadout ? Self.compactReadoutText(for: status) : nil
    }

    static func volumeDotCount(for volume: VolumeStatus) -> Int {
        if volume.isMuted || volume.level <= 0.01 { return 0 }
        if volume.level < 0.34 { return 1 }
        if volume.level < 0.67 { return 2 }
        return 3
    }

    static func compactReadoutText(for status: SystemStatus) -> String {
        if let level = status.battery.level { return "\(level)%" }
        return "\(status.volume.percent)%"
    }
}

enum MenuBarHubTab: String, CaseIterable, Identifiable, Sendable {
    case switches, statusAudio, shortcutsEvolutions, schedules

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .switches: return "switch.2"
        case .statusAudio: return "waveform.path.ecg"
        case .shortcutsEvolutions: return "bolt.horizontal.fill"
        case .schedules: return "calendar.badge.clock"
        }
    }

    static let visibleTabsKey = "com.katikati.menuBarHub.visibleTabs"

    static func visibleTabs(_ defaults: UserDefaults = .standard) -> [MenuBarHubTab] {
        guard let raw = defaults.string(forKey: visibleTabsKey) else { return allCases }
        var seen = Set<MenuBarHubTab>()
        let parsed = raw.split(separator: ",").compactMap { MenuBarHubTab(rawValue: String($0)) }.filter { seen.insert($0).inserted }
        return parsed.isEmpty ? allCases : parsed
    }

    static func serialize(_ tabs: [MenuBarHubTab]) -> String { tabs.map(\.rawValue).joined(separator: ",") }
}

enum HubActionSlotID: String, CaseIterable, Identifiable, Sendable {
    case keepAwake, darkMode, captureOCR, notchToggle
    case muteOutput, hideDesktopIcons, emptyTrash, lockScreen, nightShift, dockAutoHide

    var id: String { rawValue }
    static let defaultsKey = "com.katikati.menuBarHub.boxGrid"
    static let defaultSlots: [HubActionSlotID] = [.keepAwake, .darkMode, .captureOCR, .notchToggle]

    static func slots(_ defaults: UserDefaults = .standard) -> [HubActionSlotID] {
        var seen = Set<HubActionSlotID>()
        var result = (defaults.string(forKey: defaultsKey) ?? "")
            .split(separator: ",")
            .compactMap { HubActionSlotID(rawValue: String($0)) }
            .filter { seen.insert($0).inserted }
        for fallback in defaultSlots + allCases where result.count < 4 && seen.insert(fallback).inserted {
            result.append(fallback)
        }
        return Array(result.prefix(4))
    }

    static func serialize(_ slots: [HubActionSlotID]) -> String { slots.prefix(4).map(\.rawValue).joined(separator: ",") }
}

enum MenuBarRightClickConfig {
    static let defaultsKey = "com.katikati.menuBar.rightClickToggles"
    static let defaultTokens = ["keepAwake", "darkMode", "hideDesktopIcons", "muteOutput"]
    static let allowedTokens = ["keepAwake", "darkMode", "hideDesktopIcons", "muteOutput", "muteMic", "nightShift", "dockAutoHide", "showHiddenFiles"]

    static func toggleTokens(_ defaults: UserDefaults = .standard) -> [String] {
        guard let raw = defaults.string(forKey: defaultsKey) else { return defaultTokens }
        var seen = Set<String>()
        return raw.split(separator: ",").map(String.init)
            .filter { allowedTokens.contains($0) && seen.insert($0).inserted }
    }

    static func serialize(_ tokens: [String]) -> String {
        var seen = Set<String>()
        return tokens.filter { allowedTokens.contains($0) && seen.insert($0).inserted }.joined(separator: ",")
    }
}

// MARK: - MB-9…MB-11: opt-in modules

/// Tier B modules share one token list under one key. A missing key, an empty value or an unknown
/// token all mean **off**: a stale name must never start a module the owner did not enable, and every
/// module's heavy work (CoreAudio taps, shortcuts import, filesystem scans) is built only by its view,
/// so an off module costs nothing at launch.
enum HubModule: String, CaseIterable, Identifiable, Sendable {
    case agents, audioMixer, uninstaller

    var id: String { rawValue }

    static let storageKey = "com.katikati.menuBarHub.modules"

    static func enabled(_ raw: String?) -> Set<HubModule> {
        guard let raw else { return [] }
        return Set(raw.split(separator: ",").compactMap { HubModule(rawValue: String($0)) })
    }

    static func isEnabled(_ module: HubModule, raw: String?) -> Bool {
        enabled(raw).contains(module)
    }

    /// Canonical order, so the key is stable whichever order the boxes were ticked in.
    static func serialize(_ modules: Set<HubModule>) -> String {
        allCases.filter(modules.contains).map(\.rawValue).joined(separator: ",")
    }
}

/// Where the hub's pointer tip sits, in points from the panel's leading edge.
///
/// The tip tracks the status-item icon's centre so the panel visibly hangs off the icon in every
/// icon preset (trio glyph, compact readout, classic symbol, lyric-width item). Near a screen edge
/// the panel itself is pushed inside the visible frame, and the tip then stops at `edgeInset`
/// instead of sliding onto the panel's corner fillet — it still points at the icon, never off-panel.
enum HubCaretPlan {
    /// Height of the pointer strip added above the 560 pt body; the body is untouched.
    static let height: CGFloat = 10
    /// Half the pointer's base width (22 pt base, the same visual weight as a 20 pt glyph).
    static let halfWidth: CGFloat = 11
    /// Keeps the base clear of the 20 pt corner radius so the pointer never sits on the fillet.
    static let edgeInset: CGFloat = 22

    static func centerX(iconCenter: CGFloat, panelWidth: CGFloat) -> CGFloat {
        let minimum = halfWidth + edgeInset
        let maximum = panelWidth - minimum
        guard maximum >= minimum else { return panelWidth / 2 }
        return min(max(iconCenter, minimum), maximum)
    }
}
