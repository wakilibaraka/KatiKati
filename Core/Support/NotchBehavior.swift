import Foundation

// Dynamic Island behavior choices (ported in spirit from vorssaint-utils, GPL-3.0): how the island opens,
// how long it waits, and which screen it lives on. Pure and dual-compiled; the settings pane and
// `NotchPanelController` both read through here.

enum NotchOpenMode: String, CaseIterable, Identifiable, Sendable {
    case hover, click
    var id: String { rawValue }
    static let defaultsKey = "com.katikati.notch.openMode"
    static func current(_ d: UserDefaults = .standard) -> NotchOpenMode {
        NotchOpenMode(rawValue: d.string(forKey: defaultsKey) ?? "") ?? .hover
    }
}

enum NotchDisplayChoice: String, CaseIterable, Identifiable, Sendable {
    case automatic, builtIn, main
    var id: String { rawValue }
    static let defaultsKey = "com.katikati.notch.display"
    static func current(_ d: UserDefaults = .standard) -> NotchDisplayChoice {
        NotchDisplayChoice(rawValue: d.string(forKey: defaultsKey) ?? "") ?? .automatic
    }
}

/// 51f: which island design a display gets. A Mac's notch screen defaults to the notch, every other
/// display to the wide bar (no cutout to hug); the owner overrides per display. Stored as a
/// `[displayID: rawValue]` dictionary under `defaultsKey`.
enum NotchDesign: String, CaseIterable, Identifiable, Sendable {
    case notch, wideBar, off
    var id: String { rawValue }
    static let defaultsKey = "com.katikati.notch.displayDesigns"

    static func stored(_ d: UserDefaults = .standard) -> [String: NotchDesign] {
        (d.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]).compactMapValues(NotchDesign.init(rawValue:))
    }

    static func set(_ design: NotchDesign, for display: String, _ d: UserDefaults = .standard) {
        var raw = d.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        raw[display] = design.rawValue
        d.set(raw, forKey: defaultsKey)
    }

    static func resolve(display: String, hasHardwareNotch: Bool, stored: [String: NotchDesign]) -> NotchDesign {
        stored[display] ?? (hasHardwareNotch ? .notch : .wideBar)
    }
}

/// What the closed island shows when nothing is live (vorssaint-utils' "At rest"). `dockChips` is
/// KatiKati's original storage + battery pair.
enum NotchRestContent: String, CaseIterable, Identifiable, Sendable {
    case dockChips, battery, nothing
    var id: String { rawValue }
    static let defaultsKey = "com.katikati.notch.restContent"
    static func current(_ d: UserDefaults = .standard) -> NotchRestContent {
        NotchRestContent(rawValue: d.string(forKey: defaultsKey) ?? "") ?? .dockChips
    }
}

enum NotchBehavior {
    static let lowBatteryTintKey = "com.katikati.notch.lowBatteryTint"
    static let lowBatteryThresholdKey = "com.katikati.notch.lowBatteryThreshold"
    static let defaultLowBatteryThreshold = 20
    static let lowBatteryRange = 5...50
    static func lowBatteryThreshold(_ d: UserDefaults = .standard) -> Int {
        let v = d.object(forKey: lowBatteryThresholdKey) as? Int ?? defaultLowBatteryThreshold
        return min(lowBatteryRange.upperBound, max(lowBatteryRange.lowerBound, v))
    }

    static let hoverDelayKey = "com.katikati.notch.hoverDelay"
    static let closeDelayKey = "com.katikati.notch.closeDelay"
    static let hapticKey = "com.katikati.notch.haptic"
    static let defaultHoverDelay = 0.12
    static let defaultCloseDelay = 0.25
    static let hoverDelayRange = 0.10...1.0
    static let closeDelayRange = 0.10...2.0

    static func clamp(_ v: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        v.isFinite ? min(range.upperBound, max(range.lowerBound, v)) : fallback
    }

    static func hoverDelay(_ d: UserDefaults = .standard) -> Double {
        clamp(d.object(forKey: hoverDelayKey) as? Double ?? defaultHoverDelay, hoverDelayRange, fallback: defaultHoverDelay)
    }

    static func closeDelay(_ d: UserDefaults = .standard) -> Double {
        clamp(d.object(forKey: closeDelayKey) as? Double ?? defaultCloseDelay, closeDelayRange, fallback: defaultCloseDelay)
    }

    static func haptic(_ d: UserDefaults = .standard) -> Bool {
        d.object(forKey: hapticKey) as? Bool ?? true
    }
}

/// Open-panel size presets, after vorssaint-utils' Layout tab. KatiKati's pages are laid out at one size
/// and scaled, so a preset is a width multiplier (height follows the aspect ratio).
enum NotchSizePreset: String, CaseIterable {
    case compact, standard, spacious, custom

    static let defaultsKey = "com.katikati.notch.sizePreset"
    static let customScaleKey = "com.katikati.notch.customScale"
    static let customScaleRange = 0.70...1.30
    static let outlineKey = "com.katikati.notch.outline"
    static let translucentKey = "com.katikati.notch.translucent"

    static func scale(preset raw: String, custom: Double) -> CGFloat {
        switch NotchSizePreset(rawValue: raw) ?? .standard {
        case .compact: return 0.85
        case .standard: return 1
        case .spacious: return 1.2
        case .custom: return CGFloat(NotchBehavior.clamp(custom, customScaleRange, fallback: 1))
        }
    }

    static func current(_ d: UserDefaults = .standard) -> CGFloat {
        scale(preset: d.string(forKey: defaultsKey) ?? "", custom: d.object(forKey: customScaleKey) as? Double ?? 1)
    }
}
