import Foundation

// Phase 8b-6 — pure playback-progress maths for the Live Island's music surfaces.
//
// MediaRemote reports `elapsed` as of `timestamp`, not live; a surface that wants a moving bar must
// extrapolate `elapsed + rate * (now - timestamp)`. Kept pure (no MediaRemote, no clock reads — the
// caller passes `now`) so the clamps and the unknown-duration cases are unit-tested. Dual-compiled.

enum NowPlayingProgress {
    /// Seconds into the track right now, clamped to `0...duration` when a duration is known.
    static func elapsed(at now: Date, elapsed: TimeInterval?, asOf timestamp: Date?, rate: Double, duration: TimeInterval?) -> TimeInterval? {
        guard let elapsed, elapsed.isFinite, elapsed >= 0 else { return nil }
        var value = elapsed
        if rate > 0, let timestamp { value += rate * max(0, now.timeIntervalSince(timestamp)) }
        if let duration, duration.isFinite, duration > 0 { value = min(value, duration) }
        return value
    }

    /// 0...1, or `nil` when the duration is unknown / zero (a live stream) or the elapsed time is missing.
    static func fraction(at now: Date, elapsed: TimeInterval?, asOf timestamp: Date?, rate: Double, duration: TimeInterval?) -> Double? {
        guard let duration, duration.isFinite, duration > 0,
              let current = Self.elapsed(at: now, elapsed: elapsed, asOf: timestamp, rate: rate, duration: duration) else { return nil }
        return min(max(current / duration, 0), 1)
    }
}
