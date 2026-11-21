import Foundation
import CoreGraphics

struct DockRGBA: Equatable, Sendable {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
    let a: CGFloat

    /// Rec. 601 brightness — what decides whether white or near-black content sits on top of this colour.
    var luminance: CGFloat { 0.299 * r + 0.587 * g + 0.114 * b }
}

// MARK: - DW-1 · multicolour / gradient dock accent

/// How the dock accent is painted. One flat tint was the whole vocabulary before this; a stop list of one
/// colour is still a solid, so the simple case stayed the simple case.
enum DockAccentStyle: String, CaseIterable, Codable, Sendable {
    case solid, linearGradient, mesh, wallpaperAdaptive

    /// A solid has exactly one stop; every gradient form takes 2–4.
    var stopRange: ClosedRange<Int> {
        switch self {
        case .solid: return 1...1
        case .linearGradient, .mesh, .wallpaperAdaptive: return 2...DockAccentSpec.maximumStops
        }
    }

    var isGradient: Bool { self != .solid }
}

/// A stop parsed from `#RRGGBB` / `RRGGBB` / `#RGB`. Rejects anything else instead of guessing a colour,
/// because a typo should leave the previous accent alone rather than paint something random.
struct DockAccentColor: Equatable, Sendable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else { return nil }
        red = CGFloat((value >> 16) & 0xFF) / 255
        green = CGFloat((value >> 8) & 0xFF) / 255
        blue = CGFloat(value & 0xFF) / 255
    }

    init(r: CGFloat, g: CGFloat, b: CGFloat) {
        red = min(max(r, 0), 1); green = min(max(g, 0), 1); blue = min(max(b, 0), 1)
    }

    var rgba: DockRGBA { DockRGBA(r: red, g: green, b: blue, a: 1) }

    var hex: String {
        let r = Int((red * 255).rounded()), g = Int((green * 255).rounded()), b = Int((blue * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    func mixed(with other: DockAccentColor, _ t: Double) -> DockAccentColor {
        let k = CGFloat(min(max(t, 0), 1))
        return DockAccentColor(r: red + (other.red - red) * k,
                               g: green + (other.green - green) * k,
                               b: blue + (other.blue - blue) * k)
    }
}

/// The persisted accent choice. Pure so the model is tested rather than only looked at; the views turn
/// `resolved(wallpaperAccent:)` into a `LinearGradient` (or a soft multi-stop mesh) themselves.
struct DockAccentSpec: Codable, Equatable, Sendable {
    static let maximumStops = 4
    static let defaultsKey = "com.katikati.dock.accent.v1"

    var style: DockAccentStyle
    var hexStops: [String]
    /// 0 = left→right, 90 = top→bottom; clamped into 0..<360 when normalized (negative arcs wrap).
    var angleDegrees: Double

    /// The default: follow the wallpaper, so the bar harmonises with the desktop with no extra choice.
    static let wallpaperSampled = DockAccentSpec(style: .wallpaperAdaptive, hexStops: [], angleDegrees: 90)

    init(style: DockAccentStyle = .wallpaperAdaptive, hexStops: [String] = [], angleDegrees: Double = 90) {
        self.style = style
        self.hexStops = hexStops
        self.angleDegrees = angleDegrees
    }

    /// The stops actually entered, invalid hexes dropped (never silently replaced).
    var colors: [DockAccentColor] { hexStops.compactMap(DockAccentColor.init(hex:)) }

    var isUsable: Bool { style.stopRange.contains(colors.count) }

    /// Repaired for storage: dropped invalid stops, de-duplicated, capped at four, angle wrapped into 0..<360.
    /// A style that ends up short of its own minimum falls back to wallpaper-adaptive (which needs no input).
    var normalized: DockAccentSpec {
        var seen = Set<String>(), stops: [String] = []
        for color in colors where !seen.contains(color.hex) {
            seen.insert(color.hex)
            stops.append(color.hex)
            if stops.count == Self.maximumStops { break }
        }
        let wrapped = angleDegrees.truncatingRemainder(dividingBy: 360)
        let angle = (wrapped < 0 ? wrapped + 360 : wrapped).rounded()
        if style == .wallpaperAdaptive { return DockAccentSpec(style: style, hexStops: stops, angleDegrees: angle) }
        guard style.stopRange.contains(stops.count) else {
            return DockAccentSpec(style: .wallpaperAdaptive, hexStops: stops, angleDegrees: angle)
        }
        return DockAccentSpec(style: style, hexStops: stops, angleDegrees: angle)
    }

    /// The spec a style switch should produce, so the Style control sticks instead of bouncing straight back to
    /// Wallpaper: the chosen style is kept, and when the current stops cannot satisfy it the gap is filled from the
    /// wallpaper's sampled palette and then the neutral fallback (entered stops always come first, never replaced).
    func switching(to style: DockAccentStyle, wallpaperAccent: [String]) -> DockAccentSpec {
        var stops = colors.map(\.hex)
        if stops.count < style.stopRange.lowerBound {
            var pool = wallpaperAccent.compactMap(DockAccentColor.init(hex:)).map(\.hex)
            pool.append(contentsOf: Self.fallbackStops.map(\.hex))
            for hex in pool where !stops.contains(hex) {
                stops.append(hex)
                if stops.count >= style.stopRange.lowerBound { break }
            }
        }
        // A solid keeps its first stop only (a solid with three would not survive `normalized` either).
        stops = Array(stops.prefix(min(style.stopRange.upperBound, Self.maximumStops)))
        return DockAccentSpec(style: style, hexStops: stops, angleDegrees: angleDegrees)
    }

    /// The stops to paint with. Wallpaper-adaptive (or a spec with no usable stops) samples the wallpaper's
    /// own three accent hues instead, then falls back to the bar's neutral highlight.
    func resolved(wallpaperAccent: [String]) -> [DockAccentColor] {
        let own = colors
        let sampled = wallpaperAccent.compactMap(DockAccentColor.init(hex:))
        let source: [DockAccentColor]
        if style == .wallpaperAdaptive || own.isEmpty {
            source = sampled.isEmpty ? Self.fallbackStops : Array(sampled.prefix(3))
        } else {
            source = Array(own.prefix(Self.maximumStops))
        }
        return style == .solid ? Array(source.prefix(1)) : source
    }

    /// The bar's own neutral highlight, used when neither the spec nor the wallpaper has a usable hue.
    static let fallbackStops: [DockAccentColor] = [
        DockAccentColor(r: 0.62, g: 0.72, b: 0.92),
        DockAccentColor(r: 0.86, g: 0.72, b: 0.94)
    ]

    static func decode(_ data: Data?) -> DockAccentSpec {
        guard let data, let decoded = try? JSONDecoder().decode(DockAccentSpec.self, from: data) else {
            return .wallpaperSampled
        }
        return decoded.normalized
    }

    func encoded() -> Data? { try? JSONEncoder().encode(normalized) }
}

/// DW-6 — how a spec lands on the dock's own surfaces (selected / active pill, running-app dot, slider fill).
/// Pure on purpose: the mapping "which stops, gradient or not, which direction" is tested without a window, and the
/// views only turn the result into a `LinearGradient` or a single `Color`.
enum DockAccentFill {
    struct Stops: Equatable, Sendable {
        var colors: [DockAccentColor]
        var isGradient: Bool
        var angleDegrees: Double

        /// No accent configured: the caller keeps the signed-off token look untouched.
        var isActive: Bool { !colors.isEmpty }
        var primary: DockAccentColor? { colors.first }
    }

    /// Resolve the stops for a surface. `enabled` is the feature gate (the dock keeps its own look while the feature
    /// is off); a spec that resolves to nothing falls back to the sampled wallpaper, then to the neutral highlight.
    static func stops(spec: DockAccentSpec, wallpaperAccent: [String], enabled: Bool) -> Stops {
        guard enabled else { return Stops(colors: [], isGradient: false, angleDegrees: spec.angleDegrees) }
        let resolved = spec.resolved(wallpaperAccent: wallpaperAccent)
        let gradient = spec.style != .solid && resolved.count > 1
        return Stops(colors: resolved, isGradient: gradient, angleDegrees: spec.angleDegrees)
    }

    /// 0° runs left→right, 90° top→bottom — the same convention the stage preview and the accent slider show.
    static func unitPoints(angleDegrees: Double) -> (start: (x: Double, y: Double), end: (x: Double, y: Double)) {
        let radians = angleDegrees * .pi / 180
        let dx = cos(radians) / 2, dy = sin(radians) / 2
        return ((0.5 - dx, 0.5 - dy), (0.5 + dx, 0.5 + dy))
    }
}

struct DockThemeStyleTokens: Equatable {
    let baseTint: DockRGBA
    let gradientSheen: DockRGBA
    let glow: DockRGBA
    let rim: DockRGBA
    let blurRadius: CGFloat
    let prefersDarkContent: Bool
    /// The gradient's second stop (Phase 12). Last and defaulted on purpose: every one of the 24
    /// preset literals below was a single solid tint, and they keep compiling — and keep their frozen
    /// values — while `DockGradientPreset` fills this in for the six styles that get a gradient.
    var baseTintBottom: DockRGBA? = nil

    static let systemLight = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.9, g: 0.9, b: 0.9, a: 0.5),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.3),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.2),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.4),
        blurRadius: 30.0,
        prefersDarkContent: true
    )

    static let systemDark = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.1, g: 0.1, b: 0.1, a: 0.6),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.05),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.0),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.15),
        blurRadius: 30.0,
        prefersDarkContent: false
    )

    static let translucentLight = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.95, g: 0.95, b: 0.95, a: 0.3),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.4),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.3),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.5),
        blurRadius: 20.0,
        prefersDarkContent: true
    )

    static let translucentDark = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.15, g: 0.15, b: 0.15, a: 0.4),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.1),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.05),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.2),
        blurRadius: 20.0,
        prefersDarkContent: false
    )

    static let crystalClearLight = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.1),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.5),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.4),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.6),
        blurRadius: 10.0,
        prefersDarkContent: true
    )

    static let crystalClearDark = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.0, g: 0.0, b: 0.0, a: 0.2),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.2),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.1),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.3),
        blurRadius: 10.0,
        prefersDarkContent: false
    )

    static let obsidianDarkLight = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.2, g: 0.2, b: 0.25, a: 0.8),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.1),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.0),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.2),
        blurRadius: 30.0,
        prefersDarkContent: false
    )

    static let obsidianDarkDark = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.05, g: 0.05, b: 0.05, a: 0.85),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.05),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.0),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.15),
        blurRadius: 30.0,
        prefersDarkContent: false
    )

    static let monochromeLight = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.95, g: 0.95, b: 0.95, a: 0.6),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.4),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.3),
        rim: DockRGBA(r: 0.8, g: 0.8, b: 0.8, a: 0.5),
        blurRadius: 30.0,
        prefersDarkContent: true
    )

    static let monochromeDark = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.12, g: 0.12, b: 0.12, a: 0.7),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.1),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.05),
        rim: DockRGBA(r: 0.3, g: 0.3, b: 0.3, a: 0.4),
        blurRadius: 30.0,
        prefersDarkContent: false
    )

    static let titaniumFrostLight = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.88, g: 0.90, b: 0.92, a: 0.55),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.45),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.25),
        rim: DockRGBA(r: 0.9, g: 0.92, b: 0.95, a: 0.6),
        blurRadius: 35.0,
        prefersDarkContent: true
    )

    static let titaniumFrostDark = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.15, g: 0.16, b: 0.18, a: 0.65),
        gradientSheen: DockRGBA(r: 0.9, g: 0.95, b: 1.0, a: 0.15),
        glow: DockRGBA(r: 0.8, g: 0.9, b: 1.0, a: 0.05),
        rim: DockRGBA(r: 0.4, g: 0.45, b: 0.5, a: 0.3),
        blurRadius: 35.0,
        prefersDarkContent: false
    )

    static let auroraGlowLight = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.85, g: 0.95, b: 0.90, a: 0.5),
        gradientSheen: DockRGBA(r: 0.7, g: 1.0, b: 0.8, a: 0.4),
        glow: DockRGBA(r: 0.4, g: 1.0, b: 0.6, a: 0.2),
        rim: DockRGBA(r: 0.6, g: 0.9, b: 0.7, a: 0.5),
        blurRadius: 30.0,
        prefersDarkContent: true
    )

    static let auroraGlowDark = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.1, g: 0.2, b: 0.15, a: 0.65),
        gradientSheen: DockRGBA(r: 0.3, g: 0.8, b: 0.5, a: 0.2),
        glow: DockRGBA(r: 0.2, g: 0.9, b: 0.4, a: 0.15),
        rim: DockRGBA(r: 0.2, g: 0.6, b: 0.4, a: 0.4),
        blurRadius: 30.0,
        prefersDarkContent: false
    )

    static let deepOceanLight = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.80, g: 0.88, b: 0.98, a: 0.55),
        gradientSheen: DockRGBA(r: 0.7, g: 0.85, b: 1.0, a: 0.35),
        glow: DockRGBA(r: 0.4, g: 0.6, b: 1.0, a: 0.2),
        rim: DockRGBA(r: 0.5, g: 0.7, b: 0.95, a: 0.45),
        blurRadius: 30.0,
        prefersDarkContent: true
    )

    static let deepOceanDark = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.05, g: 0.15, b: 0.25, a: 0.7),
        gradientSheen: DockRGBA(r: 0.2, g: 0.4, b: 0.8, a: 0.15),
        glow: DockRGBA(r: 0.1, g: 0.3, b: 0.7, a: 0.1),
        rim: DockRGBA(r: 0.2, g: 0.35, b: 0.6, a: 0.3),
        blurRadius: 30.0,
        prefersDarkContent: false
    )

    static let forestMossLight = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.85, g: 0.92, b: 0.85, a: 0.55),
        gradientSheen: DockRGBA(r: 0.8, g: 1.0, b: 0.8, a: 0.3),
        glow: DockRGBA(r: 0.6, g: 0.9, b: 0.6, a: 0.15),
        rim: DockRGBA(r: 0.7, g: 0.9, b: 0.7, a: 0.4),
        blurRadius: 30.0,
        prefersDarkContent: true
    )

    static let forestMossDark = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.1, g: 0.2, b: 0.1, a: 0.7),
        gradientSheen: DockRGBA(r: 0.2, g: 0.5, b: 0.2, a: 0.15),
        glow: DockRGBA(r: 0.1, g: 0.4, b: 0.1, a: 0.1),
        rim: DockRGBA(r: 0.2, g: 0.4, b: 0.2, a: 0.3),
        blurRadius: 30.0,
        prefersDarkContent: false
    )

    static let cyberpunkGlassLight = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.95, g: 0.85, b: 0.95, a: 0.6),
        gradientSheen: DockRGBA(r: 1.0, g: 0.6, b: 0.9, a: 0.4),
        glow: DockRGBA(r: 0.9, g: 0.2, b: 0.8, a: 0.25),
        rim: DockRGBA(r: 1.0, g: 0.4, b: 0.8, a: 0.5),
        blurRadius: 25.0,
        prefersDarkContent: true
    )

    static let cyberpunkGlassDark = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.15, g: 0.05, b: 0.20, a: 0.75),
        gradientSheen: DockRGBA(r: 0.8, g: 0.2, b: 0.9, a: 0.25),
        glow: DockRGBA(r: 0.7, g: 0.0, b: 0.8, a: 0.2),
        rim: DockRGBA(r: 0.6, g: 0.1, b: 0.7, a: 0.4),
        blurRadius: 25.0,
        prefersDarkContent: false
    )

    static let emberSunsetLight = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.98, g: 0.88, b: 0.82, a: 0.55),
        gradientSheen: DockRGBA(r: 1.0, g: 0.75, b: 0.5, a: 0.4),
        glow: DockRGBA(r: 1.0, g: 0.5, b: 0.2, a: 0.25),
        rim: DockRGBA(r: 1.0, g: 0.6, b: 0.4, a: 0.45),
        blurRadius: 30.0,
        prefersDarkContent: true
    )

    static let emberSunsetDark = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.25, g: 0.12, b: 0.08, a: 0.7),
        gradientSheen: DockRGBA(r: 0.9, g: 0.4, b: 0.2, a: 0.2),
        glow: DockRGBA(r: 0.8, g: 0.3, b: 0.1, a: 0.15),
        rim: DockRGBA(r: 0.7, g: 0.3, b: 0.15, a: 0.35),
        blurRadius: 30.0,
        prefersDarkContent: false
    )

    static let roseQuartzLight = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.95, g: 0.85, b: 0.88, a: 0.6),
        gradientSheen: DockRGBA(r: 1.0, g: 0.9, b: 0.95, a: 0.35),
        glow: DockRGBA(r: 1.0, g: 0.8, b: 0.9, a: 0.2),
        rim: DockRGBA(r: 1.0, g: 0.7, b: 0.85, a: 0.4),
        blurRadius: 30.0,
        prefersDarkContent: true
    )

    static let roseQuartzDark = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.25, g: 0.15, b: 0.18, a: 0.7),
        gradientSheen: DockRGBA(r: 0.9, g: 0.6, b: 0.7, a: 0.15),
        glow: DockRGBA(r: 0.8, g: 0.4, b: 0.5, a: 0.1),
        rim: DockRGBA(r: 0.6, g: 0.3, b: 0.4, a: 0.25),
        blurRadius: 30.0,
        prefersDarkContent: false
    )

    /// The fluid theme's plate stand-in (swatch, and any surface that still draws a rounded plate).
    /// Dark in both appearances on purpose: the preset is a poured black body, not a tint.
    static let fluidLight = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.10, g: 0.10, b: 0.12, a: 0.92),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.10),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.0),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.22),
        blurRadius: 30.0,
        prefersDarkContent: false
    )

    static let fluidDark = fluidLight

    /// The one entry point: the frozen column plus the gradient stop its style's preset names.
    static func resolve(style: DockThemeStyle, appearance: AppearanceMode) -> DockThemeStyleTokens {
        column(style: style, appearance: appearance)
            .withGradient(DockGradientPreset.forStyle(style.resolved(for: appearance)).bottom(for: appearance))
    }

    /// Fills the gradient's bottom stop. A separate step so the 24 preset literals above stay exactly
    /// what `DockThemeStyleTokensTests` freezes.
    func withGradient(_ bottom: DockRGBA?) -> DockThemeStyleTokens {
        guard let bottom else { return self }
        var copy = self
        copy.baseTintBottom = bottom
        return copy
    }

    private static func column(style: DockThemeStyle, appearance: AppearanceMode) -> DockThemeStyleTokens {
        let isDark = appearance == .dark
        let resolvedStyle = style.resolved(for: appearance)
        
        switch resolvedStyle {
        case .system:
            return isDark ? .systemDark : .systemLight
        case .translucent:
            return isDark ? .translucentDark : .translucentLight
        case .crystalClear:
            return isDark ? .crystalClearDark : .crystalClearLight
        case .obsidianDark:
            return isDark ? .obsidianDarkDark : .obsidianDarkLight
        case .monochrome:
            return isDark ? .monochromeDark : .monochromeLight
        case .titaniumFrost:
            return isDark ? .titaniumFrostDark : .titaniumFrostLight
        case .auroraGlow:
            return isDark ? .auroraGlowDark : .auroraGlowLight
        case .deepOcean:
            return isDark ? .deepOceanDark : .deepOceanLight
        case .forestMoss:
            return isDark ? .forestMossDark : .forestMossLight
        case .cyberpunkGlass:
            return isDark ? .cyberpunkGlassDark : .cyberpunkGlassLight
        case .emberSunset:
            return isDark ? .emberSunsetDark : .emberSunsetLight
        case .roseQuartz:
            return isDark ? .roseQuartzDark : .roseQuartzLight
        case .fluid:
            return isDark ? .fluidDark : .fluidLight
        case let .customRGBA(r, g, b, a):
            return DockThemeStyleTokens(
                baseTint: DockRGBA(r: r, g: g, b: b, a: a),
                gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: isDark ? 0.05 : 0.2),
                glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: isDark ? 0.0 : 0.1),
                rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: isDark ? 0.15 : 0.3),
                blurRadius: 30.0,
                prefersDarkContent: !isDark
            )
        case .auto:
            return isDark ? .obsidianDarkDark : .roseQuartzLight
        }
    }
}

