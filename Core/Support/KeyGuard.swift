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
    /// Let the event through under a different key code / extra modifiers (Finder keys). Nothing is synthesized.
    case rewrite(keyCode: UInt16, addingModifiers: KeyModifiers)
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
    /// 53i: the frontmost app keeps its own ⌘Q (remote desktops, virtual machines).
    var slowQuitPassthrough = false
    /// 53b: the Finder key map is on and Finder is frontmost.
    var finderKeysActive = false
    /// 53c: snippet expansion is on and the frontmost app is not on its deny list.
    var snippetsActive = false
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

        guard state.slowQuitEnabled, state.slowQuitApplies, !state.slowQuitPassthrough else { return (.passThrough, next) }

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

/// 53b: Finder has no ⌘X. Rewrite ⌘X to ⌘C (the selection is copied and marked) and ⌘V to ⌘⌥V
/// ("move item here") while a cut is pending, so the Windows habit works without synthesizing keys.
/// Return already renames in Finder, so it is left alone.
/// `shortcut: rewrites inside a Finder text field too (rename / search), upgrade to a focused-element
/// check if that ever bites.`
struct FinderKeyMap: Equatable, Sendable {
    static let cutKey: UInt16 = 7
    static let copyKey: UInt16 = 8
    static let pasteKey: UInt16 = 9

    private(set) var cutPending = false
    private var rewroteCutUp = false
    private var rewrotePasteUp = false

    mutating func handle(_ event: KeyGuardEvent) -> KeyGuardDecision {
        switch event {
        case let .keyDown(code, mods) where mods.contains(.command):
            switch code {
            case Self.cutKey:
                cutPending = true
                rewroteCutUp = true
                return .rewrite(keyCode: Self.copyKey, addingModifiers: [])
            case Self.pasteKey where cutPending:
                cutPending = false
                rewrotePasteUp = true
                return .rewrite(keyCode: Self.pasteKey, addingModifiers: .option)
            default:
                return .passThrough
            }
        case let .keyUp(code, _):
            // The key-up must follow the rewritten key-down even if ⌘ was released first.
            if code == Self.cutKey, rewroteCutUp {
                rewroteCutUp = false
                return .rewrite(keyCode: Self.copyKey, addingModifiers: [])
            }
            if code == Self.pasteKey, rewrotePasteUp {
                rewrotePasteUp = false
                return .rewrite(keyCode: Self.pasteKey, addingModifiers: .option)
            }
            return .passThrough
        default:
            return .passThrough
        }
    }

    mutating func reset() {
        cutPending = false
        rewroteCutUp = false
        rewrotePasteUp = false
    }
}

/// 53i: apps where ⌘Q belongs to the remote session, not to the local window. SlowQuit leaves their
/// ⌘Q untouched instead of swallowing it into a hold.
/// `shortcut: native ⌘Q, no hold-to-confirm replay (that would need synthetic keys); upgrade if the
/// owner wants the confirmation kept for these apps.`
struct SlowQuitPassthrough: Equatable, Sendable {
    static let defaults = ["com.apple.ScreenSharing", "com.parallels.desktop.console",
                           "com.vmware.fusion", "com.utmapp.UTM"]

    var bundleIDs: Set<String> = Set(defaults)

    func applies(to bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return bundleIDs.contains(id)
    }

    /// Comma/whitespace separated, the same form the exception list uses. Empty means none.
    static func parse(_ raw: String) -> SlowQuitPassthrough {
        SlowQuitPassthrough(bundleIDs: Set(raw.split { $0 == "," || $0.isWhitespace }.map(String.init)))
    }
}

/// 53a: Caps Lock protection. A hold past `threshold` toggles Caps Lock once; a shorter tap does
/// nothing. Hyperkey remaps Caps Lock to F18 before the tap, so the guard is inert while it is on.
struct CapsLockGuard: Equatable, Sendable {
    /// Physical Caps Lock.
    static let keyCode: UInt16 = 57

    var threshold: TimeInterval = 0.15
    private(set) var isDown = false
    private(set) var toggled = false

    /// Returns true when the caller must schedule `fireIfStillHeld` after `threshold`.
    mutating func press() -> Bool {
        guard !isDown else { return false }
        isDown = true
        toggled = false
        return true
    }

    /// True exactly once per hold, and only while the key is still down.
    mutating func fireIfStillHeld() -> Bool {
        guard isDown, !toggled else { return false }
        toggled = true
        return true
    }

    mutating func release() { isDown = false }

    mutating func reset() {
        isDown = false
        toggled = false
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
