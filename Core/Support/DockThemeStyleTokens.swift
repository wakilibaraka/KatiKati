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
        baseTint: DockRGBA(r: 0.9, g: 0.9, b: 0.9, a: 0.5),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.3),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.2),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.4),
        blurRadius: 30.0,
        prefersDarkContent: true
    )

    static let translucentDark = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.1, g: 0.1, b: 0.1, a: 0.6),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.05),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.0),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.15),
        blurRadius: 30.0,
        prefersDarkContent: false
    )

    static let crystalClearLight = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.9, g: 0.9, b: 0.9, a: 0.5),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.3),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.2),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.4),
        blurRadius: 30.0,
        prefersDarkContent: true
    )

    static let crystalClearDark = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.1, g: 0.1, b: 0.1, a: 0.6),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.05),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.0),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.15),
        blurRadius: 30.0,
        prefersDarkContent: false
    )

    static let obsidianDarkLight = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.2, g: 0.2, b: 0.2, a: 0.8),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.3),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.2),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.4),
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
        baseTint: DockRGBA(r: 0.9, g: 0.9, b: 0.9, a: 0.5),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.3),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.2),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.4),
        blurRadius: 30.0,
        prefersDarkContent: true
    )

    static let monochromeDark = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.1, g: 0.1, b: 0.1, a: 0.6),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.05),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.0),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.15),
        blurRadius: 30.0,
        prefersDarkContent: false
    )

    static let titaniumFrostLight = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.9, g: 0.9, b: 0.9, a: 0.5),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.3),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.2),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.4),
        blurRadius: 30.0,
        prefersDarkContent: true
    )

    static let titaniumFrostDark = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.1, g: 0.1, b: 0.1, a: 0.6),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.05),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.0),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.15),
        blurRadius: 30.0,
        prefersDarkContent: false
    )

    static let auroraGlowLight = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.9, g: 0.9, b: 0.9, a: 0.5),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.3),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.2),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.4),
        blurRadius: 30.0,
        prefersDarkContent: true
    )

    static let auroraGlowDark = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.1, g: 0.1, b: 0.1, a: 0.6),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.05),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.0),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.15),
        blurRadius: 30.0,
        prefersDarkContent: false
    )

    static let deepOceanLight = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.9, g: 0.9, b: 0.9, a: 0.5),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.3),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.2),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.4),
        blurRadius: 30.0,
        prefersDarkContent: true
    )

    static let deepOceanDark = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.1, g: 0.1, b: 0.1, a: 0.6),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.05),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.0),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.15),
        blurRadius: 30.0,
        prefersDarkContent: false
    )

    static let forestMossLight = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.9, g: 0.9, b: 0.9, a: 0.5),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.3),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.2),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.4),
        blurRadius: 30.0,
        prefersDarkContent: true
    )

    static let forestMossDark = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.1, g: 0.1, b: 0.1, a: 0.6),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.05),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.0),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.15),
        blurRadius: 30.0,
        prefersDarkContent: false
    )

    static let cyberpunkGlassLight = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.9, g: 0.9, b: 0.9, a: 0.5),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.3),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.2),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.4),
        blurRadius: 30.0,
        prefersDarkContent: true
    )

    static let cyberpunkGlassDark = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.1, g: 0.1, b: 0.1, a: 0.6),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.05),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.0),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.15),
        blurRadius: 30.0,
        prefersDarkContent: false
    )

    static let emberSunsetLight = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.9, g: 0.9, b: 0.9, a: 0.5),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.3),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.2),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.4),
        blurRadius: 30.0,
        prefersDarkContent: true
    )

    static let emberSunsetDark = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.1, g: 0.1, b: 0.1, a: 0.6),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.05),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.0),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.15),
        blurRadius: 30.0,
        prefersDarkContent: false
    )

    static let roseQuartzLight = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.95, g: 0.85, b: 0.88, a: 0.6),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.3),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.2),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.4),
        blurRadius: 30.0,
        prefersDarkContent: true
    )

    static let roseQuartzDark = DockThemeStyleTokens(
        baseTint: DockRGBA(r: 0.3, g: 0.2, b: 0.25, a: 0.7),
        gradientSheen: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.05),
        glow: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.0),
        rim: DockRGBA(r: 1.0, g: 1.0, b: 1.0, a: 0.15),
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
