import Foundation

// Phase 8e — pure colour formatting for the screen colour picker (sRGB components in 0...1 → "#RRGGBB").
// Dual-compiled so clamping and rounding are unit-tested; the sampler itself is the app-only `ColorPickerService`.

enum ColorFormat {
    static func hex(red: Double, green: Double, blue: Double) -> String {
        func byte(_ v: Double) -> Int { Int((min(max(v.isFinite ? v : 0, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}
