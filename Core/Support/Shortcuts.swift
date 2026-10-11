import Foundation

/// What a shortcut does (Phase 7B-V4).
enum ShortcutAction: String, CaseIterable, Sendable {
    case launcher, pinboard, quickSettings, keepAwake

    /// Carbon hot key id (signature is shared with the other hot keys; 1 = edge auto-hide).
    var hotKeyID: UInt32 {
        switch self {
        case .launcher: return 2
        case .pinboard: return 3
        case .quickSettings: return 4
        case .keepAwake: return 5
        }
    }

    var defaultTrigger: ShortcutTrigger {
        switch self {
        case .launcher: return .chord(.optionSpace)
        case .pinboard: return .chord(.controlOptionSpace)
        case .quickSettings, .keepAwake: return .off
        }
    }
}

/// A key chord on Space. Four alternatives per the owner's brief, plus ⌃⌥Space (Pinboard's default).
enum ShortcutChord: String, CaseIterable, Sendable {
    case optionSpace, controlSpace, optionShiftSpace, controlShiftSpace, controlOptionSpace

    var usesControl: Bool { self == .controlSpace || self == .controlShiftSpace || self == .controlOptionSpace }
    var usesOption: Bool { self == .optionSpace || self == .optionShiftSpace || self == .controlOptionSpace }
    var usesShift: Bool { self == .optionShiftSpace || self == .controlShiftSpace }

    var glyphs: String {
        (usesControl ? "⌃" : "") + (usesOption ? "⌥" : "") + (usesShift ? "⇧" : "") + "Space"
    }
}

/// A modifier that fires on a quick double tap, left or right side.
enum ShortcutTapKey: String, CaseIterable, Sendable {
    case leftCommand, rightCommand, leftControl, rightControl, leftOption, rightOption

    var keyCode: UInt16 {
        switch self {
        case .leftCommand: return 55
        case .rightCommand: return 54
        case .leftControl: return 59
        case .rightControl: return 62
        case .leftOption: return 58
        case .rightOption: return 61
        }
    }

    var glyph: String {
        switch self {
        case .leftCommand, .rightCommand: return "⌘"
        case .leftControl, .rightControl: return "⌃"
        case .leftOption, .rightOption: return "⌥"
        }
    }

    var isRight: Bool { self == .rightCommand || self == .rightControl || self == .rightOption }

    init?(keyCode: UInt16) {
        guard let k = Self.allCases.first(where: { $0.keyCode == keyCode }) else { return nil }
        self = k
    }
}

enum ShortcutTrigger: Equatable, Hashable, Sendable {
    case off
    case chord(ShortcutChord)
    case doubleTap(ShortcutTapKey)

    var serialized: String {
        switch self {
        case .off: return "off"
        case .chord(let c): return "chord:\(c.rawValue)"
        case .doubleTap(let k): return "tap:\(k.rawValue)"
        }
    }

    /// Unknown / malformed → nil so the caller falls back to the action's default.
    static func parse(_ raw: String?) -> ShortcutTrigger? {
        guard let raw else { return nil }
        if raw == "off" { return .off }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        if parts[0] == "chord", let c = ShortcutChord(rawValue: parts[1]) { return .chord(c) }
        if parts[0] == "tap", let k = ShortcutTapKey(rawValue: parts[1]) { return .doubleTap(k) }
        return nil
    }
}

enum ShortcutConflicts {
    /// Actions whose (non-off) trigger is shared with another action.
    static func duplicated(_ bindings: [ShortcutAction: ShortcutTrigger]) -> Set<ShortcutAction> {
        var byTrigger: [ShortcutTrigger: [ShortcutAction]] = [:]
        for (a, t) in bindings where t != .off { byTrigger[t, default: []].append(a) }
        return Set(byTrigger.values.filter { $0.count > 1 }.flatMap { $0 })
    }
}

/// Recognises a quick double tap of one modifier key: both taps short, nothing else pressed in between.
/// Pure so the timing rules are tested; the Platform layer feeds it `flagsChanged` / `keyDown` events.
struct ModifierDoubleTapDetector {
    var window: TimeInterval = 0.35
    var maxHold: TimeInterval = 0.30
    private var downKey: ShortcutTapKey?
    private var downTime: TimeInterval = 0
    private var lastTapEnd: [ShortcutTapKey: TimeInterval] = [:]

    /// A modifier changed. `isDown` is its new state. Returns the key once its second tap completes.
    mutating func modifierChanged(keyCode: UInt16, isDown: Bool, time: TimeInterval) -> ShortcutTapKey? {
        guard let key = ShortcutTapKey(keyCode: keyCode) else { reset(); return nil }
        if isDown {
            if downKey != nil { reset() }
            downKey = key
            downTime = time
            return nil
        }
        guard downKey == key else { reset(); return nil }
        downKey = nil
        guard time - downTime <= maxHold else { lastTapEnd[key] = nil; return nil }
        if let prev = lastTapEnd[key], time - prev <= window {
            lastTapEnd[key] = nil
            return key
        }
        lastTapEnd[key] = time
        return nil
    }

    /// Any non-modifier key (or a modifier combination) breaks the sequence.
    mutating func reset() {
        downKey = nil
        lastTapEnd.removeAll()
    }
}
