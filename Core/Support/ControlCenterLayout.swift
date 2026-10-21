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

/// 57a: wheel travel on the Control Center volume row. Six points of trackpad travel (or half a mouse-wheel
/// click) is 1.25 % volume, and at most one step per 60 ms so a momentum burst cannot jump the level.
enum ControlCenterScroll {
    static let travelPerStep: CGFloat = 6
    static let volumePerStep: Double = 0.0125
    static let stepInterval: TimeInterval = 0.06
    /// A notched wheel has lines, not points; one click counts as two steps' worth of travel.
    static let notchSteps = 2

    /// What a gesture carries between events. Leftovers under one step are kept, so slow scrolling adds up.
    struct State: Equatable {
        var travel: CGFloat = 0
        var lastStepAt: Date = .distantPast
    }

    /// Scrolling away from the user (positive `deltaY`) raises the volume. Returns the new level when a step
    /// is due, nil while travel is still adding up or the rate limit holds it back.
    static func consume(deltaY: CGFloat, precise: Bool, level: Double, state: inout State,
                        now: Date = Date()) -> Double? {
        guard deltaY != 0 else { return nil }
        state.travel += precise ? deltaY : (deltaY < 0 ? -1 : 1) * CGFloat(notchSteps) * travelPerStep
        let steps = (state.travel / travelPerStep).rounded(.towardZero)
        guard steps != 0, now.timeIntervalSince(state.lastStepAt) >= stepInterval else { return nil }
        state.travel -= steps * travelPerStep
        state.lastStepAt = now
        return min(1, max(0, level + Double(steps) * volumePerStep))
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
