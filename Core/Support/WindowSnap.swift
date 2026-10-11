import CoreGraphics

/// Window zones for the Windows flyout (Phase 7A-P6). The unit rectangles follow Hop's window snapper (MIT, NOTICE §8):
/// fractions of a screen's visible area with a bottom-left origin.
enum SnapPosition: String, CaseIterable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case center, maximize

    var unit: CGRect {
        let t = 1.0 / 3
        switch self {
        case .leftHalf: return CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: return CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf: return CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .bottomHalf: return CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .topLeft: return CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .topRight: return CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .bottomLeft: return CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .bottomRight: return CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .leftThird: return CGRect(x: 0, y: 0, width: t, height: 1)
        case .centerThird: return CGRect(x: t, y: 0, width: t, height: 1)
        case .rightThird: return CGRect(x: 2 * t, y: 0, width: t, height: 1)
        case .leftTwoThirds: return CGRect(x: 0, y: 0, width: 2 * t, height: 1)
        case .rightTwoThirds: return CGRect(x: t, y: 0, width: 2 * t, height: 1)
        case .center: return CGRect(x: 0.125, y: 0.1, width: 0.75, height: 0.8)
        case .maximize: return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
    }

    /// Target frame inside `visible` (Cocoa coordinates, bottom-left origin), whole points.
    func frame(in visible: CGRect) -> CGRect {
        let u = unit
        return CGRect(x: (visible.minX + u.minX * visible.width).rounded(),
                      y: (visible.minY + u.minY * visible.height).rounded(),
                      width: (u.width * visible.width).rounded(),
                      height: (u.height * visible.height).rounded())
    }

    /// Cocoa frame → Accessibility coordinates (origin at the top-left of the primary screen).
    static func accessibilityOrigin(of cocoa: CGRect, primaryMaxY: CGFloat) -> CGPoint {
        CGPoint(x: cocoa.minX, y: primaryMaxY - cocoa.maxY)
    }
}
