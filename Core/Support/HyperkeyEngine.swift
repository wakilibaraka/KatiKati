import Foundation

// Phase 9e — Hyperkey / Superkey: a chosen modifier key (Caps Lock by default) is remapped to F18
// (`hidutil`), and this pure engine turns the F18 / key stream into "fire bound KatiKati action",
// "forward system-wide Hyper/Super modifiers", or "tap-if-alone" decisions. No AppKit, no event tap —
// the tap (App layer) only feeds it key events, so the whole behaviour is unit-tested.

enum HyperkeyModifierMode: String, CaseIterable, Identifiable, Sendable {
    /// ⌃⌥⇧⌘ (all four modifiers).
    case hyper
    /// ⌃⌥⌘ (leaves ⇧ free for a second layer).
    case superKey
    var id: String { rawValue }
}

enum HyperkeySourceKey: String, CaseIterable, Identifiable, Sendable {
    case capsLock
    case rightCommand
    case rightOption
    var id: String { rawValue }

    var hidUsage: UInt64 {
        switch self {
        case .capsLock: return HyperkeyRemap.capsLock
        case .rightCommand: return HyperkeyRemap.rightCommand
        case .rightOption: return HyperkeyRemap.rightOption
        }
    }
}

enum HyperkeyTapAction: String, CaseIterable, Identifiable, Sendable {
    case off
    case escape
    case capsLock
    var id: String { rawValue }
}

struct HyperkeyConfig: Equatable, Sendable {
    var modifierMode: HyperkeyModifierMode = .hyper
    var tapAction: HyperkeyTapAction = .off
    var forwardToSystem: Bool = false
    var tapThreshold: TimeInterval = 0.20
}

struct HyperkeyEngine {
    enum Decision: Equatable {
        /// Not ours; let the key through untouched.
        case passThrough
        /// Ours; consume it (the F18 key itself, a bound key's repeat/release).
        case swallow
        /// Hyper + a bound key went down: consume it and run the action for this key code.
        case fire(keyCode: UInt16)
        /// Hyper/Super + an unbound key: let the key through with synthesized modifier flags.
        case forwardWithModifiers(HyperkeyModifierMode)
        /// F18 was tapped alone within `tapThreshold`: consume F18 and emit the tap action.
        case tapIfAlone(HyperkeyTapAction)
    }

    /// F18 — what the source key becomes after the remap.
    static let hyperKeyCode: UInt16 = 79

    private(set) var isHeld = false
    private var heldSince: Date?
    private var didCombineKey = false
    private var swallowedKeys = Set<UInt16>()

    /// - Parameter isBound: whether Hyper+key has an action. Unbound keys either pass through or
    ///   receive system-wide `Hyper`/`Super` modifier flags when `config.forwardToSystem` is enabled.
    mutating func handle(
        keyCode: UInt16,
        isDown: Bool,
        isRepeat: Bool,
        at now: Date = Date(),
        config: HyperkeyConfig = HyperkeyConfig(),
        isBound: (UInt16) -> Bool
    ) -> Decision {
        if keyCode == Self.hyperKeyCode {
            if isDown {
                if !isHeld {
                    isHeld = true
                    heldSince = now
                    didCombineKey = false
                }
                return .swallow
            } else {
                let wasQuickTap = isHeld && !didCombineKey && config.tapAction != .off
                    && (heldSince.map { now.timeIntervalSince($0) <= config.tapThreshold } ?? false)
                isHeld = false
                heldSince = nil
                didCombineKey = false
                swallowedKeys.removeAll()
                return wasQuickTap ? .tapIfAlone(config.tapAction) : .swallow
            }
        }
        if isDown {
            guard isHeld else { return .passThrough }
            didCombineKey = true
            if isBound(keyCode) {
                swallowedKeys.insert(keyCode)
                return isRepeat ? .swallow : .fire(keyCode: keyCode)
            }
            return config.forwardToSystem ? .forwardWithModifiers(config.modifierMode) : .passThrough
        }
        // Key up: consume the release of a key we consumed on the way down.
        if swallowedKeys.remove(keyCode) != nil { return .swallow }
        return isHeld && config.forwardToSystem ? .forwardWithModifiers(config.modifierMode) : .passThrough
    }

    mutating func reset() {
        isHeld = false
        heldSince = nil
        didCombineKey = false
        swallowedKeys.removeAll()
    }
}

/// Builds and reverses the `hidutil` source-key → F18 mapping without losing the user's own remaps.
enum HyperkeyRemap {
    static let capsLock: UInt64 = 0x7_0000_0039
    static let rightCommand: UInt64 = 0x7_0000_00E7
    static let rightOption: UInt64 = 0x7_0000_00E6
    static let f18: UInt64 = 0x7_0000_006D

    typealias Mapping = [String: UInt64]

    static var ours: Mapping { mapping(for: capsLock) }

    static func mapping(for source: UInt64) -> Mapping {
        ["HIDKeyboardModifierMappingSrc": source, "HIDKeyboardModifierMappingDst": f18]
    }

    /// `existing` plus our entry (any previous mapping for `source` or prior `→ F18` entry is replaced).
    static func adding(source: UInt64 = capsLock, to existing: [Mapping]) -> [Mapping] {
        let cleaned = existing.filter {
            $0["HIDKeyboardModifierMappingSrc"] != source && $0["HIDKeyboardModifierMappingDst"] != f18
        }
        return cleaned + [mapping(for: source)]
    }

    /// `current` without our `→ F18` entry — restores whatever the user had.
    static func removing(from current: [Mapping]) -> [Mapping] {
        current.filter { $0["HIDKeyboardModifierMappingDst"] != f18 }
    }

    /// Reads `hidutil property --get UserKeyMapping`. Older macOS prints one bare plist; newer macOS prints a
    /// `RegistryID  Key  Value` table with one `UserKeyMapping ( … )` block per HID service (`(null)` when empty).
    /// Every block is parsed and duplicates are dropped, so a mapping set on any service is seen once.
    static func parse(_ text: String) -> [Mapping] {
        var blocks = [text]
        if let regex = try? NSRegularExpression(pattern: #"UserKeyMapping\s+(\(.*?\n?\))"#,
                                                options: [.dotMatchesLineSeparators]) {
            let range = NSRange(text.startIndex..., in: text)
            let found = regex.matches(in: text, range: range).compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } }
            if !found.isEmpty { blocks = found }
        }
        var result: [Mapping] = []
        for block in blocks {
            guard let data = block.data(using: .utf8),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                  let array = plist as? [[String: Any]] else { continue }
            for dict in array {
                // The ASCII plist hidutil prints has no number type: values arrive as strings.
                func value(_ key: String) -> UInt64? {
                    (dict[key] as? NSNumber)?.uint64Value ?? (dict[key] as? String).flatMap { UInt64($0) }
                }
                guard let src = value("HIDKeyboardModifierMappingSrc"),
                      let dst = value("HIDKeyboardModifierMappingDst") else { continue }
                let mapping: Mapping = ["HIDKeyboardModifierMappingSrc": src, "HIDKeyboardModifierMappingDst": dst]
                if !result.contains(mapping) { result.append(mapping) }
            }
        }
        return result
    }

    static func json(_ mappings: [Mapping]) -> String {
        let items = mappings.map { m in
            "{" + m.sorted { $0.key < $1.key }.map { "\"\($0.key)\":\($0.value)" }.joined(separator: ",") + "}"
        }
        return "{\"UserKeyMapping\":[" + items.joined(separator: ",") + "]}"
    }
}