/// Phase 12 — which presets draw as a gradient, and the bottom stop each one uses.
///
/// A *small* set on purpose, and hand-picked per family rather than derived from the frozen column:
/// a derived stop (the top stop darkened) reads as a shade of the same paint, not as a gradient, and
/// a value derived from a frozen token would start moving whenever that token moves. Everything not
/// listed stays `.solid` — the state all twelve presets were in before this existed.
///
/// The plate this draws on is `DockGlassBackdrop.overlayFill` through `DockPanelBackdrop`, i.e. all
/// five themed floating surfaces at once. **Known limit:** the non-system-variant Liquid Glass path
/// tints through a single `configuration.baseTint`, so it takes the top stop only.
enum DockGradientPreset: Equatable {
    case solid, aurora, ocean, forest, neon, sunset, rose

    static func forStyle(_ style: DockThemeStyle) -> DockGradientPreset {
        switch style {
        case .auroraGlow: return .aurora
        case .deepOcean: return .ocean
        case .forestMoss: return .forest
        case .cyberpunkGlass: return .neon
        case .emberSunset: return .sunset
        case .roseQuartz: return .rose
        default: return .solid
        }
    }

    /// The bottom stop for an appearance (`nil` = keep the solid tint). The alpha is the preset's own,
    /// scaled like the top stop's by `DockThemeStyle.plateOverlay`.
    func bottom(for appearance: AppearanceMode) -> DockRGBA? {
        let isDark = appearance == .dark
        switch self {
        case .solid: return nil
        case .aurora:
            return isDark ? DockRGBA(r: 0.06, g: 0.32, b: 0.24, a: 0.65)
                          : DockRGBA(r: 0.66, g: 0.90, b: 0.80, a: 0.50)
        case .ocean:
            return isDark ? DockRGBA(r: 0.02, g: 0.07, b: 0.22, a: 0.70)
                          : DockRGBA(r: 0.62, g: 0.78, b: 0.98, a: 0.55)
        case .forest:
            return isDark ? DockRGBA(r: 0.05, g: 0.17, b: 0.07, a: 0.70)
                          : DockRGBA(r: 0.72, g: 0.88, b: 0.70, a: 0.55)
        case .neon:
            return isDark ? DockRGBA(r: 0.30, g: 0.03, b: 0.38, a: 0.75)
                          : DockRGBA(r: 0.80, g: 0.62, b: 0.96, a: 0.60)
        case .sunset:
            return isDark ? DockRGBA(r: 0.40, g: 0.10, b: 0.06, a: 0.70)
                          : DockRGBA(r: 0.98, g: 0.72, b: 0.60, a: 0.55)
        case .rose:
            return isDark ? DockRGBA(r: 0.30, g: 0.12, b: 0.20, a: 0.70)
                          : DockRGBA(r: 0.90, g: 0.72, b: 0.82, a: 0.60)
        }
    }
}

