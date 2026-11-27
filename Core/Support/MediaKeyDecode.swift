import Foundation

/// Media / hardware control keys decoded from `NX_SYSDEFINED` (`CGEventType` 14, subtype 8).
enum MediaKeyKind: Int, Equatable, Sendable {
    case volumeUp = 0
    case volumeDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
    case illuminationUp = 21
    case illuminationDown = 22
}

struct MediaKeyEvent: Equatable, Sendable {
    let key: MediaKeyKind
    let isKeyDown: Bool
    let isRepeat: Bool
    let isFineStep: Bool
}

/// Pure decoder and step math for macOS hardware HUD media keys.
enum MediaKeyDecode {
    static let auxControlSubtype: Int16 = 8
    /// `CGEventFlags.maskAlternate.rawValue` (0x00080000) and `.maskShift.rawValue` (0x00020000).
    static let alternateFlagMask: UInt64 = 0x0008_0000
    static let shiftFlagMask: UInt64 = 0x0002_0000

    static func decode(subtype: Int16, data1: Int, modifierFlagsRaw: UInt64) -> MediaKeyEvent? {
        guard subtype == auxControlSubtype else { return nil }
        let keyCode = (data1 >> 16) & 0xFFFF
        guard let key = MediaKeyKind(rawValue: keyCode) else { return nil }
        let keyFlags = data1 & 0xFFFF
        let keyState = (keyFlags >> 8) & 0xFF
        let isKeyDown: Bool
        switch keyState {
        case 0x0A: isKeyDown = true
        case 0x0B: isKeyDown = false
        default: return nil
        }
        let isRepeat = (keyFlags & 0x1) != 0
        let fine = (modifierFlagsRaw & alternateFlagMask) != 0 && (modifierFlagsRaw & shiftFlagMask) != 0
        return MediaKeyEvent(key: key, isKeyDown: isKeyDown, isRepeat: isRepeat, isFineStep: fine)
    }

    /// Standard macOS 16-notch step, or quarter-step (64 notches) when Option+Shift is held.
    static func stepAmount(fine: Bool) -> Double {
        fine ? 1.0 / 64.0 : 1.0 / 16.0
    }

    static func steppedLevel(current: Double, increasing: Bool, fine: Bool) -> Double {
        let delta = stepAmount(fine: fine) * (increasing ? 1.0 : -1.0)
        let next = min(1.0, max(0.0, current + delta))
        if next < 0.002 { return 0.0 }
        if next > 0.998 { return 1.0 }
        return next
    }
}
