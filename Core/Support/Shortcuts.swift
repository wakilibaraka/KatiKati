import Foundation

/// What a shortcut does (Phase 7B-V4).
enum ShortcutAction: String, CaseIterable, Sendable {
    case launcher, pinboard, quickSettings, keepAwake
    /// Phase 9d: the drawer, the notch's Tools tab, and the Weather / Clock widgets on their own.
    case drawer, notchTools, weather, clock
    /// Phase 27: the ⌘Space command bar (a Raycast/Sol-style palette over the same index).
    case commandBar
    /// Phase 23: define/translate the current selection (off by default).
    case translate
    /// Phase 26a: one case per snap zone (15 total). All default to `.off` — user assigns.
    case snapLeftHalf, snapRightHalf, snapTopHalf, snapBottomHalf
    case snapTopLeft, snapTopRight, snapBottomLeft, snapBottomRight
    case snapLeftThird, snapCenterThird, snapRightThird, snapLeftTwoThirds, snapRightTwoThirds
    case snapCenter, snapMaximize
    /// Sends the focused window to the next display, keeping its relative place. Default `.off`.
    case snapNextDisplay
    /// Phase 26b tiling actions: master toggle, layout cycle, focus nav, and tile swap. All default `.off`.
    case toggleTiling, cycleTilingLayout
    case tilingFocusNext, tilingFocusPrevious
    case tilingSwapNext, tilingSwapPrevious
    /// Main-area tuning: widen, narrow, or flip the main window to the other side. Default `.off`.
    case tilingGrowMain, tilingShrinkMain, tilingFlipMain
    /// Phase 31: the colourful interactive radial dial / pie menu. Default `.off`.
    case radialDial
    /// Notch bento pages, step by step (live-check follow-up: dots are mouse-only otherwise).
    /// Both default `.off` — user assigns.
    case notchPageNext, notchPagePrevious

    /// Carbon hot key id (signature is shared with the other hot keys; 1 = edge auto-hide).
    var hotKeyID: UInt32 {
        switch self {
        case .launcher: return 2
        case .pinboard: return 3
        case .quickSettings: return 4
        case .keepAwake: return 5
        case .drawer: return 6
        case .notchTools: return 7
        case .weather: return 8
        case .clock: return 9
        case .commandBar: return 10
        case .translate: return 11
        // Phase 26a snap zones: ids 12–26
        case .snapLeftHalf: return 12
        case .snapRightHalf: return 13
        case .snapTopHalf: return 14
        case .snapBottomHalf: return 15
        case .snapTopLeft: return 16
        case .snapTopRight: return 17
        case .snapBottomLeft: return 18
        case .snapBottomRight: return 19
        case .snapLeftThird: return 20
        case .snapCenterThird: return 21
        case .snapRightThird: return 22
        case .snapLeftTwoThirds: return 23
        case .snapRightTwoThirds: return 24
        case .snapCenter: return 25
        case .snapMaximize: return 26
        // Phase 26b tiling actions: ids 27–32
        case .toggleTiling: return 27
        case .cycleTilingLayout: return 28
        case .tilingFocusNext: return 29
        case .tilingFocusPrevious: return 30
        case .tilingSwapNext: return 31
        case .tilingSwapPrevious: return 32
        // Phase 31 radial dial: id 33
        case .radialDial: return 33
        case .notchPageNext: return 34
        case .notchPagePrevious: return 35
        case .snapNextDisplay: return 36
        case .tilingGrowMain: return 37
        case .tilingShrinkMain: return 38
        case .tilingFlipMain: return 39
        }
    }

    var defaultTrigger: ShortcutTrigger {
        switch self {
        case .launcher: return .chord(.optionSpace)
        case .pinboard: return .chord(.controlOptionSpace)
        case .commandBar: return .chord(.commandSpace)
        case .quickSettings, .keepAwake, .drawer, .notchTools, .weather, .clock, .translate: return .off
        // All snap zones default to off — user assigns via Settings › Shortcuts › Snap Hotkeys.
        case .snapLeftHalf, .snapRightHalf, .snapTopHalf, .snapBottomHalf,
             .snapTopLeft, .snapTopRight, .snapBottomLeft, .snapBottomRight,
             .snapLeftThird, .snapCenterThird, .snapRightThird, .snapLeftTwoThirds, .snapRightTwoThirds,
             .snapCenter, .snapNextDisplay: return .off
        // Maximize in place (no new Space) is the one zone worth a default: ⌃⌥M.
        case .snapMaximize: return .key(ShortcutKey(keyCode: 46, modifiers: ShortcutKey.control | ShortcutKey.option))
        // All tiling actions default to off — user assigns.
        case .toggleTiling, .cycleTilingLayout,
             .tilingFocusNext, .tilingFocusPrevious,
             .tilingSwapNext, .tilingSwapPrevious,
             .tilingGrowMain, .tilingShrinkMain, .tilingFlipMain: return .off
        // Phase 31 radial dial: off by default, user assigns
        case .radialDial: return .off
        case .notchPageNext, .notchPagePrevious: return .off
        }
    }