// MARK: - Lumabar & OpenTaskbar Suite (Slice 4.1)

enum DockBarLayoutStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case unifiedBar
    case segmentedIslands

    var id: String { rawValue }
    static let defaultsKey = "com.katikati.dock.layoutStyle"
    static let islandGapDefault: CGFloat = 8.0

    static func current(_ d: UserDefaults = .standard) -> DockBarLayoutStyle {
        DockBarLayoutStyle(rawValue: d.string(forKey: defaultsKey) ?? "") ?? .unifiedBar
    }

    func islandGap(custom: CGFloat? = nil) -> CGFloat {
        let gap = custom ?? Self.islandGapDefault
        return min(max(gap, 6.0), 10.0)
    }
}

enum LumabarSurfaceTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case obsidianBlack
    case crispWhite
    case liquidGlass
    case iosGlass
    case midnightBlue

    var id: String { rawValue }
    static let defaultsKey = "com.katikati.dock.lumabarTheme"

    static func current(_ d: UserDefaults = .standard) -> LumabarSurfaceTheme {
        LumabarSurfaceTheme(rawValue: d.string(forKey: defaultsKey) ?? "") ?? .obsidianBlack
    }

    var supportsIdleFrameRestOptimization: Bool {
        self == .liquidGlass
    }

    func tokens(isDark: Bool) -> DockThemeStyleTokens {
        switch self {
        case .obsidianBlack:
            return DockThemeStyleTokens(
                baseTint: DockRGBA(r: 0.05, g: 0.05, b: 0.05, a: 0.90),
                gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.06),
                glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.0),
                rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.14),
                blurRadius: 32.0,
                prefersDarkContent: false
            )
        case .crispWhite:
            return DockThemeStyleTokens(
                baseTint: DockRGBA(r: 0.98, g: 0.98, b: 0.98, a: 0.88),
                gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.40),
                glow: DockRGBA(r: 0.0, g: 0.0, b: 0.0, a: 0.05),
                rim: DockRGBA(r: 0.0, g: 0.0, b: 0.0, a: 0.12),
                blurRadius: 28.0,
                prefersDarkContent: true
            )
        case .liquidGlass:
            return DockThemeStyleTokens(
                baseTint: DockRGBA(r: 0.12, g: 0.14, b: 0.18, a: 0.35),
                gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.30),
                glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.10),
                rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.25),
                blurRadius: 24.0,
                prefersDarkContent: false
            )
        case .iosGlass:
            return DockThemeStyleTokens(
                baseTint: isDark ? DockRGBA(r: 0.16, g: 0.16, b: 0.18, a: 0.55) : DockRGBA(r: 0.92, g: 0.92, b: 0.94, a: 0.55),
                gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: isDark ? 0.12 : 0.35),
                glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.05),
                rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: isDark ? 0.18 : 0.30),
                blurRadius: 26.0,
                prefersDarkContent: !isDark
            )
        case .midnightBlue:
            return DockThemeStyleTokens(
                baseTint: DockRGBA(r: 0.04, g: 0.07, b: 0.18, a: 0.82),
                gradientSheen: DockRGBA(r: 0.35, g: 0.55, b: 1.0, a: 0.15),
                glow: DockRGBA(r: 0.1, g: 0.3, b: 0.9, a: 0.10),
                rim: DockRGBA(r: 0.3, g: 0.5, b: 0.9, a: 0.22),
                blurRadius: 30.0,
                prefersDarkContent: false,
                baseTintBottom: DockRGBA(r: 0.02, g: 0.03, b: 0.10, a: 0.88)
            )
        }
    }
}

