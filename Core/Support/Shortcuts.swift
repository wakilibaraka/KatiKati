import Combine
import Foundation

/// What a shortcut does (Phase 7B-V4).
enum ShortcutAction: String, CaseIterable, Sendable {
    case launcher, pinboard, quickSettings, keepAwake
    /// Phase 9d: the drawer, the notch's Tools tab, and the Weather / Clock widgets on their own.
    case drawer, notchTools, weather, clock
    /// Phase 27: the command bar (a ⌘K palette over the same index). Default
    /// ⌥Space, **not** ⌘Space: Spotlight owns ⌘Space, and even though Carbon registers the
    /// combination without error, macOS hands the key to Spotlight first — the bar never opened.
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
    /// The dial opened straight on its Snapping / Tools page. Both default `.off`.
    case radialDialSnap, radialDialTools
    /// Notch bento pages, step by step (live-check follow-up: dots are mouse-only otherwise).
    /// Both default `.off` — user assigns.
    case notchPageNext, notchPagePrevious
    /// 55b: the dial's area capture, now also a shortcut. Default `.off` — user assigns.
    case captureArea
    /// 53g: save the clipboard image into the front Finder window as a `.png`. Default `.off` — user assigns.
    case pasteImageToFinder
    /// Space switching with a transition (ported from Spacewalk). Default `.off` — the system's own
    /// ⌃← / ⌃→ keep working until the user binds these.
    case spaceNext, spacePrevious
    /// The window switcher's key (default ⌥Tab). Owned by `WindowSwitcherController`, which needs the
    /// held modifier to commit; `ShortcutService` skips it, and Shift added to the combination reverses.
    case windowSwitcher
    /// Hold to peek at the Weather and Calendar panels; a quick tap keeps them open. No default key.
    case peek
    /// The window drawer (⌃⌥W). It was a hard-coded Carbon key with id 22, which `snapRightThird` also used.
    case windowDrawer
    /// Open the dictionary panel / toggle the terminal panel. No default key.
    case openDictionary, toggleTerminal
    /// Port plan #14: hold (or toggle) voice dictation into the frontmost app. No default key.
    case dictate
    /// Slice D (OpenTaskbar behavior): take the keyboard onto the dock — arrows, Home/End, Enter, Esc. No default key.
    case dockFocus
    /// Phase 60: elevate desktop boxes above windows temporarily / toggle hide all. Both default `.off`.
    case desktopQuickReveal, desktopToggleHidden
    /// Ribbon (scrolling strip): focus, column moves, width, stacking and tabs.
    case stripFocusNext, stripFocusPrevious
    case stripMoveNext, stripMovePrevious
    case stripCycleWidth, stripStackLeft, stripToggleTabs
    case stripTabNext, stripTabPrevious
    /// SCU-4: the floating cheat sheet. Default `.off` — the user picks a shortcut for it.
    case showCheatSheet

    /// The ribbon's eight pictures, ⌘⌃1–8 in visual order (1 = Chain).
    case ribbonChain, ribbonHalves, ribbonTwoPlusOne, ribbonOnePlusTwo
    case ribbonThirds, ribbonQuarters, ribbonFive, ribbonSix

    /// Carbon hot key id (signature is shared with the other hot keys; 1 = edge auto-hide).
    var hotKeyID: UInt32 {
        switch self {
        case .showCheatSheet: return 73
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
        case .radialDialSnap: return 40
        case .radialDialTools: return 41
        case .captureArea: return 42
        case .pasteImageToFinder: return 43
        case .spaceNext: return 44
        case .spacePrevious: return 45
        case .windowSwitcher: return 46   // 47 is the switcher's reverse key, not an action
        case .peek: return 48
        case .windowDrawer: return 49
        case .openDictionary: return 50
        case .toggleTerminal: return 51
        case .dictate: return 52
        case .dockFocus: return 53
        case .desktopQuickReveal: return 54
        case .desktopToggleHidden: return 55
        // Ribbon: ids 56–64 for the strip, 65–72 for the eight pictures.
        case .stripFocusNext: return 56
        case .stripFocusPrevious: return 57
        case .stripMoveNext: return 58
        case .stripMovePrevious: return 59
        case .stripCycleWidth: return 60
        case .stripStackLeft: return 61
        case .stripToggleTabs: return 62
        case .stripTabNext: return 63
        case .stripTabPrevious: return 64
        case .ribbonChain: return 65
        case .ribbonHalves: return 66
        case .ribbonTwoPlusOne: return 67
        case .ribbonOnePlusTwo: return 68
        case .ribbonThirds: return 69
        case .ribbonQuarters: return 70
        case .ribbonFive: return 71
        case .ribbonSix: return 72
        }
    }