    /// Whether this action belongs to Phase 26b auto-tiling.
    var isTilingAction: Bool {
        switch self {
        case .toggleTiling, .cycleTilingLayout,
             .tilingFocusNext, .tilingFocusPrevious,
             .tilingSwapNext, .tilingSwapPrevious,
             .tilingGrowMain, .tilingShrinkMain, .tilingFlipMain: return true
        default: return false
        }
    }

    /// The `SnapPosition` this action maps to, or `nil` for non-snap actions.
    var snapPosition: SnapPosition? {
        switch self {
        case .snapLeftHalf: return .leftHalf
        case .snapRightHalf: return .rightHalf
        case .snapTopHalf: return .topHalf
        case .snapBottomHalf: return .bottomHalf
        case .snapTopLeft: return .topLeft
        case .snapTopRight: return .topRight
        case .snapBottomLeft: return .bottomLeft
        case .snapBottomRight: return .bottomRight
        case .snapLeftThird: return .leftThird
        case .snapCenterThird: return .centerThird
        case .snapRightThird: return .rightThird
        case .snapLeftTwoThirds: return .leftTwoThirds
        case .snapRightTwoThirds: return .rightTwoThirds
        case .snapCenter: return .center
        case .snapMaximize: return .maximize
        default: return nil
        }
    }
}

/// A key chord on Space. Four alternatives per the owner's brief, plus ⌃⌥Space (Control Center) and ⌘Space (Phase 27).
enum ShortcutChord: String, CaseIterable, Sendable {
    case optionSpace, controlSpace, optionShiftSpace, controlShiftSpace, controlOptionSpace, commandSpace

    var usesControl: Bool { self == .controlSpace || self == .controlShiftSpace || self == .controlOptionSpace }
    var usesOption: Bool { self == .optionSpace || self == .optionShiftSpace || self == .controlOptionSpace }
    var usesShift: Bool { self == .optionShiftSpace || self == .controlShiftSpace }
    var usesCommand: Bool { self == .commandSpace }

    var glyphs: String {
        (usesControl ? "⌃" : "") + (usesOption ? "⌥" : "") + (usesShift ? "⇧" : "") + (usesCommand ? "⌘" : "") + "Space"
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

/// Phase 9d: any key with at least one of ⌃ ⌥ ⇧ ⌘ (not only Space chords). `modifiers` is a bit set so
/// the type stays free of AppKit/Carbon.
struct ShortcutKey: Equatable, Hashable, Sendable {
    static let control: UInt8 = 1, option: UInt8 = 2, shift: UInt8 = 4, command: UInt8 = 8

    var keyCode: UInt16
    var modifiers: UInt8

    /// Needs a modifier (a bare letter would steal typing) and a key we can name.
    var isValid: Bool { modifiers != 0 && ShortcutKeyNames.name(for: keyCode) != nil }

    var glyphs: String {
        (modifiers & Self.control != 0 ? "⌃" : "") + (modifiers & Self.option != 0 ? "⌥" : "")
            + (modifiers & Self.shift != 0 ? "⇧" : "") + (modifiers & Self.command != 0 ? "⌘" : "")
            + (ShortcutKeyNames.name(for: keyCode) ?? "?")
    }
}

enum ShortcutKeyNames {
    private static let table: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W",
        14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
        39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 49: "Space", 50: "`",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19",
    ]
    static func name(for keyCode: UInt16) -> String? { table[keyCode] }
    /// Letters and digits — what the Hyperkey picker offers.
    static let hyperChoices: [UInt16] = [0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46, 45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6]
}

enum ShortcutTrigger: Equatable, Hashable, Sendable {
    case off
    case chord(ShortcutChord)
    case doubleTap(ShortcutTapKey)
    /// Phase 9d: ⌃⌥⇧⌘-style combination on any key.
    case key(ShortcutKey)
    /// Phase 9e: Hyper (Caps Lock → ⌃⌥⇧⌘) + a key. Fired by the Hyperkey service, never by Carbon.
    case hyper(UInt16)

    var serialized: String {
        switch self {
        case .off: return "off"
        case .chord(let c): return "chord:\(c.rawValue)"
        case .doubleTap(let k): return "tap:\(k.rawValue)"
        case .key(let k): return "key:\(k.modifiers):\(k.keyCode)"
        case .hyper(let code): return "hyper:\(code)"
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
        if parts[0] == "hyper", let code = UInt16(parts[1]), ShortcutKeyNames.name(for: code) != nil { return .hyper(code) }
        if parts[0] == "key" {
            let nums = parts[1].split(separator: ":").compactMap { UInt16($0) }
            if nums.count == 2, nums[0] <= 15 {
                let key = ShortcutKey(keyCode: nums[1], modifiers: UInt8(nums[0]))
                if key.isValid { return .key(key) }
            }
        }
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
