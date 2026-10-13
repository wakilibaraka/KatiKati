import CoreGraphics
import Foundation

/// Which screen edge the dock strip sits on (Phase 18). Bottom is the original and the default;
/// left/right make the strip a vertical rail. Top is out of scope (the notch / Live Island own it).
enum StripPlacement: String, CaseIterable, Codable, Sendable {
    case bottom, left, right

    var isVertical: Bool { self != .bottom }

    /// The layout mode a placement actually renders. A side rail has a short main axis, so the
    /// five- and four-island splits fold into the three-island split (owner decision 1, 2026-10-13):
    /// top = launcher + weather, middle = apps (+ media), bottom = clock + widgets.
    func effectiveMode(_ mode: BarLayoutMode) -> BarLayoutMode {
        guard isVertical else { return mode }
        switch mode {
        case .split4, .split5: return .split3
        case .windows, .centered, .split3: return mode
        }
    }
}

/// Global placement plus optional per-display overrides (decision 5: one picker, per-display
/// override in Fine-tune). Persisted as one JSON blob at `defaultsKey`.
struct StripPlacementMap: Codable, Equatable, Sendable {
    static let defaultsKey = "com.katikati.layout.placement.v1"

    var global: StripPlacement = .bottom
    /// `displayUUID` → placement. A display without an entry follows `global`.
    var perDisplay: [String: StripPlacement] = [:]

    func placement(forDisplay displayUUID: String?) -> StripPlacement {
        guard let displayUUID, let override = perDisplay[displayUUID] else { return global }
        return override
    }

    /// Copy with `display`'s override set; passing the global value clears the override.
    func setting(_ placement: StripPlacement, forDisplay displayUUID: String) -> StripPlacementMap {
        var copy = self
        copy.perDisplay[displayUUID] = placement == global ? nil : placement
        return copy
    }

    static func decode(_ data: Data?) -> StripPlacementMap? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(StripPlacementMap.self, from: data)
    }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }
}

/// Main/cross axis abstraction (Phase 18a). Layout code solves every placement as if it were a
/// bottom strip — `IslandLayoutSolver` stays one horizontal engine — and this maps the result onto
/// the real edge. Bottom is the identity, so the bottom bar stays byte-identical.
///
/// Solver space for a side rail: x runs along the rail from its **top** end (`0 … mainLength`),
/// y is the distance from the screen edge (`bottomMargin` … `+ barHeight`).
enum StripAxis {
    /// Length available along the strip's main axis: the screen width for the bottom; for a rail,
    /// the screen height below `topInset` (menu bar / notch).
    static func mainLength(placement: StripPlacement, screen: CGRect, topInset: CGFloat) -> CGFloat {
        placement.isVertical ? max(0, screen.height - topInset) : screen.width
    }

    /// Maps a solver frame into screen space (bottom-left origin, AppKit). For `.bottom` the solver
    /// already ran in screen coordinates, so the frame comes back untouched.
    static func map(_ solved: CGRect, placement: StripPlacement, screen: CGRect, topInset: CGFloat) -> CGRect {
        switch placement {
        case .bottom:
            return solved
        case .left, .right:
            let top = screen.maxY - topInset
            let y = top - solved.maxX
            let thickness = solved.height
            let edgeDistance = solved.minY
            let x = placement == .left
                ? screen.minX + edgeDistance
                : screen.maxX - edgeDistance - thickness
            return CGRect(x: x, y: y, width: thickness, height: solved.width)
        }
    }

    /// The edge-distance a frame keeps clear on the strip's side of the screen — what windows must
    /// stay out of (window clearance, Phase 18e): bottom → height above `screen.minY`, left → width
    /// from `screen.minX`, right → width from `screen.maxX`.
    static func reservedInset(frame: CGRect, placement: StripPlacement, screen: CGRect) -> CGFloat {
        switch placement {
        case .bottom: return max(0, frame.maxY - screen.minY)
        case .left: return max(0, frame.maxX - screen.minX)
        case .right: return max(0, screen.maxX - frame.minX)
        }
    }
}

extension BarSection {
    /// Main-axis length of a widget as a compact square-ish tile on a side rail (decision 1:
    /// weather = glyph over temperature, clock = HH over MM, media = artwork square, the rest one
    /// icon slot). Scales with the bar thickness like every other strip metric.
    func railTileLength(barHeight: CGFloat) -> CGFloat {
        switch self {
        case .weather, .clock: return (barHeight * 1.15).rounded()
        case .media, .launcher, .widgets: return barHeight
        case .apps: return 0
        }
    }
}