    var defaultTrigger: ShortcutTrigger {
        switch self {
        case .launcher: return .chord(.optionShiftSpace)
        case .pinboard: return .chord(.controlOptionSpace)
        case .commandBar: return .chord(.optionSpace)
        case .showCheatSheet: return .off
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
        // Phase 31 radial dial: ⌃⌥R by default for main dial, sub-page shortcuts off by default
        case .radialDial: return .key(ShortcutKey(keyCode: 15, modifiers: ShortcutKey.control | ShortcutKey.option))
        case .radialDialSnap, .radialDialTools: return .off
        case .notchPageNext, .notchPagePrevious, .captureArea, .pasteImageToFinder: return .off
        case .spaceNext, .spacePrevious, .peek, .openDictionary, .toggleTerminal, .dictate, .dockFocus,
             .desktopQuickReveal, .desktopToggleHidden: return .off
        case .windowSwitcher: return .key(ShortcutKey(keyCode: 48, modifiers: ShortcutKey.option))
        case .windowDrawer: return .key(ShortcutKey(keyCode: 13, modifiers: ShortcutKey.control | ShortcutKey.option))
        // Ribbon: ⌃⌥⇧R cycles the focused column's width (⌃⌥R belongs to the radial dial), and the
        // eight pictures sit on ⌘⌃1–8 in visual order.
        case .stripCycleWidth: return .key(ShortcutKey(keyCode: 15, modifiers: ShortcutKey.control | ShortcutKey.option | ShortcutKey.shift))
        case .ribbonChain: return .key(ShortcutKey(keyCode: 18, modifiers: ShortcutKey.command | ShortcutKey.control))
        case .ribbonHalves: return .key(ShortcutKey(keyCode: 19, modifiers: ShortcutKey.command | ShortcutKey.control))
        case .ribbonTwoPlusOne: return .key(ShortcutKey(keyCode: 20, modifiers: ShortcutKey.command | ShortcutKey.control))
        case .ribbonOnePlusTwo: return .key(ShortcutKey(keyCode: 21, modifiers: ShortcutKey.command | ShortcutKey.control))
        case .ribbonThirds: return .key(ShortcutKey(keyCode: 23, modifiers: ShortcutKey.command | ShortcutKey.control))
        case .ribbonQuarters: return .key(ShortcutKey(keyCode: 22, modifiers: ShortcutKey.command | ShortcutKey.control))
        case .ribbonFive: return .key(ShortcutKey(keyCode: 26, modifiers: ShortcutKey.command | ShortcutKey.control))
        case .ribbonSix: return .key(ShortcutKey(keyCode: 28, modifiers: ShortcutKey.command | ShortcutKey.control))
        case .stripFocusNext, .stripFocusPrevious, .stripMoveNext, .stripMovePrevious,
             .stripStackLeft, .stripToggleTabs, .stripTabNext, .stripTabPrevious: return .off
        }
    }

