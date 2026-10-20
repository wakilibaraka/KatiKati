import Foundation

// Phase 9e — Hyperkey: Caps Lock is remapped to F18 (`hidutil`), and this pure engine turns the F18 /
// key stream into "fire the action bound to Hyper+<key>" decisions. No AppKit, no event tap — the tap
// (App layer) only feeds it key events, so the whole behaviour is unit-tested.

struct HyperkeyEngine {
    enum Decision: Equatable {
        /// Not ours; let the key through untouched.
        case passThrough
        /// Ours; consume it (the F18 key itself, a bound key's repeat/release).
        case swallow
        /// Hyper + a bound key went down: consume it and run the action for this key code.
        case fire(keyCode: UInt16)
    }

    /// F18 — what Caps Lock becomes after the remap.
    static let hyperKeyCode: UInt16 = 79

    private(set) var isHeld = false
    private var swallowedKeys = Set<UInt16>()

    /// - Parameter isBound: whether Hyper+key has an action. Unbound keys pass through, so Hyper+X with no
    ///   binding does nothing special and never swallows typing.
    mutating func handle(keyCode: UInt16, isDown: Bool, isRepeat: Bool, isBound: (UInt16) -> Bool) -> Decision {
        if keyCode == Self.hyperKeyCode {
            isHeld = isDown
            if !isDown { swallowedKeys.removeAll() }
            return .swallow
        }
        if isDown {
            guard isHeld, isBound(keyCode) else { return .passThrough }
            swallowedKeys.insert(keyCode)
            return isRepeat ? .swallow : .fire(keyCode: keyCode)
        }
        // Key up: consume the release of a key we consumed on the way down.
        return swallowedKeys.remove(keyCode) != nil ? .swallow : .passThrough
    }

    mutating func reset() {
        isHeld = false
        swallowedKeys.removeAll()
    }
}

/// Builds and reverses the `hidutil` Caps Lock → F18 mapping without losing the user's own remaps.
enum HyperkeyRemap {
    static let capsLock: UInt64 = 0x7_0000_0039
    static let f18: UInt64 = 0x7_0000_006D

    typealias Mapping = [String: UInt64]

    static var ours: Mapping {
        ["HIDKeyboardModifierMappingSrc": capsLock, "HIDKeyboardModifierMappingDst": f18]
    }

    /// `existing` plus our entry (any previous Caps Lock mapping is replaced).
    static func adding(to existing: [Mapping]) -> [Mapping] {
        existing.filter { $0["HIDKeyboardModifierMappingSrc"] != capsLock } + [ours]
    }

    /// `current` without our entry — restores whatever the user had.
    static func removing(from current: [Mapping]) -> [Mapping] {
        current.filter { !($0["HIDKeyboardModifierMappingSrc"] == capsLock && $0["HIDKeyboardModifierMappingDst"] == f18) }
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