// MARK: - Slice DA-1: dock motion, press feedback and running indicators

/// How an app icon answers the pointer. Pure enum: the view reads it, every curve lives in `DockMagnificationMath` /
/// `DockTiltMath`, and `DockMotionPolicy` decides what Reduce Motion lets through.
enum DockHoverAnimationStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case magnification
    case springLift
    case jiggle
    case colorAura
    case slidingPill
    case magneticPull

    static let defaultsKey = "com.katikati.dock.hoverAnimation"
    var id: String { rawValue }

    /// Styles that move the icon itself; Reduce Motion retires exactly these.
    var movesTheIcon: Bool {
        switch self {
        case .magnification, .springLift, .jiggle, .magneticPull, .slidingPill: return true
        case .none, .colorAura: return false
        }
    }
}

/// What a click looks like before the window appears.
enum DockPressAnimationStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case tactileSquish
    case launchBounce
    case ripple
    case flip3D

    static let defaultsKey = "com.katikati.dock.pressAnimation"
    var id: String { rawValue }
}

/// Size/shape/tint preset for the Dock window hover preview. Pure data: the panel maps these
/// values to its thumbnail width, corner radius, border and backdrop treatment.
struct DockHoverPreviewPreset: Codable, Equatable, Sendable {
    enum Size: String, CaseIterable, Identifiable, Codable, Sendable {
        case compact
        case standard
        case large

