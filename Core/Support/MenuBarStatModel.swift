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
        }
    }

    static func styles(for metric: MenuBarMetric) -> [MenuBarMetricStyle] {
        switch metric {
        case .cpu, .memory, .gpu: return [.percentage, .barGraph, .pieChart]
        case .storage: return [.percentage, .available, .used]
        case .battery: return [.percentage, .iconOnly]
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
        switch style {
        case .barGraph, .pieChart, .iconOnly:
            return ""
        case .percentage:
            return fraction(metric: metric, values: values).map(SystemMonitorFormat.percent) ?? "–"
        case .available:
            return SystemMonitorFormat.bytes(values.storageFreeBytes)
        case .used:
            return SystemMonitorFormat.bytes(Double(values.storageTotalBytes) - values.storageFreeBytes)
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
            return fraction(metric: .battery, values: values).map(SystemMonitorFormat.percent) ?? "–"
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
