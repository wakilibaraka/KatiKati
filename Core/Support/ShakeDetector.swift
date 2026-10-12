import Foundation

// "Shake to shelf" — recognises a quick left-right shake of the pointer from `(x, time)` samples. Pure so
// the thresholds are unit-tested without a mouse. The app layer only feeds samples while a file drag is
// in progress. Dual-compiled.

struct ShakeDetector {
    /// Samples older than this are forgotten.
    var window: TimeInterval = 0.7
    /// Minimum travel, in points, for a stroke to count (ignores jitter and slow wobble).
    var minTravel: Double = 40
    /// Direction reversals needed (3 reversals = 4 strokes: right-left-right-left).
    var reversalsNeeded = 3
    /// After a shake fires, ignore further shakes for this long.
    var cooldown: TimeInterval = 1.5

    private var samples: [(x: Double, t: TimeInterval)] = []
    private var lastFired: TimeInterval?

    /// Feed one pointer sample; returns `true` on the sample that completes a shake.
    mutating func add(x: Double, at t: TimeInterval) -> Bool {
        samples.append((x, t))
        samples.removeAll { t - $0.t > window }
        if let lastFired, t - lastFired < cooldown { return false }
        guard reversals() >= reversalsNeeded else { return false }
        lastFired = t
        samples.removeAll()
        return true
    }

    mutating func reset() {
        samples.removeAll()
        lastFired = nil
    }

    private func reversals() -> Int {
        guard let first = samples.first else { return 0 }
        var direction = 0          // +1 moving right, -1 moving left, 0 undecided
        var extreme = first.x
        var count = 0
        for s in samples.dropFirst() {
            switch direction {
            case 0:
                if abs(s.x - extreme) >= minTravel { direction = s.x > extreme ? 1 : -1; extreme = s.x }
            case 1:
                if s.x > extreme { extreme = s.x } else if extreme - s.x >= minTravel { count += 1; direction = -1; extreme = s.x }
            default:
                if s.x < extreme { extreme = s.x } else if s.x - extreme >= minTravel { count += 1; direction = 1; extreme = s.x }
            }
        }
        return count
    }
}
