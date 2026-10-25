import CoreGraphics
import Foundation

/// Which screen edge the dock strip sits on (Phase 18). Bottom is the original and the default;
/// left/right make the strip a vertical rail. Top is out of scope (the notch / Live Island own it).
enum StripPlacement: String, CaseIterable, Codable, Sendable {
    case bottom, left, right

    var isVertical: Bool { self != .bottom }

    // Phase 41a: a rail renders every layout mode as itself. Phase 18's fold of split4/split5 into
    // split3 is gone (owner 2026-10-15: "all layout mode changes should also apply vertically"), so a
    // rail's island count is always `BarLayoutMode.slotCount` — placement only transposes the axis.
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

    /// Inverse of `map` (with no top inset — offsets cancel in relative tests): a screen point in
    /// bottom-strip space, so screen-space rules written for the bottom bar (`StripPointerBox`)
    /// classify a rail the same way. Main axis = distance down from the top, cross = from the edge.
    static func unmap(_ point: CGPoint, placement: StripPlacement, screen: CGRect) -> CGPoint {
        switch placement {
        case .bottom: return point
        case .left: return CGPoint(x: screen.maxY - point.y, y: point.x - screen.minX)
        case .right: return CGPoint(x: screen.maxY - point.y, y: screen.maxX - point.x)
        }
    }

    static func unmap(_ rect: CGRect, placement: StripPlacement, screen: CGRect) -> CGRect {
        guard placement.isVertical else { return rect }
        let a = unmap(CGPoint(x: rect.minX, y: rect.minY), placement: placement, screen: screen)
        let b = unmap(CGPoint(x: rect.maxX, y: rect.maxY), placement: placement, screen: screen)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// How far a screen point is from the edge the strip sits on — the auto-hide hot zone and edge
    /// wake measure this instead of "height above the screen bottom" (Phase 18f).
    static func distanceFromStripEdge(_ point: CGPoint, placement: StripPlacement, screen: CGRect) -> CGFloat {
        switch placement {
        case .bottom: return point.y - screen.minY
        case .left: return point.x - screen.minX
        case .right: return screen.maxX - point.x
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
    /// Main-axis length of a widget as a compact square tile on a side rail (Phase 40b / Phase 49:
    /// every rail widget tile — weather, clock, media, launcher, widgets — is a 40×40 square matching
    /// `ChipPillMetrics.cardWidth`). Scales with the bar thickness like every other strip metric.
    func railTileLength(barHeight: CGFloat) -> CGFloat {
        switch self {
        case .weather, .clock, .media, .launcher, .widgets, .calendar, .system, .devices: return Self.railTileSize
        case .apps: return 0
        }
    }

    /// Native side of a rail tile. Matches `ChipPillMetrics.cardWidth`, the app chips it sits among.
    static let railTileSize: CGFloat = 40
}

/// Which side of a chip the running dot hugs: **the screen edge**, the same rule the bottom bar already
/// follows (its dot sits at the bottom). Phase 18c put a rail's dot on the workspace-facing edge instead,
/// which is why the bottom bar and the rail disagreed — corrected in Phase 40c. On a left rail the screen
/// edge is the leading side; on a right rail the trailing one.
///
/// The type lives here rather than beside its SwiftUI consumers for the repo's own reason (Standing Rules
/// §2.2): it is a pure decision of the placement, and `App/Scenes` is not compiled into the test target — a
/// rule stated only there cannot be pinned by a test, which is exactly how the old mapping survived. The
/// SwiftUI half (`alignment`, `paddingEdge`) stays in `ChipView.swift`.
enum RunningDotEdge: Equatable {
    case bottom, leading, trailing

    init(placement: StripPlacement) {
        switch placement {
        case .bottom: self = .bottom
        case .left: self = .leading
        case .right: self = .trailing
        }
    }
}

/// What happens to an edge bar when the dock strip moves onto its edge (Phase 18g, owner
/// 2026-10-13: "move across is default, merge all into one"). Raw values are stored in
/// `com.katikati.edge.conflictPolicy`; never rename them.
enum EdgeConflictPolicy: String, CaseIterable, Codable, Sendable {
    /// The bar moves to the opposite edge; if a bar is already there, both merge into one bar.
    case moveAcross
    /// The bar on the dock's edge is hidden while the dock is there.
    case hide

    static let defaultsKey = "com.katikati.edge.conflictPolicy"
}

/// Pure edge-bar occupancy once the dock may sit on a side (Phase 18g).
enum EdgeOccupancy {
    /// Edge-bar content per side after making room for a dock rail. The bottom dock changes nothing.
    /// Merging keeps the free side's items first and drops duplicates, order otherwise preserved.
    static func resolve<Item: Equatable>(_ content: [EdgeSide: [Item]], dock: StripPlacement,
                                         policy: EdgeConflictPolicy) -> [EdgeSide: [Item]] {
        let taken: EdgeSide
        switch dock {
        case .bottom: return content
        case .left: taken = .left
        case .right: taken = .right
        }
        guard let displaced = content[taken], !displaced.isEmpty else { return content }
        var result = content
        result[taken] = nil
        guard policy == .moveAcross else { return result }
        let other: EdgeSide = taken == .left ? .right : .left
        var merged = result[other] ?? []
        for item in displaced where !merged.contains(item) { merged.append(item) }
        result[other] = merged
        return result
    }
}
