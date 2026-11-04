import Foundation

/// Peek: hold the key to look, tap it to keep the panels open. Pure, so the threshold is tested without a clock.
enum PeekHold {
    static let tapThreshold: TimeInterval = 0.25

    enum Outcome: Equatable { case keepOpen, hide }

    /// What to do when the key comes up after being down for `heldFor` seconds.
    static func outcome(heldFor: TimeInterval) -> Outcome { heldFor < tapThreshold ? .keepOpen : .hide }
}
