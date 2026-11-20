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
    case flagsChanged(modifiers: KeyModifiers)
}

enum KeyGuardAction: Equatable, Sendable {
    case unlock
    case slowQuitPressed
    case slowQuitReleased
}

enum SlowQuitMode: String, CaseIterable, Identifiable, Sendable {
    case hold
    case doubleTap
    var id: String { rawValue }
}

enum SlowQuitListMode: String, CaseIterable, Identifiable, Sendable {
    case allExceptListed
    case onlyListedApps
    var id: String { rawValue }
}

enum SlowQuitOverlayStyle: String, CaseIterable, Identifiable, Sendable {
    case ring
    case bar
    var id: String { rawValue }
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
    /// macOS Secure Input is active (password fields / auth prompts): SlowQuit must not intercept keys.
    var secureInputActive = false
}

enum KeyGuardPipeline {
    /// Physical ⌘Q. `shortcut: keyboard-layout-dependent (US = 12); upgrade to keyCode-free matching if
    /// non-US layouts matter.`
    static let quitKeyCode: UInt16 = 12
    static let escapeKeyCode: UInt16 = 53

    static func reduce(_ event: KeyGuardEvent, state: KeyGuardState, isRepeat: Bool = false) -> (decision: KeyGuardDecision, state: KeyGuardState) {
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
        case .keyDown(quitKeyCode, let mods) where mods == .command && !state.secureInputActive:
            if isRepeat {
                return (.swallow, next)
            }
            next.slowQuitHolding = true
            return (.consumeAndFire(.slowQuitPressed), next)
        case .keyDown(escapeKeyCode, _) where state.slowQuitHolding:
            next.slowQuitHolding = false
            return (.consumeAndFire(.slowQuitReleased), next)
        case .keyUp(quitKeyCode, _) where state.slowQuitHolding:
            next.slowQuitHolding = false
            return (.consumeAndFire(.slowQuitReleased), next)
        case .flagsChanged(let mods) where state.slowQuitHolding && !mods.contains(.command):
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

enum CapsLockProtectionMode: String, CaseIterable, Identifiable, Sendable {
    case hold
    case doubleTap
    var id: String { rawValue }
}

/// 53a: Caps Lock protection. A hold past `threshold` (or double-tap in `.doubleTap` mode) toggles
/// Caps Lock once; a shorter single tap does nothing. Hyperkey remaps Caps Lock to F18 before the
/// tap, so the guard is inert while Hyperkey uses Caps Lock.
struct CapsLockGuard: Equatable, Sendable {
    /// Physical Caps Lock.
    static let keyCode: UInt16 = 57

    var threshold: TimeInterval = 0.15
    private(set) var isDown = false
    private(set) var toggled = false
    private(set) var lastTapAt: Date?

    /// Returns true when the caller must schedule `fireIfStillHeld` after `threshold`.
    mutating func press() -> Bool {
        guard !isDown else { return false }
        isDown = true
        toggled = false
        return true
    }

    /// True if two quick taps occur within `window` (for `.doubleTap` mode).
    mutating func registerDoubleTap(at now: Date = Date(), window: TimeInterval = 0.35) -> Bool {
        if let last = lastTapAt, now.timeIntervalSince(last) <= window {
            lastTapAt = nil
            return true
        }
        lastTapAt = now
        return false
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
        lastTapAt = nil
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

/// Supercharge-style double-tap ⌘Q timing. First tap arms a short window; second tap within `window` fires.
struct SlowQuitDoubleTapTiming: Equatable, Sendable {
    var window: TimeInterval = 0.5
    private(set) var lastTapAt: Date?

    enum Step: Equatable, Sendable {
        case armed
        case fire
    }

    mutating func registerTap(at now: Date = Date()) -> Step {
        if let last = lastTapAt, now.timeIntervalSince(last) <= window {
            lastTapAt = nil
            return .fire
        }
        lastTapAt = now
        return .armed
    }

    mutating func reset() { lastTapAt = nil }
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

enum KeyVisualizerFilter: String, CaseIterable, Identifiable, Sendable {
    case allKeys
    case modifiedKeys
    case commandKeysOnly
    var id: String { rawValue }
}

enum KeyVisualizerStyle: String, CaseIterable, Identifiable, Sendable {
    case glassCapsule
    case svelte
    case darkBezel
    var id: String { rawValue }
}

struct KeyVisualizerConfig: Equatable, Sendable {
    var filter: KeyVisualizerFilter = .allKeys
    var style: KeyVisualizerStyle = .glassCapsule
    var lingerDuration: TimeInterval = 1.5
    var fadeDuration: TimeInterval = 0.15
    var fontSize: Double = 15
    var showMouseClicks: Bool = false
    var isPositionUnlocked: Bool = false
}

enum KeyVisualizerSymbol {
    static let specialKeyGlyphs: [UInt16: String] = [
        36: "⏎",  // Return
        48: "⇥",  // Tab
        49: "␣",  // Space
        51: "⌫",  // Delete
        53: "⎋",  // Escape
        76: "⌤",  // Enter (numpad)
        115: "↖", // Home
        116: "⇞", // Page Up
        117: "⌦", // Forward Delete
        119: "↘", // End
        121: "⇟", // Page Down
        123: "←", // Left Arrow
        124: "→", // Right Arrow
        125: "↓", // Down Arrow
        126: "↑", // Up Arrow
        122: "F1", 120: "F2", 99: "F3", 118: "F4",
        96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12"
    ]

    static func format(
        keyCode: UInt16,
        modifiers: KeyModifiers,
        characters: String?,
        filter: KeyVisualizerFilter
    ) -> String? {
        switch filter {
        case .commandKeysOnly:
            guard modifiers.contains(.command) else { return nil }
        case .modifiedKeys:
            let hasShortcutMod = modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option)
            if !hasShortcutMod && specialKeyGlyphs[keyCode] == nil {
                return nil
            }
        case .allKeys:
            break
        }

        let base: String
        if let special = specialKeyGlyphs[keyCode] {
            base = special
        } else if let chars = characters, !chars.isEmpty,
                  let scalar = chars.unicodeScalars.first, scalar.value >= 0x20, scalar.value != 0x7F {
            base = modifiers.isEmpty ? chars : chars.uppercased()
        } else {
            return nil
        }

        var prefix = ""
        if modifiers.contains(.control) { prefix += "⌃" }
        if modifiers.contains(.option) { prefix += "⌥" }
        if modifiers.contains(.shift) { prefix += "⇧" }
        if modifiers.contains(.command) { prefix += "⌘" }
        return prefix.isEmpty ? base : prefix + base
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

// MARK: - Droppy-Inspired Slice C-KeyAudio: Keystroke Audio Feedback

/// Mechanical soundpack selection for keystroke audio feedback.
enum KeyAudioSoundpack: String, CaseIterable, Identifiable, Codable, Sendable {
    case mechanicalClick
    case typewriter
    case softThud
    case retroBeep

    var id: String { rawValue }
    static let defaultsKey = "com.katikati.keyguard.soundpack"
    static let enabledKey = "com.katikati.keyguard.keyAudio"

    static func current(_ d: UserDefaults = .standard) -> KeyAudioSoundpack {
        KeyAudioSoundpack(rawValue: d.string(forKey: defaultsKey) ?? "") ?? .mechanicalClick
    }
}

/// Evaluates whether a keystroke should trigger low-latency audio feedback based on privacy and context guards.
enum KeyAudioPolicy {
    /// Pure decision whether to trigger audio feedback on a key event.
    /// Strictly suppressed when:
    /// 1. Audio feedback is turned off
    /// 2. Not a keyDown event
    /// 3. Secure event input is enabled (password field protection)
    /// 4. Microphone / audio call is active (avoid meeting disturbance)
    /// 5. Keyboard input is paused (cleaning mode)
    static func shouldTrigger(
        event: KeyGuardEvent,
        enabled: Bool,
        isSecureInput: Bool,
        isCallActive: Bool,
        isPaused: Bool
    ) -> Bool {
        guard enabled else { return false }
        guard !isSecureInput else { return false }
        guard !isCallActive else { return false }
        guard !isPaused else { return false }

        switch event {
        case .keyDown:
            return true
        case .keyUp, .flagsChanged:
            return false
        }
    }
}

// MARK: - SuperCmd v2 / Droppy-Inspired Slice 2.1: Modifier Double-Tap Detector

enum ModifierKey: String, CaseIterable, Sendable, Codable {
    case command, option, control, shift
}

struct KeyModifierDoubleTapDetector: Sendable {
    let timeout: TimeInterval

    init(timeout: TimeInterval = 0.3) {
        self.timeout = timeout
    }

    private var lastRelease: (modifier: ModifierKey, time: Date)? = nil

    enum StepResult: Equatable, Sendable {
        case none
        case doubleTap(ModifierKey)
    }

    mutating func registerModifier(modifier: ModifierKey, isDown: Bool, at date: Date = Date()) -> StepResult {
        if isDown {
            if let last = lastRelease, last.modifier == modifier {
                let delta = date.timeIntervalSince(last.time)
                if delta >= 0 && delta <= timeout {
                    lastRelease = nil
                    return .doubleTap(modifier)
                }
            }
            return .none
        } else {
            lastRelease = (modifier: modifier, time: date)
            return .none
        }
    }

    mutating func registerInterveningKey() {
        lastRelease = nil
    }

    mutating func reset() {
        lastRelease = nil
    }
}

// MARK: - Slice GT-1: GutchinTouchTool-Inspired Multitouch Classifier & Velocity Reducer

struct MultitouchPoint: Equatable, Sendable {
    var id: Int32
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
}

enum MultitouchGestureKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case threeFingerSwipeLeft
    case threeFingerSwipeRight
    case fourFingerSwipeLeft
    case fourFingerSwipeRight
    case pinchIn
    case pinchOut
    case fourFingerTap
    // TG-1: the directions the brief calls for. Raw values persist, so existing mappings keep decoding.
    case threeFingerSwipeUp
    case threeFingerSwipeDown
    case fourFingerSwipeUp
    case fourFingerSwipeDown
    case twoFingerRightEdgeSwipeLeft
    case threeFingerTipTapLeft
    case threeFingerTipTapRight
    var id: String { rawValue }
}

enum GestureActionTarget: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case toggleNotch
    case commandBar
    case launcher
    case spaceLeft
    case spaceRight
    case snapLeft
    case snapRight
    /// Ribbon: step focus along the active display's strip (RT-6).
    case stripNext, stripPrevious
    // TG-1: the approved 6 window-management + 6 tiling set. Every case maps onto something the app
    // already does; the gesture layer only decides *when* it fires.
    case snapCycleLeft, snapCycleRight
    case maximize, centerRestore
    case windowSwitcher
    case nextDisplay, previousDisplay
    case toggleTiling
    case stripCycleWidth, stripStack, stripTabs, stripSwapNext, stripSwapPrevious
    case quickLayoutPicker
    var id: String { rawValue }
}

struct GestureClassificationConfig: Equatable, Sendable {
    var swipeThreshold: Double = 0.14
    var flickVelocityThreshold: Double = 0.65
    var pinchRatioThreshold: Double = 0.22
    var tapMaxDuration: TimeInterval = 0.28
    var tapMaxTravel: Double = 0.035
    var debounceInterval: TimeInterval = 0.35
}

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

// MARK: - Slice TG-1: trackpad bindings, context routing and macOS clash detection

/// Which macOS feature a gesture belongs to. `MultitouchSupport` is a listener, so KatiKati can
/// never stop the OS acting on a gesture — the best it can do is tell the user which slots are taken.
enum MacOSGestureOwner: String, CaseIterable, Sendable {
    case swipeBetweenPages, spaces, missionControl, appExpose
    case notificationCenter, appsPinch, showDesktop, lookUp
}

/// Three states, never two: the per-trackpad keys are undocumented and can disagree with what
/// System Settings shows, so "we could not verify" must not render as "clear".
enum GestureConflict: Equatable, Sendable {
    case clear
    case clash(MacOSGestureOwner)
    case unverifiable

    var isClash: Bool { if case .clash = self { return true }; return false }
}

/// What the trackpad preferences say, read once when Settings opens and otherwise untouched.
/// `nil` means the key was absent — not false.
struct TrackpadSettingsSnapshot: Equatable, Sendable {
    var threeFingerHorizSwipe: Bool?
    var threeFingerVertSwipe: Bool?
    var fourFingerHorizSwipe: Bool?
    var fourFingerVertSwipe: Bool?
    var fourFingerPinch: Bool?
    var fiveFingerPinch: Bool?
    var threeFingerTap: Bool?
    var twoFingerRightEdgeSwipe: Bool?
    /// `com.apple.dock`, which is where the modern toggles actually live.
    var missionControlGestureEnabled: Bool?
    var appExposeGestureEnabled: Bool?

    init(
        threeFingerHorizSwipe: Bool? = nil,
        threeFingerVertSwipe: Bool? = nil,
        fourFingerHorizSwipe: Bool? = nil,
        fourFingerVertSwipe: Bool? = nil,
        fourFingerPinch: Bool? = nil,
        fiveFingerPinch: Bool? = nil,
        threeFingerTap: Bool? = nil,
        twoFingerRightEdgeSwipe: Bool? = nil,
        missionControlGestureEnabled: Bool? = nil,
        appExposeGestureEnabled: Bool? = nil
    ) {
        self.threeFingerHorizSwipe = threeFingerHorizSwipe
        self.threeFingerVertSwipe = threeFingerVertSwipe
        self.fourFingerHorizSwipe = fourFingerHorizSwipe
        self.fourFingerVertSwipe = fourFingerVertSwipe
        self.fourFingerPinch = fourFingerPinch
        self.fiveFingerPinch = fiveFingerPinch
        self.threeFingerTap = threeFingerTap
        self.twoFingerRightEdgeSwipe = twoFingerRightEdgeSwipe
        self.missionControlGestureEnabled = missionControlGestureEnabled
        self.appExposeGestureEnabled = appExposeGestureEnabled
    }
}

/// Pure evaluator: a snapshot in, a badge out. The dock's enable flags win where they exist, because
/// they describe what the UI shows; the per-trackpad keys only say which finger count a feature uses.
enum TrackpadConflictDetector {
    static func conflict(for kind: MultitouchGestureKind, settings: TrackpadSettingsSnapshot) -> GestureConflict {
        switch kind {
        case .threeFingerSwipeLeft, .threeFingerSwipeRight:
            return decide(settings.threeFingerHorizSwipe, owner: .swipeBetweenPages)
        case .fourFingerSwipeLeft, .fourFingerSwipeRight:
            return decide(settings.fourFingerHorizSwipe, owner: .spaces)
        case .threeFingerSwipeUp:
            return dockGated(enabled: settings.missionControlGestureEnabled,
                             trackpad: settings.threeFingerVertSwipe, owner: .missionControl)
        case .threeFingerSwipeDown, .fourFingerSwipeUp, .fourFingerSwipeDown:
            return dockGated(enabled: settings.appExposeGestureEnabled,
                             trackpad: kind == .threeFingerSwipeDown ? settings.threeFingerVertSwipe : settings.fourFingerVertSwipe,
                             owner: .appExpose)
        case .pinchIn, .pinchOut:
            // No dock gate exists for these, so the two pinch keys are the only evidence — and when
            // both read on there is no way to say which toggle each one encodes.
            let appsKey = settings.fourFingerPinch
            let desktopKey = settings.fiveFingerPinch
            if appsKey == nil, desktopKey == nil { return .unverifiable }
            if appsKey == true, desktopKey == true { return .unverifiable }
            let ownKey = kind == .pinchIn ? appsKey : desktopKey
            switch ownKey {
            case .some(true): return .clash(kind == .pinchIn ? .appsPinch : .showDesktop)
            case .some(false): return .clear
            case .none: return .unverifiable
            }
        case .twoFingerRightEdgeSwipeLeft:
            return decide(settings.twoFingerRightEdgeSwipe, owner: .notificationCenter)
        case .threeFingerTipTapLeft, .threeFingerTipTapRight:
            return decide(settings.threeFingerTap, owner: .lookUp)
        case .fourFingerTap:
            // Nothing in macOS uses a four-finger tap.
            return .clear
        }
    }

    private static func decide(_ value: Bool?, owner: MacOSGestureOwner) -> GestureConflict {
        switch value {
        case .some(true): return .clash(owner)
        case .some(false): return .clear
        case .none: return .unverifiable
        }
    }

    private static func dockGated(enabled: Bool?, trackpad: Bool?, owner: MacOSGestureOwner) -> GestureConflict {
        if let enabled { return enabled ? .clash(owner) : .clear }
        return decide(trackpad, owner: owner)
    }
}

/// One gesture's binding: what it does with tiling off, and optionally what it does instead with
/// tiling on. `nil` tiling action means the window action applies in both contexts.
struct GestureBindingRule: Equatable, Sendable, Codable {
    var windowAction: GestureActionTarget = .none
    var tilingAction: GestureActionTarget?
    var enabled = true

    static let off = GestureBindingRule(windowAction: .none, tilingAction: nil, enabled: false)
}

struct GestureContext: Equatable, Sendable {
    var tilingEnabled: Bool
}

enum GestureRouter {
    /// The action a gesture should fire, or nil when it should do nothing.
    static func target(for rule: GestureBindingRule, context: GestureContext) -> GestureActionTarget? {
        guard rule.enabled else { return nil }
        let action = (context.tilingEnabled ? rule.tilingAction : nil) ?? rule.windowAction
        return action == .none ? nil : action
    }
}

/// ½ → ⅓ → ⅔ → ½, only while the same edge is repeated inside `window`.
enum SnapWidthCycle: Int, CaseIterable, Sendable {
    case half, third, twoThirds

    var next: SnapWidthCycle {
        let all = Self.allCases
        return all[(rawValue + 1) % all.count]
    }
}

enum SnapSide: String, Sendable { case left, right }

/// Remembers which edge was snapped and how far the cycle got, so a repeated swipe of the same edge
/// narrows the window instead of re-applying the half every time.
struct SnapCycleState: Equatable, Sendable {
    private(set) var side: SnapSide?
    private(set) var step: SnapWidthCycle = .half
    private(set) var at: Date = .distantPast
    var window: TimeInterval = 1.2

    mutating func next(side newSide: SnapSide, at now: Date) -> SnapPosition {
        let continuing = side == newSide && now.timeIntervalSince(at) <= window
        step = continuing ? step.next : .half
        side = newSide
        at = now
        return Self.position(side: newSide, step: step)
    }

    static func position(side: SnapSide, step: SnapWidthCycle) -> SnapPosition {
        switch (side, step) {
        case (.left, .half): return .leftHalf
        case (.left, .third): return .leftThird
        case (.left, .twoThirds): return .leftTwoThirds
        case (.right, .half): return .rightHalf
        case (.right, .third): return .rightThird
        case (.right, .twoThirds): return .rightTwoThirds
        }
    }
}

enum TrackpadSettingsReader {
    /// The undocumented per-trackpad keys, in the order the snapshot stores them.
    static let trackpadKeys = [
        "TrackpadThreeFingerHorizSwipeGesture", "TrackpadThreeFingerVertSwipeGesture",
        "TrackpadFourFingerHorizSwipeGesture", "TrackpadFourFingerVertSwipeGesture",
        "TrackpadFourFingerPinchGesture", "TrackpadFiveFingerPinchGesture",
        "TrackpadThreeFingerTapGesture", "TrackpadTwoFingerFromRightEdgeSwipeGesture",
    ]
    /// Where the modern More Gestures toggles actually live.
    static let dockKeys = ["showMissionControlGestureEnabled", "showAppExposeGestureEnabled"]

    /// These arrive as small integers: 0 is off and anything else (1 or 2) is on.
    static func snapshot(trackpad: [String: Any], dock: [String: Any]) -> TrackpadSettingsSnapshot {
        TrackpadSettingsSnapshot(
            threeFingerHorizSwipe: flag(trackpad["TrackpadThreeFingerHorizSwipeGesture"]),
            threeFingerVertSwipe: flag(trackpad["TrackpadThreeFingerVertSwipeGesture"]),
            fourFingerHorizSwipe: flag(trackpad["TrackpadFourFingerHorizSwipeGesture"]),
            fourFingerVertSwipe: flag(trackpad["TrackpadFourFingerVertSwipeGesture"]),
            fourFingerPinch: flag(trackpad["TrackpadFourFingerPinchGesture"]),
            fiveFingerPinch: flag(trackpad["TrackpadFiveFingerPinchGesture"]),
            threeFingerTap: flag(trackpad["TrackpadThreeFingerTapGesture"]),
            twoFingerRightEdgeSwipe: flag(trackpad["TrackpadTwoFingerFromRightEdgeSwipeGesture"]),
            missionControlGestureEnabled: flag(dock["showMissionControlGestureEnabled"]),
            appExposeGestureEnabled: flag(dock["showAppExposeGestureEnabled"])
        )
    }

    private static func flag(_ value: Any?) -> Bool? {
        guard let number = value as? Int else { return nil }
        return number != 0
    }
}

enum TrackpadGesturePreset {
    /// Clash-free for a 4-finger Spaces / 3-finger Mission Control setup. Gestures macOS owns
    /// (3-finger up, 4-finger left/right, spread) are deliberately absent rather than remapped.
    static let clashFree: [MultitouchGestureKind: GestureBindingRule] = [
        .threeFingerSwipeLeft: GestureBindingRule(windowAction: .snapCycleLeft, tilingAction: .stripPrevious),
        .threeFingerSwipeRight: GestureBindingRule(windowAction: .snapCycleRight, tilingAction: .stripNext),
        .threeFingerSwipeDown: GestureBindingRule(windowAction: .windowSwitcher, tilingAction: .stripStack),
        .fourFingerSwipeUp: GestureBindingRule(windowAction: .maximize, tilingAction: .stripCycleWidth),
        .fourFingerSwipeDown: GestureBindingRule(windowAction: .centerRestore, tilingAction: .quickLayoutPicker),
        .pinchIn: GestureBindingRule(windowAction: .toggleTiling, tilingAction: .toggleTiling),
        .twoFingerRightEdgeSwipeLeft: GestureBindingRule(windowAction: .commandBar, tilingAction: .nextDisplay),
        .threeFingerTipTapLeft: GestureBindingRule(windowAction: .previousDisplay, tilingAction: .stripSwapPrevious),
        .threeFingerTipTapRight: GestureBindingRule(windowAction: .nextDisplay, tilingAction: .stripSwapNext),
    ]

    /// The preset with anything the current macOS settings already own removed.
    static func applicable(to settings: TrackpadSettingsSnapshot) -> [MultitouchGestureKind: GestureBindingRule] {
        clashFree.filter { kind, _ in
            !TrackpadConflictDetector.conflict(for: kind, settings: settings).isClash
        }
    }
}
