import Foundation

/// A damped spring parameterized by SwiftUI's `response` and `dampingFraction`, solved in closed form.
///
/// Mass is normalized to `1.0`, matching SwiftUI (`stiffness = (2π / response)²`,
/// `damping = 4π * dampingFraction / response`). Closed-form evaluation guarantees deterministic
/// seeking and zero numerical drift across variable display refresh rates (60 Hz / 120 Hz ProMotion).
public struct IslandSpringConfig: Equatable, Hashable, Sendable {
    public let response: Double
    public let dampingFraction: Double
    public let blendDuration: Double

    public init(response: Double, dampingFraction: Double, blendDuration: Double = 0) {
        self.response = response
        self.dampingFraction = dampingFraction
        self.blendDuration = blendDuration
    }
}

public struct IslandSpringState: Equatable, Sendable {
    public let x: Double
    public let v: Double

    public init(x: Double, v: Double) {
        self.x = x
        self.v = v
    }
}

/// Evaluates displacement and velocity `t` seconds after release from displacement `x0` with initial velocity `v0`.
public func solveIslandSpring(
    _ config: IslandSpringConfig,
    x0: Double,
    v0: Double,
    t: Double
) -> IslandSpringState {
    if t <= 0 {
        return IslandSpringState(x: x0, v: v0)
    }
    let response = max(config.response, 1e-4)
    let zeta = max(config.dampingFraction, 0)
    let w0 = (2.0 * .pi) / response

    if zeta < 1.0 {
        let wd = w0 * sqrt(1.0 - zeta * zeta)
        let decay = exp(-zeta * w0 * t)
        let b = (v0 + zeta * w0 * x0) / wd
        let cosVal = cos(wd * t)
        let sinVal = sin(wd * t)
        let x = decay * (x0 * cosVal + b * sinVal)
        let v = decay * (-zeta * w0 * (x0 * cosVal + b * sinVal) + (-x0 * wd * sinVal + b * wd * cosVal))
        return IslandSpringState(x: x, v: v)
    }

    if zeta == 1.0 {
        let decay = exp(-w0 * t)
        let b = v0 + w0 * x0
        let x = decay * (x0 + b * t)
        let v = decay * (b - w0 * (x0 + b * t))
        return IslandSpringState(x: x, v: v)
    }

    let root = sqrt(zeta * zeta - 1.0)
    let r1 = -w0 * (zeta - root)
    let r2 = -w0 * (zeta + root)
    let c2 = (v0 - r1 * x0) / (r2 - r1)
    let c1 = x0 - c2
    let e1 = exp(r1 * t)
    let e2 = exp(r2 * t)
    return IslandSpringState(
        x: c1 * e1 + c2 * e2,
        v: c1 * r1 * e1 + c2 * r2 * e2
    )
}

public enum IslandTransition: Equatable, Sendable {
    case spring(IslandSpringConfig, delay: Double = 0)
    case tween(duration: Double, delay: Double = 0)
    case instant

    public var delay: Double {
        switch self {
        case let .spring(_, delay): return delay
        case let .tween(_, delay): return delay
        case .instant: return 0
        }
    }
}

private indirect enum IslandSegment: Sendable {
    case `static`(value: Double)
    case spring(
        start: Double,
        from: Double,
        to: Double,
        v0: Double,
        spring: IslandSpringConfig,
        previous: IslandSegment?,
        issued: Double
    )
    case tween(
        start: Double,
        from: Double,
        to: Double,
        duration: Double,
        previous: IslandSegment?,
        issued: Double
    )

    var targetValue: Double {
        switch self {
        case let .static(value): return value
        case let .spring(_, _, to, _, _, _, _): return to
        case let .tween(_, _, to, _, _, _): return to
        }
    }

    var startTime: Double {
        switch self {
        case .static: return -.infinity
        case let .spring(start, _, _, _, _, _, _): return start
        case let .tween(start, _, _, _, _, _): return start
        }
    }

    var issuedTime: Double {
        switch self {
        case .static: return -.infinity
        case let .spring(_, _, _, _, _, _, issued): return issued
        case let .tween(_, _, _, _, _, issued): return issued
        }
    }

    var isStatic: Bool {
        if case .static = self { return true }
        return false
    }

    func stripped() -> IslandSegment {
        switch self {
        case .static:
            return self
        case let .spring(start, from, to, v0, spring, _, issued):
            return .spring(start: start, from: from, to: to, v0: v0, spring: spring, previous: nil, issued: issued)
        case let .tween(start, from, to, duration, _, issued):
            return .tween(start: start, from: from, to: to, duration: duration, previous: nil, issued: issued)
        }
    }
}

private func easeOutCubic(_ u: Double) -> Double {
    1.0 - pow(1.0 - u, 3.0)
}

private func islandSmoothstep(_ u: Double) -> Double {
    u * u * (3.0 - 2.0 * u)
}