        var id: String { rawValue }

        var thumbWidth: Int {
            switch self {
            case .compact: return 140
            case .standard: return 180
            case .large: return 240
            }
        }
    }

    enum Shape: String, CaseIterable, Identifiable, Codable, Sendable {
        case roundedCard
        case squircle
        case borderlessGlass

        var id: String { rawValue }

        var cornerRadius: Double {
            switch self {
            case .roundedCard: return 8
            case .squircle: return 18
            case .borderlessGlass: return 0
            }
        }

        var hasBorder: Bool { self != .borderlessGlass }
    }

    enum Tint: String, CaseIterable, Identifiable, Codable, Sendable {
        case liquidGlass
        case darkObsidian
        case appAccent

        var id: String { rawValue }
    }

    var size: Size
    var shape: Shape
    var tint: Tint
    var showsQuickActions: Bool
    var showsMinimizeQuickAction: Bool
    var showsMaximizeQuickAction: Bool

    init(size: Size = .standard,
         shape: Shape = .roundedCard,
         tint: Tint = .liquidGlass,
         showsQuickActions: Bool = true,
         showsMinimizeQuickAction: Bool = true,
         showsMaximizeQuickAction: Bool = true) {
        self.size = size
        self.shape = shape
        self.tint = tint
        self.showsQuickActions = showsQuickActions
        self.showsMinimizeQuickAction = showsMinimizeQuickAction
        self.showsMaximizeQuickAction = showsMaximizeQuickAction
    }

