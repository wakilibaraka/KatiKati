import Foundation

// Phase 33a — NotchMotionSpec: Pure motion parameters and spring dynamics for the Notch.
// Follows Apple's WWDC Designing Fluid Interfaces guidelines (/apple-design):
// critically damped settles (dampingRatio = 1.0) to prevent bezel clipping,
// under-damped springs (dampingRatio ~0.8) for momentum/open gestures,
// velocity handoff, and reduced-motion timing. Dual-compiled in app and test targets.

struct SpringParameters: Equatable, Sendable {
    let response: Double
    let dampingRatio: Double

    init(response: Double, dampingRatio: Double) {
        self.response = response
        self.dampingRatio = dampingRatio
    }
}

enum NotchMotionSpec {
    /// Open transition: organic, tactile expansion with subtle momentum overshoot
    static let openSpring = SpringParameters(response: 0.38, dampingRatio: 0.82)

    /// Close transition: critically damped (1.0), snaps cleanly home with zero overshoot into bezel
    static let closeSpring = SpringParameters(response: 0.32, dampingRatio: 1.0)

    /// Sneak wing reveal/expand: snappy, low latency
    static let wingSneakSpring = SpringParameters(response: 0.24, dampingRatio: 0.74)

    /// Gallery page flip / section step
    static let pageStepSpring = SpringParameters(response: 0.28, dampingRatio: 0.84)

    /// Card micro-interaction (press down)
    static let cardPressSpring = SpringParameters(response: 0.16, dampingRatio: 0.60)

    /// Card micro-interaction (release / rebound)
    static let cardReleaseSpring = SpringParameters(response: 0.22, dampingRatio: 0.50)

    /// Reduced motion duration (cross-fade / static alpha)
    static let reducedMotionDuration: TimeInterval = 0.15

    /// Velocity projection helper following Apple's exponential decay formula:
    /// projected = current + (velocity / 1000.0) * d / (1 - d) where d ≈ 0.998
    static func projectEndpoint(current: Double, velocity: Double, decelerationRate: Double = 0.998) -> Double {
        guard decelerationRate > 0 && decelerationRate < 1.0 else { return current }
        let projectedOffset = (velocity / 1000.0) * decelerationRate / (1.0 - decelerationRate)
        return current + projectedOffset
    }
}
