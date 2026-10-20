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
    /// How long an event toast stays open; its draining bar runs for exactly this long.
    static let eventLifetime: TimeInterval = 3.0

    /// Open transition: critically damped so the island settles without bouncing
    static let openSpring = SpringParameters(response: 0.38, dampingRatio: 1.0)

    /// Close transition: critically damped (1.0), snaps cleanly home with zero overshoot into bezel
    static let closeSpring = SpringParameters(response: 0.32, dampingRatio: 1.0)

    /// Sneak wing reveal/expand: snappy, low latency
    static let wingSneakSpring = SpringParameters(response: 0.24, dampingRatio: 1.0)

    /// Gallery page flip / section step
    static let pageStepSpring = SpringParameters(response: 0.28, dampingRatio: 1.0)

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

/// How the notch opens and closes. `boring` is the default and matches Boring Notch's springs
/// with no overshoot (all critically damped); only `bounce` overshoots, on request.
enum NotchOpenAnimation: String, CaseIterable, Identifiable, Sendable {
    case boring, liquid, snap, bounce

    static let defaultsKey = "com.katikati.notch.openAnimation"
    var id: String { rawValue }

    var openSpring: SpringParameters {
        switch self {
        case .boring: return SpringParameters(response: 0.38, dampingRatio: 1.0)
        case .liquid: return SpringParameters(response: 0.46, dampingRatio: 1.0)
        case .snap: return SpringParameters(response: 0.26, dampingRatio: 1.0)
        case .bounce: return SpringParameters(response: 0.5, dampingRatio: 0.58)
        }
    }

    var closeSpring: SpringParameters {
        switch self {
        case .boring: return SpringParameters(response: 0.45, dampingRatio: 1.0)
        case .liquid: return SpringParameters(response: 0.4, dampingRatio: 1.0)
        case .snap: return SpringParameters(response: 0.22, dampingRatio: 1.0)
        case .bounce: return SpringParameters(response: 0.42, dampingRatio: 0.9)
        }
    }

    /// Open content: plain fade, blur-and-scale pour, fade with a small drop, or a springy pop.
    enum Reveal: Sendable { case fade, pour, drop, pop }
    var reveal: Reveal {
        switch self {
        case .boring: return .fade
        case .liquid: return .pour
        case .snap: return .drop
        case .bounce: return .pop
        }
    }

    var title: String {
        switch self {
        case .boring: return "Classic"
        case .liquid: return "Liquid"
        case .snap: return "Snap"
        case .bounce: return "Bounce"
        }
    }

    var summary: String {
        switch self {
        case .boring: return "Smooth spring, light overshoot"
        case .liquid: return "Content pours in, soft settle"
        case .snap: return "Fast and crisp, no overshoot"
        case .bounce: return "Springy, clear overshoot"
        }
    }
}