    static let standard = DockHoverPreviewPreset()

    var thumbWidth: Int { size.thumbWidth }
    var cornerRadius: Double { shape.cornerRadius }
}

/// How a running app is marked under its icon — the three shapes the port covers.
enum DockRunningIndicatorStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    /// macOS' own 4 pt circle.
    case macDot
    /// Windows 11: a wide 16 pt pill for the frontmost app, a 6 pt pill for background apps, up to three pips.
    case windowsPill
    /// KDE Latte: a bottom edge bar tinted with the app's dominant brand colour.
    case latteBrandLine

    static let defaultsKey = "com.katikati.dock.runningIndicator"
    var id: String { rawValue }
}

/// Gaussian neighbour falloff for the magnification style: the item nearest the pointer peaks at `maxScale`, neighbours
/// fall off by distance, and anything farther than `spread` stays at 1.0 — so the dock never shimmers at rest.
enum DockMagnificationMath {
    static func scale(forItemAt index: Int,
                      cursorX: CGFloat,
                      itemCenters: [CGFloat],
                      maxScale: CGFloat = 1.35,
                      spread: CGFloat = 90) -> CGFloat {
        guard itemCenters.indices.contains(index), spread > 0 else { return 1 }
        let distance = abs(cursorX - itemCenters[index])
        guard distance < spread else { return 1 }
        // exp(-d² / 2σ²) with σ = spread/1.5: ~0.99 at the pointer, ~0.5 at 0.6·spread, 1.0 outside.
        let sigma = spread / 1.5
        let bell = exp(-(distance * distance) / (2 * sigma * sigma))
        return 1 + (max(1, maxScale) - 1) * bell
    }
}

