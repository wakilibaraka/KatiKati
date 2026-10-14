import SwiftUI

// Phase 33b — NotchContinuousMaskShape: G2-continuous squircle and clothoid-flared ear masking
// for the Dynamic Island Notch. Dual-compiled.
//
// Supports two rendering modes:
// 1. Hardware Notch (`flaringTopEars = true`): Flaring concave top ears that meet the top screen bezel
//    at a 0° horizontal tangent, straight vertical sides, and continuous squircle bottom corners.
// 2. Floating Island (`flaringTopEars = false`): Symmetrical convex squircle on all four corners for
//    non-notched external displays.

struct NotchContinuousMaskShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var flaringTopEars: Bool

    init(
        topCornerRadius: CGFloat? = nil,
        bottomCornerRadius: CGFloat? = nil,
        flaringTopEars: Bool = true
    ) {
        self.topCornerRadius = topCornerRadius ?? NotchDesignSpec.closedCornerRadii.topFlaring
        self.bottomCornerRadius = bottomCornerRadius ?? NotchDesignSpec.closedCornerRadii.bottomSquircle
        self.flaringTopEars = flaringTopEars
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !rect.isNull, !rect.isInfinite, rect.size.width > 0, rect.size.height > 0 else {
            return path
        }

        let maxRadius = min(rect.width / 4, rect.height / 2)
        let topR = min(max(0, topCornerRadius), maxRadius)
        let bottomR = min(max(0, bottomCornerRadius), maxRadius)

        if flaringTopEars {
            // MARK: - Hardware Notch (Bezel-Flared Ears + Bottom Squircle)
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))

            // Left flaring ear: 0° horizontal tangent meeting bezel -> curves down to (minX + topR, minY + topR)
            path.addCurve(
                to: CGPoint(x: rect.minX + topR, y: rect.minY + topR),
                control1: CGPoint(x: rect.minX + topR * 0.45, y: rect.minY),
                control2: CGPoint(x: rect.minX + topR, y: rect.minY + topR * 0.55)
            )

            // Left vertical edge down to bottom squircle start
            path.addLine(to: CGPoint(x: rect.minX + topR, y: rect.maxY - bottomR))

            // Left bottom squircle (smooth G2 continuous curve)
            path.addCurve(
                to: CGPoint(x: rect.minX + topR + bottomR, y: rect.maxY),
                control1: CGPoint(x: rect.minX + topR, y: rect.maxY - bottomR * 0.44),
                control2: CGPoint(x: rect.minX + topR + bottomR * 0.44, y: rect.maxY)
            )

            // Bottom horizontal edge
            path.addLine(to: CGPoint(x: rect.maxX - topR - bottomR, y: rect.maxY))

            // Right bottom squircle
            path.addCurve(
                to: CGPoint(x: rect.maxX - topR, y: rect.maxY - bottomR),
                control1: CGPoint(x: rect.maxX - topR - bottomR * 0.44, y: rect.maxY),
                control2: CGPoint(x: rect.maxX - topR, y: rect.maxY - bottomR * 0.44)
            )

            // Right vertical edge up to right ear
            path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY + topR))

            // Right flaring ear: curves up and outward to 0° horizontal tangent at (maxX, minY)
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control1: CGPoint(x: rect.maxX - topR, y: rect.minY + topR * 0.55),
                control2: CGPoint(x: rect.maxX - topR * 0.45, y: rect.minY)
            )

            // Close back along top edge
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        } else {
            // MARK: - Floating Dynamic Island (Symmetrical 4-Corner Continuous Squircle)
            path.move(to: CGPoint(x: rect.minX + topR, y: rect.minY))

            // Top edge
            path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY))

            // Top-right squircle
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + topR),
                control1: CGPoint(x: rect.maxX - topR * 0.44, y: rect.minY),
                control2: CGPoint(x: rect.maxX, y: rect.minY + topR * 0.44)
            )

            // Right edge
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomR))

            // Bottom-right squircle
            path.addCurve(
                to: CGPoint(x: rect.maxX - bottomR, y: rect.maxY),
                control1: CGPoint(x: rect.maxX, y: rect.maxY - bottomR * 0.44),
                control2: CGPoint(x: rect.maxX - bottomR * 0.44, y: rect.maxY)
            )

            // Bottom edge
            path.addLine(to: CGPoint(x: rect.minX + bottomR, y: rect.maxY))

            // Bottom-left squircle
            path.addCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - bottomR),
                control1: CGPoint(x: rect.minX + bottomR * 0.44, y: rect.maxY),
                control2: CGPoint(x: rect.minX, y: rect.maxY - bottomR * 0.44)
            )

            // Left edge
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topR))

            // Top-left squircle
            path.addCurve(
                to: CGPoint(x: rect.minX + topR, y: rect.minY),
                control1: CGPoint(x: rect.minX, y: rect.minY + topR * 0.44),
                control2: CGPoint(x: rect.minX + topR * 0.44, y: rect.minY)
            )

            path.closeSubpath()
        }

        return path
    }
}
