import Foundation

// Phase 32a — the dock widgets' motion language as data. Pure: no AppKit, no SwiftUI.
//
// The notch's twin is `NotchMotionSpec`, and this file reuses its `SpringParameters`, so the two
// surfaces cannot disagree about what a spring is. What lives here is *which* spring a dock widget
// uses, and the one user-facing choice over it (`WidgetMotionPreset`), so a widget never hardcodes a
// curve and a test can pin the table without a screen.

/// One dock widget's motion: the Tier-1 content morph and the tile chrome's hover.
struct WidgetMotion: Equatable, Sendable {
    /// The spring a changed reading or track moves with. `nil` = the content cuts instead of moving.
    let contentSpring: SpringParameters?
    /// The tile's hover spring. `nil` = the tile does not move at all on hover.
    let hoverSpring: SpringParameters?
    /// The hover scale every dock tile already uses (`DockTileChrome`).
    let hoverScale: Double

    /// Whether a value change morphs (numeric text, symbol replace) or simply swaps.
    var morphsContent: Bool { contentSpring != nil }

    /// Today's feel, as shipped: the tile hover is `DockTileChrome`'s own 0.28/0.75 at 1.04, and the
    /// content spring is what the weather widgets' first morph uses.
    static let fluid = WidgetMotion(
        contentSpring: SpringParameters(response: 0.34, dampingRatio: 0.80),
        hoverSpring: SpringParameters(response: 0.28, dampingRatio: 0.75),
        hoverScale: 1.04)

    /// Faster and firmer: for anyone who finds the default soft.
    static let snappy = WidgetMotion(
        contentSpring: SpringParameters(response: 0.20, dampingRatio: 0.90),
        hoverSpring: SpringParameters(response: 0.18, dampingRatio: 0.88),
        hoverScale: 1.03)

    /// No motion at all — the Reduce Motion answer, and a real choice for everyone else.
    static let instant = WidgetMotion(contentSpring: nil, hoverSpring: nil, hoverScale: 1.0)

    /// Deliberately slower than Fluid: the dock's Settings card (Dockey-style presets) needs both
    /// ends of the scale, and a slower end cannot be expressed by the three above.
    static let slow = WidgetMotion(
        contentSpring: SpringParameters(response: 0.52, dampingRatio: 0.78),
        hoverSpring: SpringParameters(response: 0.46, dampingRatio: 0.72),
        hoverScale: 1.05)
}

/// The dock widgets' motion preset (Phase 32a). Stored under `storageKey`; the dock's Settings row and
/// the widgets themselves both read this one value.
enum WidgetMotionPreset: String, CaseIterable, Codable, Sendable {
    case fluid
    case snappy
    case instant
    case slow

    static let storageKey = "com.katikati.widgets.dockMotion"
    static let `default`: WidgetMotionPreset = .fluid

    /// The picker's label. `String(localized:)` over a whole literal, so the localizer sees every one
    /// of them (`Docs/SETTINGS.md` rule 9) — the older preset titles in `SystemGaugeModel.swift` are
    /// bare English and are left as they are; this table is new and has no excuse.
    var title: String {
        switch self {
        case .fluid: return String(localized: "Fluid")
        case .snappy: return String(localized: "Snappy")
        case .instant: return String(localized: "Instant")
        case .slow: return String(localized: "Slow")
        }
    }

    var motion: WidgetMotion {
        switch self {
        case .fluid: return .fluid
        case .snappy: return .snappy
        case .instant: return .instant
        case .slow: return .slow
        }
    }

    /// Reduce Motion always wins, exactly as `WidgetAnimationTiming.effective` does for the notch's own
    /// animation preset.
    func effective(reduceMotion: Bool) -> WidgetMotion {
        reduceMotion ? .instant : motion
    }

    /// The stored choice as motion (default Fluid), Reduce Motion applied.
    static func resolve(defaults: UserDefaults = .standard, reduceMotion: Bool) -> WidgetMotion {
        let chosen = defaults.string(forKey: storageKey).flatMap(WidgetMotionPreset.init(rawValue:)) ?? .default
        return chosen.effective(reduceMotion: reduceMotion)
    }
}

/// Dockey-style "Animation Delay" presets: how long the pointer has to rest at the dock's edge before
/// the dock slides back in. These are the same four steps `AppSettingsStore.edgeAutoHideDelay` runs
/// on, in seconds on its 0.1 s slider grid — `none` is that grid's floor, not zero, because zero would
/// round to the "always visible" sentinel and turn the dock off instead of making it quick.
///
/// Pure data: the Settings card reads it, the dock keeps reading the one stored delay, so there is no
/// second path into the panel.
enum DockRevealDelayPreset: String, CaseIterable, Codable, Sendable {
    case none
    case little
    case standard
    case aLot

    var title: String {
        switch self {
        case .none: return String(localized: "None")
        case .little: return String(localized: "Little")
        case .standard: return String(localized: "Default")
        case .aLot: return String(localized: "A lot")
        }
    }

    var seconds: Double {
        switch self {
        case .none: return 0.1
        case .little: return 0.3
        case .standard: return 0.6
        case .aLot: return 1.2
        }
    }

    /// The nearest preset for a stored delay; `nil` = the dock never hides, so no delay applies.
    /// Nearest rather than exact because the auto-hide slider writes every 0.1 s stop, and a card
    /// that only lit up on its own four values would look broken after one drag of that slider.
    static func matching(_ delay: Double) -> DockRevealDelayPreset? {
        guard delay.isFinite, delay > 0 else { return nil }
        return allCases.min { abs($0.seconds - delay) < abs($1.seconds - delay) }
    }
}