/// iPadOS-style cursor attraction and the 3D tilt used by the spring-lift style. Both clamp, so a pointer at the far edge
/// of a chip can never ask for a translation or an angle the icon cannot draw.
enum DockTiltMath {
    /// Translation toward the pointer, capped at 18 % of the icon size.
    static func magneticOffset(cursorOffset: CGFloat, iconSize: CGFloat) -> CGFloat {
        guard iconSize > 0 else { return 0 }
        let limit = iconSize * 0.18
        return min(max(cursorOffset * 0.25, -limit), limit)
    }

    /// Tilt in degrees: ±10° around Y and ±6° around X, scaled by the pointer's offset inside the icon.
    static func tiltAngles(cursorOffset: CGPoint, iconSize: CGFloat) -> (x: Double, y: Double) {
        guard iconSize > 0 else { return (0, 0) }
        let nx = max(-1, min(1, cursorOffset.x / (iconSize / 2)))
        let ny = max(-1, min(1, cursorOffset.y / (iconSize / 2)))
        return (x: Double(-ny) * 6, y: Double(nx) * 10)
    }
}

/// The state the running indicator draws. Pure so the three styles share one set of tests.
struct DockRunningIndicatorState: Equatable, Sendable {
    var width: CGFloat
    var opacity: Double
    var pipCount: Int

