import CoreGraphics

/// The numbers behind the fluid rail body (the "Viscous" dock theme and edge-bar style): where the
/// lobes sit, how far the pointer swells one, and how narrow the waist between two items is.
///
/// The drawing half lives in `FluidRailBody` (SwiftUI); everything a test can pin is here.
enum FluidRailGeometry {
    /// The most the body may swell past the plate. Every floating panel keeps
    /// `PanelCoordinator.shadowPadding` (20 pt) of transparent room around its plate, so a bulge
    /// this size is drawn inside that room and never grows a window.
    static let maxSwell: CGFloat = 6

    /// The waist between two items, as a share of the plate's thickness. Below 1 the rail's two
    /// long edges undulate — that undulation is what reads as poured rather than as a rounded rect.
    static let neckRatio: CGFloat = 0.62

    /// How far a pointer's pull reaches past an item's centre, as a multiple of the lobe radius.
    /// Slightly over one radius so the two neighbours of the hovered item soften instead of
    /// stepping.
    static let swellReach: CGFloat = 1.35

    /// Waist thickness for a plate of `plate` across.
    static func coreThickness(plate: CGFloat) -> CGFloat { plate * neckRatio }

    /// Per-item swell for a pointer at `pointer` along the rail, each in `0...maxSwell`.
    ///
    /// A smoothstep, not a cone: a linear falloff leaves a visible crease on the lobe's shoulder.
    /// Ids are positional, so the result lines up with `centers` even when two items share a centre.
    static func swells(
        centers: [CGFloat],
        pointer: CGFloat?,
        radius: CGFloat,
        maxSwell: CGFloat = FluidRailGeometry.maxSwell
    ) -> [CGFloat] {
        guard let pointer, radius > 0 else { return Array(repeating: 0, count: centers.count) }
        let reach = radius * swellReach
        return centers.map { center in
            let distance = abs(pointer - center)
            guard distance < reach else { return 0 }
            let t = 1 - distance / reach
            return maxSwell * t * t * (3 - 2 * t)
        }
    }
}
