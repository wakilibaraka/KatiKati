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

    static func resolve(style: DockThemeStyle, appearance: AppearanceMode) -> DockThemeStyleTokens {
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
