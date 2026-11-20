import Foundation

/// Recognises a Launchpad-style pinch from raw trackpad frames (Phase 7B launcher gesture).
/// Feed one frame per touch update; it returns true exactly once per pinch, when four or more fingers have
/// settled and then drawn together to `shrink` of their settled spread. Lifting to two fingers or fewer re-arms it.
struct PinchDetector {
    var minFingers = 4
    var shrink = 0.8
    var settleFrames = 4

    private var lastCount = 0
    private var stable = 0
    private var base: Double?
    private var fired = false

    mutating func feed(fingers: Int, spread: Double) -> Bool {
        if fingers <= 2 { reset(); fired = false; return false }
        if fingers != lastCount { lastCount = fingers; stable = 0; base = nil }
        guard fingers >= minFingers else { return false }
        stable += 1
        if stable == settleFrames { base = spread; return false }
        guard let base, !fired, base > 0, spread <= base * shrink else { return false }
        fired = true
        return true
    }

    private mutating func reset() { lastCount = 0; stable = 0; base = nil }

    /// Mean distance of the touch points from their centre (normalised trackpad units).
    static func spread(of points: [(x: Double, y: Double)]) -> Double {
        guard !points.isEmpty else { return 0 }
        let n = Double(points.count)
        let cx = points.reduce(0) { $0 + $1.x } / n, cy = points.reduce(0) { $0 + $1.y } / n
        return points.reduce(0) { $0 + (($1.x - cx) * ($1.x - cx) + ($1.y - cy) * ($1.y - cy)).squareRoot() } / n
    }
}

// MARK: - Multi-finger classification: raw frames in, one gesture out

struct GestureClassificationReducer: Equatable, Sendable {
    private var activeFingerCount = 0
    private var maxFingerCount = 0
    private var startCentroid: (x: Double, y: Double) = (0, 0)
    private var lastCentroid: (x: Double, y: Double) = (0, 0)
    private var startSpread: Double = 0
    private var startTime: Date?
    private var lastTriggeredAt: Date = .distantPast
    private var firedInCurrentTouch = false

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.activeFingerCount == rhs.activeFingerCount &&
        lhs.maxFingerCount == rhs.maxFingerCount &&
        lhs.startSpread == rhs.startSpread &&
        lhs.startTime == rhs.startTime &&
        lhs.lastTriggeredAt == rhs.lastTriggeredAt &&
        lhs.firedInCurrentTouch == rhs.firedInCurrentTouch
    }

    mutating func feed(
        points: [MultitouchPoint],
        at now: Date = Date(),
        config: GestureClassificationConfig = GestureClassificationConfig()
    ) -> MultitouchGestureKind? {
                guard !points.isEmpty else {
            defer { resetTouch() }
            guard !firedInCurrentTouch,
                  maxFingerCount == 3 || maxFingerCount == 4,
                  let start = startTime,
                  now.timeIntervalSince(start) <= config.tapMaxDuration,
                  now.timeIntervalSince(lastTriggeredAt) >= config.debounceInterval else {
                return nil
            }

            let travel = hypot(lastCentroid.x - startCentroid.x, lastCentroid.y - startCentroid.y)
            guard travel <= config.tapMaxTravel else { return nil }
            if maxFingerCount == 4 {
                lastTriggeredAt = now
                return .fourFingerTap
            }
            // A plain three-finger tap is macOS Look Up, so only a directional one fires here.
            let dx = lastCentroid.x - startCentroid.x
            guard abs(dx) >= 0.012 else { return nil }
            lastTriggeredAt = now
            return dx > 0 ? .threeFingerTipTapRight : .threeFingerTipTapLeft
        }

        let centroid = Self.centroid(of: points)
        let spread = Self.spread(of: points, centroid: centroid)
        lastCentroid = centroid

        if points.count != activeFingerCount {
            activeFingerCount = points.count
            maxFingerCount = max(maxFingerCount, points.count)
            startCentroid = centroid
            startSpread = spread
            if startTime == nil { startTime = now }
            return nil
        }

        guard !firedInCurrentTouch,
              points.count >= 2,
              now.timeIntervalSince(lastTriggeredAt) >= config.debounceInterval else {
            return nil
        }

        let dx = centroid.x - startCentroid.x
        let dy = centroid.y - startCentroid.y
        let avgVx = points.reduce(0.0) { $0 + $1.vx } / Double(points.count)

        if points.count == 3 || points.count == 4 {
            let isFlick = abs(avgVx) >= config.flickVelocityThreshold && abs(dx) >= config.swipeThreshold * 0.45
            let isTravelSwipe = abs(dx) >= config.swipeThreshold
            if (isFlick || isTravelSwipe), abs(dx) > abs(dy) * 1.3 {
                firedInCurrentTouch = true
                lastTriggeredAt = now
                if points.count == 3 {
                    return dx > 0 ? .threeFingerSwipeRight : .threeFingerSwipeLeft
                } else {
                    return dx > 0 ? .fourFingerSwipeRight : .fourFingerSwipeLeft
                }
            }
        }

        if points.count == 3 || points.count == 4 {
            let avgVy = points.reduce(0.0) { $0 + $1.vy } / Double(points.count)
            let isFlickY = abs(avgVy) >= config.flickVelocityThreshold && abs(dy) >= config.swipeThreshold * 0.45
            let isTravelY = abs(dy) >= config.swipeThreshold
            if (isFlickY || isTravelY), abs(dy) > abs(dx) * 1.3 {
                firedInCurrentTouch = true
                lastTriggeredAt = now
                if points.count == 3 {
                    return dy > 0 ? .threeFingerSwipeUp : .threeFingerSwipeDown
                }
                return dy > 0 ? .fourFingerSwipeUp : .fourFingerSwipeDown
            }
        }

        // Notification Center's edge swipe: two fingers starting in the right-edge band and moving
        // left. Two-finger travel anywhere else is page scrolling and stays untouched.
        if points.count == 2, startCentroid.x >= 0.88,
           dx <= -config.swipeThreshold * 0.6, abs(dx) > abs(dy) * 1.2 {
            firedInCurrentTouch = true
            lastTriggeredAt = now
            return .twoFingerRightEdgeSwipeLeft
        }

        if startSpread > 0.02 {
            let ratio = (spread - startSpread) / startSpread
            if ratio <= -config.pinchRatioThreshold {
                firedInCurrentTouch = true
                lastTriggeredAt = now
                return .pinchIn
            }
            if ratio >= config.pinchRatioThreshold {
                firedInCurrentTouch = true
                lastTriggeredAt = now
                return .pinchOut
            }
        }
        return nil
    }

    private mutating func resetTouch() {
        activeFingerCount = 0
        maxFingerCount = 0
        startCentroid = (0, 0)
        lastCentroid = (0, 0)
        startSpread = 0
        startTime = nil
        firedInCurrentTouch = false
    }

    private static func centroid(of points: [MultitouchPoint]) -> (x: Double, y: Double) {
        let inv = 1.0 / Double(points.count)
        return (points.reduce(0) { $0 + $1.x } * inv, points.reduce(0) { $0 + $1.y } * inv)
    }

    private static func spread(of points: [MultitouchPoint], centroid: (x: Double, y: Double)) -> Double {
        points.reduce(0.0) { $0 + hypot($1.x - centroid.x, $1.y - centroid.y) } / Double(points.count)
    }
}
