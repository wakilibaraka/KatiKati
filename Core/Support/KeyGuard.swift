import Foundation

/// Phase 24a: the pure priority pipeline behind the single shared key tap. Given one key event and the
/// current guard state it decides what the tap does — pass it on, swallow it, or swallow it and fire an
/// action. No AppKit, no CGEventTap, no permission. Timing/policy/visualizer helpers live alongside.

/// Modifier bits (mirrors what the tap sees, without importing AppKit).
struct KeyModifiers: OptionSet, Equatable, Sendable {
    let rawValue: UInt8
    static let command = KeyModifiers(rawValue: 1 << 0)
    static let option = KeyModifiers(rawValue: 1 << 1)
    static let control = KeyModifiers(rawValue: 1 << 2)
    static let shift = KeyModifiers(rawValue: 1 << 3)
}

struct KeyChord: Equatable, Sendable {
    var keyCode: UInt16
    var modifiers: KeyModifiers
}

enum KeyGuardEvent: Equatable, Sendable {
    case keyDown(keyCode: UInt16, modifiers: KeyModifiers)
    case keyUp(keyCode: UInt16, modifiers: KeyModifiers)
}

enum KeyGuardAction: Equatable, Sendable {
    case unlock
    case slowQuitPressed
    case slowQuitReleased
}

enum KeyGuardDecision: Equatable, Sendable {
    /// Leave the event alone (the default when no guard is on).
    case passThrough
    /// Eat the event and do nothing.
    case swallow
    /// Eat the event and fire the action.
    case consumeAndFire(KeyGuardAction)
}

struct KeyGuardState: Equatable, Sendable {
    var paused = false
    var slowQuitEnabled = false
    /// `SlowQuitPolicy` result for the frontmost app (filled by the caller).
    var slowQuitApplies = false
    /// A ⌘Q hold is in progress.
    var slowQuitHolding = false
    /// The chord that unpauses. Pause swallows everything else.
    var unlockKey: KeyChord?
}

enum KeyGuardPipeline {
    /// Physical ⌘Q. `shortcut: keyboard-layout-dependent (US = 12); upgrade to keyCode-free matching if
    /// non-US layouts matter.`
    static let quitKeyCode: UInt16 = 12

    static func reduce(_ event: KeyGuardEvent, state: KeyGuardState) -> (decision: KeyGuardDecision, state: KeyGuardState) {
        var next = state

        if state.paused {
            if case .keyDown(let code, let mods) = event, isUnlock(code, mods, state) {
                next.paused = false
                return (.consumeAndFire(.unlock), next)
            }
            return (.swallow, next)
        }

        guard state.slowQuitEnabled, state.slowQuitApplies else { return (.passThrough, next) }

        switch event {
        case .keyDown(quitKeyCode, let mods) where mods.contains(.command):
            next.slowQuitHolding = true
            return (.consumeAndFire(.slowQuitPressed), next)
        case .keyUp(quitKeyCode, _) where state.slowQuitHolding:
            next.slowQuitHolding = false
            return (.consumeAndFire(.slowQuitReleased), next)
        default:
            return (.passThrough, next)
        }
    }

    static func isUnlock(_ code: UInt16, _ mods: KeyModifiers, _ state: KeyGuardState) -> Bool {
        guard let key = state.unlockKey else { return false }
        return code == key.keyCode && mods == key.modifiers
    }
}

/// Phase 24a: hold-to-quit timing. Injected clock keeps it testable.
struct SlowQuitTiming: Equatable, Sendable {
    var threshold: TimeInterval = 0.6

    func progress(heldFor: TimeInterval) -> Double {
        guard threshold > 0 else { return 1 }
        return min(max(heldFor / threshold, 0), 1)
    }

    func shouldFire(heldFor: TimeInterval) -> Bool { heldFor >= threshold }
}

/// Phase 24a: which apps SlowQuit applies to. `allow == nil` means "all except `deny`".
struct SlowQuitPolicy: Equatable, Sendable {
    var allow: Set<String>?
    var deny: Set<String> = []

    func applies(to bundleID: String?) -> Bool {
        guard let id = bundleID else { return allow == nil }
        if deny.contains(id) { return false }
        if let allow { return allow.contains(id) }
        return true
    }
}

/// Phase 24a: one keycap in the visualizer overlay.
struct KeycapVisual: Equatable, Sendable {
    var symbol: String
    var time: Date
}

/// Phase 24a: a bounded, coalescing ring of recent keycaps. Never unbounded, never persisted.
struct KeyVisualizerBuffer: Equatable, Sendable {
    static let capacity = 6
    private(set) var items: [KeycapVisual] = []

    /// A repeat of the last symbol just refreshes its time (coalescing); the ring drops the oldest past `capacity`.
    mutating func push(symbol: String, at time: Date) {
        if let last = items.last, last.symbol == symbol {
            items[items.count - 1].time = time
            return
        }
        items.append(KeycapVisual(symbol: symbol, time: time))
        if items.count > Self.capacity { items.removeFirst(items.count - Self.capacity) }
    }

    mutating func prune(olderThan interval: TimeInterval, now: Date) {
        items.removeAll { now.timeIntervalSince($0.time) > interval }
    }

    mutating func clear() { items.removeAll() }
}
