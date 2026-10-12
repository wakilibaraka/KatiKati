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
