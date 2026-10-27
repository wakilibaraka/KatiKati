import SwiftUI

/// One poured mass for a rail: a narrower waist down its length, a lobe around every item, and the
/// lobe under the pointer cresting out of the silhouette. Used by both surfaces that wear the fluid
/// look (the dock rail theme and the Edge Bars style) so the two can never drift apart.
///
/// The numbers come from `FluidRailGeometry`; this file only draws them.
struct FluidRailShape: Shape {
    /// Item centres along the rail, in the shape's own space (points from its top/leading edge).
    var centers: [CGFloat]
    /// Half the plate's thickness at rest.
    var radius: CGFloat
    /// Per-centre swell (`FluidRailGeometry.swells`); a missing entry means none.
    var swells: [CGFloat] = []
    var vertical = true

    func path(in rect: CGRect) -> Path {
        let plate = vertical ? rect.width : rect.height
        let waist = min(FluidRailGeometry.coreThickness(plate: plate), plate)
        let across = vertical ? rect.midX : rect.midY
        let waistRect = vertical
            ? CGRect(x: across - waist / 2, y: rect.minY, width: waist, height: rect.height)
            : CGRect(x: rect.minX, y: across - waist / 2, width: rect.width, height: waist)
        var path = Path(roundedRect: waistRect, cornerRadius: waist / 2, style: .continuous)
        // No items: one centred lobe, for surfaces that are a single blob (the drawer capsule,
        // the edge bar's resting pill).
        let centers = centers.isEmpty ? [vertical ? rect.midY : rect.midX] : centers
        for (index, centre) in centers.enumerated() {
            let r = radius + (index < swells.count ? swells[index] : 0)
            guard r > 0 else { continue }
            let lobe = vertical
                ? CGRect(x: across - r, y: centre - r, width: 2 * r, height: 2 * r)
                : CGRect(x: centre - r, y: across - r, width: 2 * r, height: 2 * r)
            path = path.union(Path(ellipseIn: lobe))
        }
        return path
    }
}

struct FluidRailBody: View {
    var centers: [CGFloat]
    var radius: CGFloat
    var swells: [CGFloat] = []
    var vertical = true
    /// True when the screen edge — the side the light comes from — is the rect's leading/top edge.
    var lightAtStart = true
    /// Centre of the item under the pointer, for the inner crest; nil at rest.
    var crest: CGFloat?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: FluidRailShape {
        FluidRailShape(centers: centers, radius: radius, swells: swells, vertical: vertical)
    }

    private var startPoint: UnitPoint {
        vertical ? (lightAtStart ? .leading : .trailing) : (lightAtStart ? .top : .bottom)
    }
    private var endPoint: UnitPoint {
        vertical ? (lightAtStart ? .trailing : .leading) : (lightAtStart ? .bottom : .top)
    }

    var body: some View {
        shape
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.19, green: 0.19, blue: 0.21), location: 0),
                        .init(color: Color(red: 0.10, green: 0.10, blue: 0.12), location: 0.45),
                        .init(color: Color(red: 0.03, green: 0.03, blue: 0.04), location: 1),
                    ],
                    startPoint: startPoint,
                    endPoint: endPoint
                )
            )
            .overlay(crestGlow)
            .overlay(
                shape.stroke(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.52), location: 0),
                            .init(color: Color.white.opacity(0.16), location: 0.35),
                            .init(color: Color.white.opacity(0.05), location: 1),
                        ],
                        startPoint: startPoint,
                        endPoint: endPoint
                    ),
                    lineWidth: 0.75
                )
            )
            .compositingGroup()
            .allowsHitTesting(false)
    }

    /// The wet highlight under the pointer. Masked to the body, so it reads as light inside the
    /// fluid rather than a circle drawn on top of it.
    @ViewBuilder private var crestGlow: some View {
        if let crest {
            GeometryReader { proxy in
                let diameter = max(radius * 4.2, 1)
                Circle()
                    .fill(RadialGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: diameter / 2))
                    .frame(width: diameter, height: diameter)
                    .position(vertical
                              ? CGPoint(x: proxy.size.width / 2, y: crest)
                              : CGPoint(x: crest, y: proxy.size.height / 2))
            }
            .mask(shape)
            .allowsHitTesting(false)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.72), value: crest)
        }
    }
}
