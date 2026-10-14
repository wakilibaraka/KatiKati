import CoreGraphics
import Foundation

/// Pure mathematical geometry and hit-testing engine for radial dials / pie menus (Phase 31a).
/// Operates in standard screen/view coordinate space (x right, y down in SwiftUI).
enum RadialDialGeometry {

    enum HitResult: Equatable, Sendable {
        case center
        case sector(Int)
        case outside
    }

    /// Annular sector description in radians.
    struct Sector: Equatable, Sendable {
        let index: Int
        let count: Int
        let startAngle: CGFloat
        let endAngle: CGFloat
        let midAngle: CGFloat
        let innerRadius: CGFloat
        let outerRadius: CGFloat

        func centerPoint(in center: CGPoint, atFraction fraction: CGFloat = 0.5) -> CGPoint {
            let r = innerRadius + (outerRadius - innerRadius) * fraction
            return CGPoint(
                x: center.x + r * cos(midAngle),
                y: center.y + r * sin(midAngle)
            )
        }
    }

    /// Computes which sector or center hub contains `point`.
    /// - Parameters:
    ///   - point: The cursor or touch point.
    ///   - center: The origin center of the dial.
    ///   - count: Total number of sectors on this ring (must be >= 1).
    ///   - innerRadius: Radius of the center hub deadzone.
    ///   - outerRadius: Outer boundary of the wedge ring.
    ///   - startOffset: Angle for the center of sector 0 (default: -π/2, i.e. 12 o'clock / North).
    ///   - outerSlop: Extra outer threshold in points to allow fast flick gestures without dropping selection.
    static func hitTest(
        point: CGPoint,
        center: CGPoint,
        count: Int,
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        startOffset: CGFloat = -CGFloat.pi / 2,
        outerSlop: CGFloat = 40
    ) -> HitResult {
        guard count > 0 else { return .outside }

        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)

        if distance < innerRadius {
            return .center
        }

        if distance > (outerRadius + outerSlop) {
            return .outside
        }

        let delta = (2 * CGFloat.pi) / CGFloat(count)
        let angle = atan2(dy, dx) // Range [-π, π]

        // Shift angle relative to (startOffset - delta / 2) so sector 0 is centered at startOffset
        let baseAngle = startOffset - (delta / 2)
        var relativeAngle = angle - baseAngle

        let twoPi = 2 * CGFloat.pi
        while relativeAngle < 0 { relativeAngle += twoPi }
        while relativeAngle >= twoPi { relativeAngle -= twoPi }

        let index = Int(relativeAngle / delta) % count
        return .sector(index)
    }

    /// Returns the sector geometry for all `count` wedges.
    static func sectors(
        count: Int,
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        startOffset: CGFloat = -CGFloat.pi / 2
    ) -> [Sector] {
        guard count > 0 else { return [] }
        let delta = (2 * CGFloat.pi) / CGFloat(count)

        return (0..<count).map { i in
            let mid = startOffset + CGFloat(i) * delta
            let start = mid - (delta / 2)
            let end = mid + (delta / 2)

            return Sector(
                index: i,
                count: count,
                startAngle: start,
                endAngle: end,
                midAngle: mid,
                innerRadius: innerRadius,
                outerRadius: outerRadius
            )
        }
    }
}
