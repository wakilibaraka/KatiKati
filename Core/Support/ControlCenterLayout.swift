import CoreGraphics
import Foundation

/// Phase 16v: Control Center size presets. Width per preset; height is always content-sized
/// (the panel never scrolls). Raw values are stored in `com.katikati.controlcenter.size`.
enum ControlCenterSize: String, CaseIterable, Sendable {
    case small, medium, large

    static let `default`: ControlCenterSize = .medium
    static let storageKey = "com.katikati.controlcenter.size"

    /// Panel width per preset. Medium (360) is the pre-preset width, frozen.
    var width: CGFloat {
        switch self {
        case .small: return 300
        case .medium: return 360
        case .large: return 440
        }
    }

    static func parse(_ raw: String?) -> ControlCenterSize {
        raw.flatMap(ControlCenterSize.init(rawValue:)) ?? .default
    }
}

/// Vertical anchor of the Control Center panel on its edge. Top (default) is the pre-anchor
/// behavior: top-aligned under the menu bar. Bottom sits above the dock clearance.
enum ControlCenterAnchor: String, CaseIterable, Sendable {
    case top, center, bottom

    static let `default`: ControlCenterAnchor = .top
    static let storageKey = "com.katikati.controlcenter.anchor"

    static func parse(_ raw: String?) -> ControlCenterAnchor {
        raw.flatMap(ControlCenterAnchor.init(rawValue:)) ?? .default
    }
}

/// Control Center open animation. Instant (default) is the pre-animation behavior.
enum ControlCenterAnimation: String, CaseIterable, Sendable {
    case instant, fade, slide

    static let `default`: ControlCenterAnimation = .instant
    static let storageKey = "com.katikati.controlcenter.animation"

    static func parse(_ raw: String?) -> ControlCenterAnimation {
        raw.flatMap(ControlCenterAnimation.init(rawValue:)) ?? .default
    }
}