    /// `windowsPill`: 16 pt and opaque in front, 6 pt and dimmer behind; `latteBrandLine` is a 3 pt full-width line at
    /// 85 % (front) / 55 % (back); `macDot` keeps today's 4 pt dot.
    static func state(for style: DockRunningIndicatorStyle,
                      isFrontmost: Bool,
                      windowCount: Int) -> DockRunningIndicatorState {
        let windows = max(1, windowCount)
        switch style {
        case .macDot:
            return DockRunningIndicatorState(width: 4, opacity: isFrontmost ? 1 : 0.7, pipCount: 1)
        case .windowsPill:
            return DockRunningIndicatorState(width: isFrontmost ? 16 : 6,
                                             opacity: isFrontmost ? 1 : 0.8,
                                             pipCount: min(3, windows))
        case .latteBrandLine:
            return DockRunningIndicatorState(width: 18,
                                             opacity: isFrontmost ? 0.85 : 0.55,
                                             pipCount: min(3, windows))
        }
    }
}

/// Reduce Motion keeps the feedback but drops the movement: an icon that slides, tilts or jiggles under the pointer falls
/// back to a plain tint, and the tint-only style stays as it is.
enum DockMotionPolicy {
    static func hoverStyle(_ style: DockHoverAnimationStyle, reduceMotion: Bool) -> DockHoverAnimationStyle {
        guard reduceMotion else { return style }
        return style.movesTheIcon ? .colorAura : style
    }

    /// The press keeps its tint ripple; the three that move the icon become a short opacity dip instead.
    static func pressStyle(_ style: DockPressAnimationStyle, reduceMotion: Bool) -> DockPressAnimationStyle {
        guard reduceMotion else { return style }
        return .ripple
    }
}

enum DockBarHeightPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case compact // 44pt
    case regular // 54pt
    case relaxed // 64pt

    var id: String { rawValue }

    var points: CGFloat {
        switch self {
        case .compact: return 44.0
        case .regular: return 54.0
        case .relaxed: return 64.0
        }
    }
}