    /// Whether this action belongs to Phase 26b auto-tiling.
    var isTilingAction: Bool {
        switch self {
        case .toggleTiling, .cycleTilingLayout,
             .tilingFocusNext, .tilingFocusPrevious,
             .tilingSwapNext, .tilingSwapPrevious,
             .tilingGrowMain, .tilingShrinkMain, .tilingFlipMain,
             .stripFocusNext, .stripFocusPrevious, .stripMoveNext, .stripMovePrevious,
             .stripCycleWidth, .stripStackLeft, .stripToggleTabs, .stripTabNext, .stripTabPrevious,
             .ribbonChain, .ribbonHalves, .ribbonTwoPlusOne, .ribbonOnePlusTwo,
             .ribbonThirds, .ribbonQuarters, .ribbonFive, .ribbonSix: return true
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

/// A key chord on Space. Four alternatives per the owner's brief, plus ⌃⌥Space (Control Center) and ⌘Space.
/// `commandSpace` stays selectable for people who turned Spotlight off, but it is never a default:
/// macOS delivers it to Spotlight before any app-level hot key (see `isReservedBySystem`).
enum ShortcutChord: String, CaseIterable, Sendable {
    case optionSpace, controlSpace, optionShiftSpace, controlShiftSpace, controlOptionSpace, commandSpace

    /// Owned by macOS out of the box: ⌘Space is Spotlight, ⌃Space switches input sources. Carbon
    /// still returns noErr for them (verified), but the system's handler consumes the key first, so a
    /// default on either one leaves the action silently unreachable. `defaultTrigger` avoids both,
    /// and `CommandBarTests.testDefaultShortcutChordsAreNotOwnedByMacOS` keeps it that way.
    var isReservedBySystem: Bool { self == .commandSpace || self == .controlSpace }

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
    /// fn / Globe. Arrives only as a `flagsChanged` event, so it rides the same detector as the modifiers.
    case fn

    var keyCode: UInt16 {
        switch self {
        case .fn: return 63
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
        case .fn: return "fn"
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
    var isValid: Bool {
        guard ShortcutKeyNames.name(for: keyCode) != nil else { return false }
        return modifiers != 0 || ShortcutKeyNames.isFunctionKey(keyCode)
    }

    var glyphs: String {
        (modifiers & Self.control != 0 ? "⌃" : "") + (modifiers & Self.option != 0 ? "⌥" : "")
            + (modifiers & Self.shift != 0 ? "⇧" : "") + (modifiers & Self.command != 0 ? "⌘" : "")
            + (ShortcutKeyNames.name(for: keyCode) ?? "?")
    }
}

/// One app pinned to a direct switcher hotkey. Raw key fields keep the record Codable while the
/// computed `key` reuses the existing validation/glyph rules.
struct PinnedAppHotkey: Codable, Equatable, Hashable, Sendable, Identifiable {
    var bundleID: String
    var keyCode: UInt16
    var modifiers: UInt8

    var id: String { bundleID }

    var key: ShortcutKey {
        ShortcutKey(keyCode: keyCode, modifiers: modifiers)
    }

    init(bundleID: String, key: ShortcutKey) {
        self.bundleID = bundleID
        self.keyCode = key.keyCode
        self.modifiers = key.modifiers
    }
}

enum PinnedAppHotkeyValidation {
    /// Trims bundle IDs, drops invalid keys, and keeps the first entry for each bundle ID and each
    /// physical key so a duplicate can never register two Carbon hotkeys for one gesture.
    static func validated(_ hotkeys: [PinnedAppHotkey]) -> [PinnedAppHotkey] {
        var seenBundleIDs: Set<String> = []
        var seenKeys: Set<ShortcutKey> = []
        return hotkeys.compactMap { hotkey in
            var next = hotkey
            next.bundleID = next.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !next.bundleID.isEmpty, next.key.isValid else { return nil }
            guard seenBundleIDs.insert(next.bundleID).inserted,
                  seenKeys.insert(next.key).inserted else { return nil }
            return next
        }
    }
}

enum ShortcutKeyNames {
    private static let table: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W",
        14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
        39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        // Arrows: the ribbon's own focus keys (⌃⌥← / ⌃⌥→) need to be assignable at all, and a
        // chord with ⌃ or ⌥ still cannot steal typing.
        123: "\u{2190}", 124: "\u{2192}", 125: "\u{2193}", 126: "\u{2191}",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19",
    ]
    static func name(for keyCode: UInt16) -> String? { table[keyCode] }
    /// F1–F19 are safe to bind bare: they cannot steal typing.
    static func isFunctionKey(_ keyCode: UInt16) -> Bool { (table[keyCode].map { $0.hasPrefix("F") && $0.count > 1 } ?? false) }
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
    /// Hold one modifier (or fn) for `ShortcutHold.threshold` without pressing anything else.
    case hold(ShortcutTapKey)

    var serialized: String {
        switch self {
        case .off: return "off"
        case .chord(let c): return "chord:\(c.rawValue)"
        case .doubleTap(let k): return "tap:\(k.rawValue)"
        case .key(let k): return "key:\(k.modifiers):\(k.keyCode)"
        case .hyper(let code): return "hyper:\(code)"
        case .hold(let k): return "hold:\(k.rawValue)"
        }
    }

    /// Unknown / malformed → nil so the caller falls back to the action's default.
    static func parse(_ raw: String?) -> ShortcutTrigger? {
        guard let raw else { return nil }
        if raw == "off" { return .off }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        if parts[0] == "chord", let c = ShortcutChord(rawValue: parts[1]) { return .chord(c) }
        if parts[0] == "hold", let k = ShortcutTapKey(rawValue: parts[1]) { return .hold(k) }
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

extension ShortcutTrigger {
    /// The key combination the window switcher listens for. `nil` = bound to Off. A held modifier is
    /// what commits, so double-tap and Hyper (nothing to hold) fall back to the default ⌥Tab.
    var switcherKey: ShortcutKey? {
        switch self {
        case .off: return nil
        case .key(let k): return k
        case .chord(let c):
            var mods: UInt8 = 0
            if c.usesControl { mods |= ShortcutKey.control }
            if c.usesOption { mods |= ShortcutKey.option }
            if c.usesShift { mods |= ShortcutKey.shift }
            if c.usesCommand { mods |= ShortcutKey.command }
            return ShortcutKey(keyCode: 49, modifiers: mods)
        case .doubleTap, .hyper, .hold: return ShortcutAction.windowSwitcher.defaultTrigger.switcherKey
        }
    }
}

enum ShortcutConflicts {
    /// Actions whose (non-off) trigger is shared with another action. Compared by `overlapKey`, so a
    /// Space chord and the same combination recorded as a custom key count as one.
    static func duplicated(_ bindings: [ShortcutAction: ShortcutTrigger]) -> Set<ShortcutAction> {
        var byTrigger: [ShortcutTrigger: [ShortcutAction]] = [:]
        for (a, t) in bindings where t != .off { byTrigger[t.overlapKey, default: []].append(a) }
        return Set(byTrigger.values.filter { $0.count > 1 }.flatMap { $0 })
    }
}

extension ShortcutTrigger {
    /// The one place a trigger becomes display text; `nil` for Off.
    var displayGlyphs: String? {
        switch self {
        case .off: return nil
        case .chord(let c): return c.glyphs
        case .doubleTap(let k): return k == .fn ? "fn fn" : "\(k.glyph)\(k.glyph)"
        case .hold(let k): return "hold " + k.glyph
        case .key(let k): return k.glyphs
        case .hyper(let code): return "✦" + (ShortcutKeyNames.name(for: code) ?? "?")
        }
    }

    /// The same physical gesture always maps to the same value: a Space chord becomes its `.key` form.
    var overlapKey: ShortcutTrigger {
        if case .chord = self, let k = switcherKey { return .key(k) }
        return self
    }
}

/// How long a `.hold` trigger must be held before it fires.
enum ShortcutHold {
    static let defaultsKey = "com.katikati.shortcut.holdSeconds"
    static let range: ClosedRange<Double> = 0.3...1.5
    static var threshold: TimeInterval {
        let v = UserDefaults.standard.object(forKey: defaultsKey) as? Double ?? 0.5
        return min(max(v, range.lowerBound), range.upperBound)
    }
}

/// One verdict for a candidate binding, in one place (the recorder and the settings rows ask this).
enum ShortcutVerdict: Equatable, Sendable {
    case ok
    /// Allowed, but the user should know (macOS owns it, another action has it, fn may be swallowed).
    case warn(String)
    case reject(String)
}

enum ShortcutValidator {
    static func check(_ trigger: ShortcutTrigger, for action: ShortcutAction,
                      among bindings: [ShortcutAction: ShortcutTrigger]) -> ShortcutVerdict {
        let key = trigger.overlapKey
        if case .key(let k) = key, !k.isValid { return .reject("Add a modifier (⌃ ⌥ ⇧ ⌘) to a plain key.") }
        if let other = bindings.first(where: { $0.key != action && $0.value != .off && $0.value.overlapKey == key })?.key {
            return .warn("Already used by \(other.rawValue).")
        }
        // One table for "macOS answers first", shared with the row badge below.
        if case .key(let k) = key, let reason = MacOSShortcutOwnership.reason(for: k) { return .warn(reason) }
        switch key {
        case .doubleTap(.fn), .hold(.fn):
            return .warn("macOS may use fn / Globe for dictation or emoji. Set 'Press 🌐 key to' Do Nothing in System Settings › Keyboard.")
        default:
            return .ok
        }
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

    /// Any pointer press or drag breaks the sequence (slice MD-5). `⌘`+click and `⌘`+drag are chords,
    /// not taps: without this the release ending a drag could pair with the next tap and fire.
    mutating func pointerActivity() {
        reset()
    }

    /// Any non-modifier key (or a modifier combination) breaks the sequence.
    mutating func reset() {
        downKey = nil
        lastTapEnd.removeAll()
    }
}

/// Which bindings macOS or another app refused, shown on their Settings rows (it was only a log line).
@MainActor
final class ShortcutRegistrationState: ObservableObject {
    static let shared = ShortcutRegistrationState()
    @Published internal(set) var failures: [ShortcutAction: String] = [:]
}

/// Port plan #14: pure transcript normalization for Hold-to-Dictate before clipboard paste.
enum DictationTranscript {
    static func cleaned(_ raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}


// MARK: - Slice D: keyboard focus on the dock (OpenTaskbar behavior, MIT — see NOTICE)

/// One key the focused dock understands. AppKit key codes become these in `DockFocusKeyView`; keeping the
/// model free of AppKit is what lets the rules be tested without a window.
enum DockFocusKey: String, CaseIterable, Sendable {
    case left, right, home, end, enter, escape
}

/// What a key did, so the view knows when to act on the bar rather than just redraw the highlight.
enum DockFocusEffect: Equatable, Sendable {
    case none
    /// The highlight moved (or the model is still on the same card, e.g. Home when already first).
    case moved
    /// Enter on a card: the view performs that card's click.
    case activated(String)
    case ended
}

/// Keyboard focus over the strip's cards. **No wrap**: right at the last card and left at the first do
/// nothing, which is what the owner asked for and what makes the ends of the bar findable by feel.
struct DockFocusModel: Equatable, Sendable {
    private(set) var ids: [String] = []
    private(set) var index: Int?

    init(ids: [String] = [], index: Int? = nil) {
        self.ids = ids
        self.index = index
    }

    var isActive: Bool { index != nil }

    var focusedID: String? {
        guard let index, ids.indices.contains(index) else { return nil }
        return ids[index]
    }

    /// Start on the first card. An empty bar stays unfocused rather than inventing a position.
    mutating func begin() {
        guard !ids.isEmpty else { index = nil; return }
        if let index, ids.indices.contains(index) { return }
        index = 0
    }

    mutating func end() {
        index = nil
    }

    /// Follow the strip while focused: same card if it survives, else the nearest remaining one (never wraps).
    mutating func sync(_ newIDs: [String]) {
        let previous = focusedID
        let wasActive = isActive
        ids = newIDs
        guard wasActive else { index = nil; return }
        if let previous, let kept = newIDs.firstIndex(of: previous) {
            index = kept
            return
        }
        guard !newIDs.isEmpty else { index = nil; return }
        index = min(index ?? 0, newIDs.count - 1)
    }

    mutating func handle(_ key: DockFocusKey) -> DockFocusEffect {
        guard isActive, !ids.isEmpty else { return .none }
        switch key {
        case .left:
            guard let index, index > 0 else { return .none }
            self.index = index - 1
            return .moved
        case .right:
            guard let index, index < ids.count - 1 else { return .none }
            self.index = index + 1
            return .moved
        case .home:
            index = 0
            return .moved
        case .end:
            index = ids.count - 1
            return .moved
        case .enter:
            guard let id = focusedID else { return .none }
            return .activated(id)
        case .escape:
            end()
            return .ended
        }
    }
}

// MARK: - SCU-1: categories, conflicts, presets, and the keycap map

/// Which band of the bindings list an action belongs to. Order is the order the chips read in.
enum ShortcutCategory: String, CaseIterable, Sendable {
    case core, windowAndSnap, tiling, desktopAndNotch, tools

    var titleKey: String {
        switch self {
        case .core: return "Core"
        case .windowAndSnap: return "Window & Snap"
        case .tiling: return "Tiling"
        case .desktopAndNotch: return "Desktop & Notch"
        case .tools: return "Tools"
        }
    }
}

extension ShortcutAction {
    /// The band this action lives in. Unlisted actions fall back to Tools rather than vanishing
    /// from every chip, so a new action is never silently unreachable in the list.
    var category: ShortcutCategory {
        switch self {
        case .launcher, .pinboard, .quickSettings, .keepAwake, .commandBar, .translate,
             .peek, .openDictionary, .toggleTerminal, .dictate:
            return .core
        case .snapLeftHalf, .snapRightHalf, .snapTopHalf, .snapBottomHalf,
             .snapTopLeft, .snapTopRight, .snapBottomLeft, .snapBottomRight,
             .snapLeftThird, .snapCenterThird, .snapRightThird, .snapLeftTwoThirds, .snapRightTwoThirds,
             .snapCenter, .snapMaximize, .snapNextDisplay,
             .windowSwitcher, .windowDrawer, .spaceNext, .spacePrevious, .dockFocus:
            return .windowAndSnap
        case .toggleTiling, .cycleTilingLayout, .tilingFocusNext, .tilingFocusPrevious,
             .tilingSwapNext, .tilingSwapPrevious, .tilingGrowMain, .tilingShrinkMain, .tilingFlipMain,
             .stripFocusNext, .stripFocusPrevious, .stripMoveNext, .stripMovePrevious,
             .stripCycleWidth, .stripStackLeft, .stripToggleTabs, .stripTabNext, .stripTabPrevious,
             .ribbonChain, .ribbonHalves, .ribbonTwoPlusOne, .ribbonOnePlusTwo,
             .ribbonThirds, .ribbonQuarters, .ribbonFive, .ribbonSix:
            return .tiling
        case .showCheatSheet:
            return .tools
        case .drawer, .notchTools, .weather, .clock, .notchPageNext, .notchPagePrevious,
             .desktopQuickReveal, .desktopToggleHidden,
             .radialDial, .radialDialSnap, .radialDialTools:
            return .desktopAndNotch
        default:
            return .tools
        }
    }
}

/// The shortcuts macOS acts on before a Carbon hot key hears about them — one table, so the
/// recorder's verdict and the row badge can never disagree.
enum MacOSShortcutOwnership {
    static func reason(for key: ShortcutKey) -> String? {
        if key.keyCode == 49 {
            if key.modifiers == ShortcutKey.command { return "macOS already uses ⌘Space for Spotlight. Turn it off in System Settings › Keyboard › Shortcuts first." }
            if key.modifiers == ShortcutKey.control { return "macOS already uses ⌃Space to switch input sources. Turn it off in System Settings › Keyboard › Shortcuts first." }
            if key.modifiers == ShortcutKey.command | ShortcutKey.option { return "macOS already uses ⌘⌥Space for Finder search. Turn it off in System Settings › Keyboard › Shortcuts first." }
        }
        if key.keyCode == 48, key.modifiers == ShortcutKey.command {
            return "This is the system app switcher. Turn on ⌘Tab for the Window Switcher to replace it."
        }
        if key.modifiers == ShortcutKey.command | ShortcutKey.shift, [20, 21, 23].contains(key.keyCode) {
            return "⌘⇧3, ⌘⇧4 and ⌘⇧5 are the macOS screenshot shortcuts. Rebind them in System Settings › Keyboard › Shortcuts to use these."
        }
        return nil
    }
}

/// What a row says about its shortcut: nothing in the way, a duplicate, or macOS answers first.
enum ShortcutConflict: Equatable, Sendable {
    case clear
    case internalDuplicate(ShortcutAction)
    case systemClash(String)

    var isClear: Bool { self == .clear }
}

enum ShortcutConflictDetector {
    static func conflict(for action: ShortcutAction,
                         trigger: ShortcutTrigger,
                         among bindings: [ShortcutAction: ShortcutTrigger]) -> ShortcutConflict {
        guard trigger != .off else { return .clear }
        if case .key(let key) = trigger.overlapKey, let reason = MacOSShortcutOwnership.reason(for: key) {
            return .systemClash(reason)
        }
        let other = bindings.first { pair in
            pair.key != action && pair.value != .off && pair.value.overlapKey == trigger.overlapKey
        }
        return other.map { .internalDuplicate($0.key) } ?? .clear
    }

    /// Every action that is not clear, in one pass — what the `Conflicts (N)` chip counts.
    static func conflicted(_ bindings: [ShortcutAction: ShortcutTrigger]) -> [ShortcutAction: ShortcutConflict] {
        var result: [ShortcutAction: ShortcutConflict] = [:]
        for (action, trigger) in bindings {
            let conflict = conflict(for: action, trigger: trigger, among: bindings)
            if !conflict.isClear { result[action] = conflict }
        }
        return result
    }
}

/// Ready-made bindings. Every pack starts from the shipped defaults, so applying one never leaves an
/// action unreachable that the defaults would have kept alive.
enum ShortcutPresetPack: String, CaseIterable, Sendable {
    case standard, hyperKeyPack, minimalConflictFree, resetDefaults

    var titleKey: String {
        switch self {
        case .standard: return "Standard"
        case .hyperKeyPack: return "Hyper Key Pack"
        case .minimalConflictFree: return "Minimal Conflict-Free"
        case .resetDefaults: return "Reset to Defaults"
        }
    }

    private static let hyperBindings: [ShortcutAction: UInt16] = [
        .snapLeftHalf: 0,      // A
        .snapRightHalf: 2,     // D
        .snapMaximize: 46,     // M
        .snapNextDisplay: 37,  // L
        .windowSwitcher: 13,   // W
        .toggleTiling: 17      // T
    ]

    func bindings(replacing current: [ShortcutAction: ShortcutTrigger]) -> [ShortcutAction: ShortcutTrigger] {
        var next: [ShortcutAction: ShortcutTrigger] = [:]
        for action in ShortcutAction.allCases { next[action] = action.defaultTrigger }
        switch self {
        case .standard, .resetDefaults:
            return next
        case .hyperKeyPack:
            for (action, code) in Self.hyperBindings { next[action] = .hyper(code) }
            return next
        case .minimalConflictFree:
            // Keep the defaults, drop anything the one table calls a clash (macOS answers first).
            let conflicted = ShortcutConflictDetector.conflicted(next)
            for (action, conflict) in conflicted {
                if case .systemClash = conflict { next[action] = .off }
            }
            return next
        }
    }
}

/// What the stage's keyboard lights up for a trigger: modifier caps, one main key, and whether the
/// gesture is a timing one (double-tap / hold) that should pulse.
struct MiniKeyboardState: Equatable, Sendable {
    var litModifiers: Set<String>
    var mainKey: String?
    var pulses: Bool

    static let idle = MiniKeyboardState(litModifiers: [], mainKey: nil, pulses: false)

    static func from(_ trigger: ShortcutTrigger) -> MiniKeyboardState {
        switch trigger {
        case .off:
            return .idle
        case .chord(let chord):
            return MiniKeyboardState(litModifiers: Set(chord.modifierGlyphs), mainKey: "Space", pulses: false)
        case .key(let key):
            return MiniKeyboardState(litModifiers: Set(key.modifierGlyphs), mainKey: ShortcutKeyNames.name(for: key.keyCode), pulses: false)
        case .hyper(let code):
            return MiniKeyboardState(litModifiers: ["✦"], mainKey: ShortcutKeyNames.name(for: code), pulses: false)
        case .doubleTap(let tap):
            return MiniKeyboardState(litModifiers: [], mainKey: tap.glyph, pulses: true)
        case .hold(let tap):
            return MiniKeyboardState(litModifiers: [], mainKey: tap.glyph, pulses: true)
        }
    }
}

/// The bindings list's two ways in: a typed query, or the keys themselves.
enum ShortcutFilter {
    static func matches(name: String, action: ShortcutAction, trigger: ShortcutTrigger, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if name.localizedCaseInsensitiveContains(trimmed) || action.rawValue.localizedCaseInsensitiveContains(trimmed) { return true }
        if let glyphs = trigger.displayGlyphs, glyphs.localizedCaseInsensitiveContains(trimmed) { return true }
        return false
    }
    static func matches(trigger: ShortcutTrigger, key: ShortcutKey) -> Bool {
        guard case .key(let own) = trigger.overlapKey else { return false }
        return own.keyCode == key.keyCode && own.modifiers == key.modifiers
    }
}

extension ShortcutChord {
    /// The modifier caps this chord lights on the stage's keyboard, in ⌃⌥⇧⌘ order.
    var modifierGlyphs: [String] {
        var caps: [String] = []
        if usesControl { caps.append("⌃") }
        if usesOption { caps.append("⌥") }
        if usesShift { caps.append("⇧") }
        if usesCommand { caps.append("⌘") }
        return caps
    }
}

extension ShortcutKey {
    var modifierGlyphs: [String] {
        var caps: [String] = []
        if modifiers & Self.control != 0 { caps.append("⌃") }
        if modifiers & Self.option != 0 { caps.append("⌥") }
        if modifiers & Self.shift != 0 { caps.append("⇧") }
        if modifiers & Self.command != 0 { caps.append("⌘") }
        return caps
    }
}

// MARK: - SCU-4: the cheat sheet

/// One line of the cheat sheet: what it is and the keys it takes.
struct ShortcutCheatSheetRow: Equatable, Identifiable, Sendable {
    var action: ShortcutAction
    var trigger: ShortcutTrigger
    var id: ShortcutAction { action }
}

/// The sheet reads the same bindings the settings pane writes, with the shipped default behind every
/// action the store has not answered for — so it can never show a combination the pane would not.
enum ShortcutCheatSheet {
    static func rows(bindings: [ShortcutAction: ShortcutTrigger]) -> [ShortcutCheatSheetRow] {
        ShortcutAction.allCases.compactMap { action in
            // The sheet never lists itself: one shortcut opens it, the sheet is not a reference entry.
            guard action != .showCheatSheet else { return nil }
            let trigger = bindings[action] ?? action.defaultTrigger
            guard trigger != .off else { return nil }
            return ShortcutCheatSheetRow(action: action, trigger: trigger)
        }
    }

    /// Groups in `ShortcutCategory.allCases` order; an empty band is left out entirely.
    static func sections(bindings: [ShortcutAction: ShortcutTrigger]) -> [(category: ShortcutCategory, rows: [ShortcutCheatSheetRow])] {
        let all = rows(bindings: bindings)
        return ShortcutCategory.allCases.compactMap { category in
            let rows = all.filter { $0.action.category == category }
            return rows.isEmpty ? nil : (category, rows)
        }
    }
}

/// Open or closed. Pure so Esc, a click outside and the same shortcut again are all testable without
/// an AppKit window: every way of closing calls `dismiss`, and reopening goes through `toggle`.
struct ShortcutCheatSheetPresence: Equatable, Sendable {
    private(set) var isVisible = false

    mutating func toggle() { isVisible.toggle() }
    mutating func dismiss() { isVisible = false }
}