private func sampleSegment(_ segment: IslandSegment, t: Double) -> (value: Double, velocity: Double) {
    switch segment {
    case let .static(value):
        return (value, 0)

    case let .tween(start, from, to, duration, previous, _):
        if t < start {
            return previous.map { sampleSegment($0, t: t) } ?? (from, 0)
        }
        if duration <= 0 {
            return (to, 0)
        }
        let clampedDuration = max(duration, 1e-4)
        let u = min(1.0, (t - start) / clampedDuration)
        let value = from + (to - from) * easeOutCubic(u)
        let velocity = u >= 1.0 ? 0.0 : ((to - from) * 3.0 * pow(1.0 - u, 2.0)) / clampedDuration
        return (value, velocity)

    case let .spring(start, from, to, v0, spring, previous, _):
        if t < start {
            return previous.map { sampleSegment($0, t: t) } ?? (from, 0)
        }
        let elapsed = t - start
        let solved = solveIslandSpring(spring, x0: from - to, v0: v0, t: elapsed)
        let next = (value: to + solved.x, velocity: solved.v)
        let blend = spring.blendDuration
        guard blend > 0, let previous, elapsed < blend else {
            return next
        }
        let old = sampleSegment(previous, t: t)
        let u = elapsed / blend
        let w = islandSmoothstep(u)
        let dw = (6.0 * u * (1.0 - u)) / blend
        return (
            old.value + (next.value - old.value) * w,
            old.velocity + (next.velocity - old.velocity) * w + (next.value - old.value) * dw
        )
    }
}

private func settledAfter(_ segment: IslandSegment) -> Double {
    switch segment {
    case .static:
        return -.infinity
    case let .tween(start, _, _, duration, _, _):
        return start + duration
    case let .spring(start, _, _, _, spring, _, _):
        return start + spring.blendDuration
    }
}

/// One animated scalar driven by closed-form springs and multi-leg plans.
public final class IslandAnimatedValue {
    private var segment: IslandSegment
    public let precision: Double

    public init(_ value: Double, precision: Double = 0.01) {
        self.segment = .static(value: value)
        self.precision = precision
    }

    public var target: Double {
        segment.targetValue
    }

    public func valueAt(_ t: Double) -> Double {
        sampleSegment(segment, t: t).value
    }

    public func velocityAt(_ t: Double) -> Double {
        sampleSegment(segment, t: t).velocity
    }

    /// Moves to `to` starting at clock time `t` (seconds), preserving velocity and supporting
    /// delayed multi-leg choreography and velocity hand-offs.
    public func set(
        _ to: Double,
        at t: Double,
        transition: IslandTransition,
        from: (value: Double, velocity: Double)? = nil
    ) {
        if case .instant = transition {
            segment = .static(value: to)
            return
        }

        let start = t + transition.delay
        let pending = !segment.isStatic && segment.startTime > t
        let queued = pending && segment.issuedTime == t && start >= segment.startTime

        let pendingPrevious: IslandSegment
        if !queued, case .spring(_, let segFrom, _, _, _, let prev, let issued) = segment, segment.startTime > t {
            pendingPrevious = prev ?? (issued != t ? .static(value: segFrom) : segment)
        } else if !queued, case .tween(_, let segFrom, _, _, let prev, let issued) = segment, segment.startTime > t {
            pendingPrevious = prev ?? (issued != t ? .static(value: segFrom) : segment)
        } else {
            pendingPrevious = segment
        }

        let flying = sampleSegment(pendingPrevious, t: t)
        let restingAt = pendingPrevious.targetValue
        let moving = abs(flying.value - restingAt) >= precision || abs(flying.velocity) >= precision * 10.0

        let handOff: Bool
        if let from, start > t, moving {
            handOff = abs(from.value - flying.value) >= precision || abs(from.velocity - flying.velocity) >= precision * 10.0
        } else {
            handOff = false
        }

        let inFlight: IslandSegment
        if handOff, let from {
            let handOffSpring: IslandSpringConfig
            switch pendingPrevious {
            case let .spring(_, _, _, _, pendingSpring, _, _):
                handOffSpring = pendingSpring
            default:
                switch transition {
                case let .spring(trSpring, _):
                    handOffSpring = trSpring
                case let .tween(duration, _):
                    handOffSpring = IslandSpringConfig(response: max(duration, 1e-3), dampingFraction: 1.0)
                case .instant:
                    handOffSpring = IslandSpringConfig(response: 1e-3, dampingFraction: 1.0)
                }
            }
            inFlight = .spring(
                start: t,
                from: from.value,
                to: pendingPrevious.targetValue,
                v0: from.velocity,
                spring: handOffSpring,
                previous: nil,
                issued: t
            )
        } else {
            inFlight = pendingPrevious
        }

        let now = handOff ? sampleSegment(inFlight, t: start) : (from ?? sampleSegment(inFlight, t: start))
        if to == target && abs(now.value - to) < precision && abs(now.velocity) < precision {
            return
        }

        switch transition {
        case .instant:
            segment = .static(value: to)
        case let .tween(duration, _):
            segment = .tween(
                start: start,
                from: now.value,
                to: to,
                duration: duration,
                previous: inFlight,
                issued: t
            )
        case let .spring(spring, _):
            let previous: IslandSegment?
            if inFlight.isStatic {
                previous = nil
            } else if queued || inFlight.startTime >= t {
                previous = inFlight
            } else {
                previous = inFlight.stripped()
            }
            segment = .spring(
                start: start,
                from: now.value,
                to: to,
                v0: now.velocity,
                spring: spring,
                previous: previous,
                issued: t
            )
        }
    }

    /// Returns true once settled by clock time `t`; collapses settled segments to `.static` for zero idle overhead.
    @discardableResult
    public func isAtRest(at t: Double) -> Bool {
        if segment.isStatic { return true }
        if t < settledAfter(segment) { return false }
        let sample = sampleSegment(segment, t: t)
        let targetVal = segment.targetValue
        let rest = abs(sample.value - targetVal) < precision && abs(sample.velocity) < precision * 10.0
        if rest {
            segment = .static(value: targetVal)
        }
        return rest
    }
}
