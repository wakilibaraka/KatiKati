import Foundation

/// One step along the ribbon, produced by `StripScrollGesture`.
enum StripScrollStep: Equatable, Sendable {
    case next
    case previous
}

/// The "⌥ + scroll steps the strip" gesture, as arithmetic (RT-6's second half; the setting is
/// off by default).
///
/// A two-finger scroll arrives as a stream of small deltas, so stepping on every event would race
/// through the strip. This accumulates them and emits one step once the finger has travelled
/// `stepDistance`, then stays quiet for `cooldown` so one flick is one column. Momentum events are
/// dropped outright: they carry the rest of a flick and would otherwise step again on their own.
///
/// Sign convention follows `NSEvent.scrollingDelta`: negative (scroll down, or swipe left) moves
/// forward along the strip, positive moves back — the same way the content under the pointer would.
struct StripScrollGesture: Sendable {
    let stepDistance: Double
    let cooldown: TimeInterval
    private(set) var accumulated: Double = 0
    private(set) var lastStepAt: TimeInterval?

    init(stepDistance: Double = 60, cooldown: TimeInterval = 0.28) {
        self.stepDistance = max(1, stepDistance)
        self.cooldown = max(0, cooldown)
    }

    /// Forgets the travel so far — used when Option is released or the pointer leaves the strip.
    mutating func reset() {
        accumulated = 0
    }

    /// Feeds one scroll event; `horizontal`/`vertical` are its `scrollingDeltaX/Y`. The dominant
    /// axis wins, so a mostly-vertical trackpad scroll does not get read as a sideways step.
    mutating func feed(
        horizontal: Double,
        vertical: Double,
        isMomentum: Bool,
        at time: TimeInterval
    ) -> StripScrollStep? {
        guard !isMomentum else { accumulated = 0; return nil }
        let delta = abs(horizontal) >= abs(vertical) ? horizontal : vertical
        return feed(delta: delta, at: time)
    }

    mutating func feed(delta: Double, at time: TimeInterval) -> StripScrollStep? {
        guard delta != 0 else { return nil }
        if accumulated != 0, (delta < 0) != (accumulated < 0) { accumulated = 0 }
        accumulated += delta
        guard abs(accumulated) >= stepDistance else { return nil }
        if let lastStepAt, time - lastStepAt < cooldown { return nil }
        let step: StripScrollStep = accumulated < 0 ? .next : .previous
        accumulated = 0
        lastStepAt = time
        return step
    }
}
