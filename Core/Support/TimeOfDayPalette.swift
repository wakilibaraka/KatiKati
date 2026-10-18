// Settings redesign, Phase 6 — the tint the Settings window's glow and the stage vignette take from
// the hour of day: night, dawn, day, dusk, blended smoothly between them.
//
// Dual-compiled: pure numbers, no AppKit/SwiftUI.

struct TimeOfDayPalette: Equatable {
    struct RGB: Equatable { var red, green, blue: Double }

    enum Phase: String, Equatable { case night, dawn, day, dusk }

    /// Colour keyframes by hour; the last repeats the first so midnight wraps without a seam.
    private static let keyframes: [(hour: Double, rgb: RGB)] = [
        (0, RGB(red: 0.20, green: 0.24, blue: 0.55)),
        (6, RGB(red: 0.98, green: 0.62, blue: 0.45)),
        (12, RGB(red: 0.45, green: 0.72, blue: 1.00)),
        (18, RGB(red: 0.95, green: 0.45, blue: 0.55)),
        (24, RGB(red: 0.20, green: 0.24, blue: 0.55)),
    ]

    let tint: RGB
    let phase: Phase

    /// `hour` is a fractional local hour; any value is wrapped into 0..<24.
    init(hour: Double) {
        let h = hour - (hour / 24).rounded(.down) * 24
        let upper = Self.keyframes.firstIndex { $0.hour > h } ?? Self.keyframes.count - 1
        let a = Self.keyframes[upper - 1], b = Self.keyframes[upper]
        let t = (h - a.hour) / (b.hour - a.hour)
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        tint = RGB(red: mix(a.rgb.red, b.rgb.red), green: mix(a.rgb.green, b.rgb.green), blue: mix(a.rgb.blue, b.rgb.blue))
        switch h {
        case 5..<9: phase = .dawn
        case 9..<17: phase = .day
        case 17..<21: phase = .dusk
        default: phase = .night
        }
    }
}
