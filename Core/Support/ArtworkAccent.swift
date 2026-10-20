import Foundation

// Phase 50a — reduce an artwork's average colour to one readable accent. Pure: the pixel read stays in
// the app layer, which falls back to the theme accent whenever this returns nil. Dual-compiled.

struct ArtworkAccent: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    /// Below these there is no hue worth showing (black, white, grey art), so the caller keeps the theme accent.
    static let minBrightness = 0.12
    static let minSaturation = 0.12
    static let saturationRange = 0.45...0.85
    static let brightnessRange = 0.65...0.95

    /// - Parameters: the artwork's average colour, each 0...1.
    static func reduce(red: Double, green: Double, blue: Double) -> ArtworkAccent? {
        let r = clamp01(red), g = clamp01(green), b = clamp01(blue)
        let hi = max(r, g, b), lo = min(r, g, b)
        guard hi >= minBrightness, hi > 0, (hi - lo) / hi >= minSaturation else { return nil }
        let delta = hi - lo
        var hue: Double
        if hi == r { hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
        else if hi == g { hue = (b - r) / delta + 2 }
        else { hue = (r - g) / delta + 4 }
        if hue < 0 { hue += 6 }
        let s = min(max((hi - lo) / hi, saturationRange.lowerBound), saturationRange.upperBound)
        let v = min(max(hi, brightnessRange.lowerBound), brightnessRange.upperBound)
        let c = v * s
        let x = c * (1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        let (r1, g1, b1): (Double, Double, Double)
        switch Int(hue) {
        case 0: (r1, g1, b1) = (c, x, 0)
        case 1: (r1, g1, b1) = (x, c, 0)
        case 2: (r1, g1, b1) = (0, c, x)
        case 3: (r1, g1, b1) = (0, x, c)
        case 4: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        return ArtworkAccent(red: r1 + m, green: g1 + m, blue: b1 + m)
    }

    private static func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
}
