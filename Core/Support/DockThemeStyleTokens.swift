import Foundation
import CoreGraphics

struct DockRGBA: Equatable {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
    let a: CGFloat
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
