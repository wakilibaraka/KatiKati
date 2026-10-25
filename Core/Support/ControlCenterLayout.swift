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

/// Visual preset of the Control Center: the original dock-themed panel, or the iPadOS-style glass bento.
enum ControlCenterStyle: String, CaseIterable, Sendable {
    case classic, ipad

    static let `default`: ControlCenterStyle = .classic
    static let storageKey = "com.katikati.controlcenter.style"

    static func parse(_ raw: String?) -> ControlCenterStyle {
        raw.flatMap(ControlCenterStyle.init(rawValue:)) ?? .default
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

/// The Control Center's switch grid: four toggles per row normally, five when four would run past the
/// screen and five saves a row. Pure so the choice is unit-tested instead of being eyeballed.
enum ControlCenterGrid {
    static let baseColumns = 4
    static let wideColumns = 5

    /// Rows the grid needs for `count` cells at `columns` per row. 0 for an empty grid.
    static func rows(count: Int, columns: Int) -> Int {
        guard count > 0, columns > 0 else { return 0 }
        return (count + columns - 1) / columns
    }

    /// Cells per row for a grid that has room for `rowsFit` rows. Four while the panel's height can
    /// hold that many; five when it cannot, so the grid narrows its rows instead of running off the
    /// panel. `rowsFit` is measured from the grid's own height, not from the screen.
    static func columns(count: Int, rowsFit: Int) -> Int {
        guard count > 0, rowsFit > 0 else { return baseColumns }
        return count <= rowsFit * baseColumns ? baseColumns : wideColumns
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
