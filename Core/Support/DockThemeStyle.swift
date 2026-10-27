import Foundation
import CoreGraphics

/// Phase 12 — the Appearance page's two plate knobs, carried together because they always travel
/// together: from the store, through the environment, to the one backdrop all five floating surfaces
/// share. Pure values, no SwiftUI, so the identity points are unit-tested.
struct ThemeTuning: Equatable {
    var vibrancy: CGFloat = DockThemeStyle.identityVibrancy
    /// `1` = the preset's own colours; above it separates the tint from the wallpaper, below it
    /// flattens the preset.
    var contrast: CGFloat = 1
    /// `1` = the plate's tint as it was before this knob existed; lower lays the tint down thicker
    /// until the plate reads solid.
    var translucency: CGFloat = DockThemeStyle.identityTranslucency

    static let identity = ThemeTuning()

    /// Whatever the store or a stale key hands over, clamped to the sliders' own range.
    static func resolved(vibrancy: CGFloat, contrast: CGFloat, translucency: CGFloat = DockThemeStyle.identityTranslucency) -> ThemeTuning {
        ThemeTuning(
            vibrancy: min(max(vibrancy, DockThemeStyle.vibrancyRange.lowerBound), DockThemeStyle.vibrancyRange.upperBound),
            contrast: min(max(contrast, DockThemeStyle.contrastRange.lowerBound), DockThemeStyle.contrastRange.upperBound),
            translucency: min(max(translucency, DockThemeStyle.translucencyRange.lowerBound), DockThemeStyle.translucencyRange.upperBound)
        )
    }
}

/// Dock theme material style, covering both light and dark appearances.
enum DockThemeStyle: Equatable, Codable {
    case system
    case translucent
    case crystalClear
    case obsidianDark
    case monochrome
    case titaniumFrost
    case auroraGlow
    case deepOcean
    case forestMoss
    case cyberpunkGlass
    case emberSunset
    case roseQuartz
    /// The poured body: one near-black mass whose outline swells around the item under the
    /// pointer (`FluidRailBody`). The plate tint below only feeds the swatch and the surfaces that
    /// still draw a rounded plate; the rail itself draws its own silhouette.
    case fluid
    
    case customRGBA(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
    case auto
    
    var token: String {
        switch self {
        case .system: return "system"
        case .translucent: return "translucent"
        case .crystalClear: return "crystalClear"
        case .obsidianDark: return "obsidianDark"
        case .monochrome: return "monochrome"
        case .titaniumFrost: return "titaniumFrost"
        case .auroraGlow: return "auroraGlow"
        case .deepOcean: return "deepOcean"
        case .forestMoss: return "forestMoss"
        case .cyberpunkGlass: return "cyberpunkGlass"
        case .emberSunset: return "emberSunset"
        case .roseQuartz: return "roseQuartz"
        case .fluid: return "fluid"
        case .auto: return "auto"
        case .customRGBA(let r, let g, let b, let a):
            return "custom:\(r),\(g),\(b),\(a)"
        }
    }
    
    init?(token: String) {
        switch token {
        case "system": self = .system
        case "translucent": self = .translucent
        case "crystalClear": self = .crystalClear
        case "obsidianDark": self = .obsidianDark
        case "monochrome": self = .monochrome
        case "titaniumFrost": self = .titaniumFrost
        case "auroraGlow": self = .auroraGlow
        case "deepOcean": self = .deepOcean
        case "forestMoss": self = .forestMoss
        case "cyberpunkGlass": self = .cyberpunkGlass
        case "emberSunset": self = .emberSunset
        case "roseQuartz": self = .roseQuartz
        case "fluid": self = .fluid
        case "auto": self = .auto
        default:
            if token.hasPrefix("custom:") {
                let parts = token.dropFirst(7).split(separator: ",")
                if parts.count == 4,
                   let r = Double(parts[0]), let g = Double(parts[1]), let b = Double(parts[2]), let a = Double(parts[3]) {
                    self = .customRGBA(r: CGFloat(r), g: CGFloat(g), b: CGFloat(b), a: CGFloat(a))
                    return
                }
            }
            return nil
        }
    }
}

extension DockThemeStyle {
    /// Resolves `.auto` to `roseQuartz` for light appearance and `obsidianDark` for dark appearance.
    /// Retains user's pinned choice otherwise.
    func resolved(for appearance: AppearanceMode) -> DockThemeStyle {
        if let debugOverride = DebugSwitch.dockTheme.value(),
           let theme = DockThemeStyle(token: debugOverride) {
            return theme
        }
        guard self == .auto else { return self }
        switch appearance {
        case .light:
            return .roseQuartz
        case .dark:
            return .obsidianDark
        case .system:
            // The actual system appearance is not known here; 
            // the resolution against system appearance happens downstream via NSAppearance.
            // But we can fallback to roseQuartz as a structural default for the auto placeholder.
            return .roseQuartz 
        }
    }
}

extension DockThemeStyle {
    /// Share of a preset's `baseTint` alpha laid over the system glass / visual-effect plate.
    /// The glass already brings its own body, so the full token alpha (up to 0.85) reads as paint.
    static let plateOverlayStrength: CGFloat = 0.55

    /// The Appearance page's two plate knobs (Phase 12). `vibrancy` scales the tint's alpha and the
    /// identity is the 0.55 this file has always used, so a user who never touches the slider sees
    /// exactly the plate they saw before it existed. `contrast` pushes each channel away from
    /// mid-grey (1 = untouched): the sweep found the twelve presets nearly indistinguishable on a
    /// dark backdrop, and this is the slider that separates them without touching the frozen columns.
    static let identityVibrancy: CGFloat = plateOverlayStrength
    static let vibrancyRange: ClosedRange<CGFloat> = 0.1 ... 1.0
    static let contrastRange: ClosedRange<CGFloat> = 0.5 ... 2.0
    /// The third plate knob (2026-10-26). `translucency` scales the tint's alpha the way `vibrancy`
    /// does, but in the other direction: **1 is today's plate**, and toward 0 the tint is laid down
    /// up to twice as thick, which is what makes the plate read solid over whatever backdrop is
    /// behind it (the native glass takes no tint of its own — see `DockLiquidGlassConfiguration`).
    /// Multiplying by exactly 1 is bit-exact, so the default leaves every existing plate untouched.
    static let identityTranslucency: CGFloat = 1
    static let translucencyRange: ClosedRange<CGFloat> = 0.2 ... 1.0

    /// Colour laid over the dock plate on the system-glass and pre-26 paths, which otherwise drop
    /// the preset tint entirely — the reason picking a theme changed nothing visible (Phase 11c, B6).
    /// `auto` and `system` keep the untinted native look (pixel-frozen default).
    /// Whether this style colours the dock plate (everything but `auto` / `system`).
    var tintsPlate: Bool {
        switch self {
        case .auto, .system: return false
        default: return true
        }
    }

    /// The poured-body theme. Only the rail and the drawer capsule draw a fluid body; every other
    /// surface keeps the rounded plate this file has always produced.
    var isFluid: Bool { self == .fluid }

    func plateOverlay(
        baseTint: DockRGBA,
        vibrancy: CGFloat = identityVibrancy,
        contrast: CGFloat = 1,
        translucency: CGFloat = identityTranslucency
    ) -> DockRGBA? {
        guard tintsPlate else { return nil }
        return Self.plateTint(baseTint, vibrancy: vibrancy, contrast: contrast, translucency: translucency)
    }

    /// The gradient's bottom stop (`DockGradientPreset`), through the same vibrancy/contrast pass as
    /// the top one so both stops still read as one material. `nil` when the style tints nothing or
    /// has no gradient, i.e. `overlayFill` then draws the flat tint it always drew.
    func plateOverlayBottom(
        baseTintBottom: DockRGBA?,
        vibrancy: CGFloat = identityVibrancy,
        contrast: CGFloat = 1,
        translucency: CGFloat = identityTranslucency
    ) -> DockRGBA? {
        guard tintsPlate, let bottom = baseTintBottom else { return nil }
        return Self.plateTint(bottom, vibrancy: vibrancy, contrast: contrast, translucency: translucency)
    }

    private static func plateTint(_ colour: DockRGBA, vibrancy: CGFloat, contrast: CGFloat,
                                  translucency: CGFloat) -> DockRGBA {
        // Translucency 1 is the identity: `a * 1` is bit-exact, so an untouched slider cannot
        // move a pixel. Lower values lay the same colour down thicker, clamped at opaque.
        let alpha = min(colour.a * vibrancy * (2 - translucency), 1)
        // `contrast == 1` leaves the channels bit-for-bit alone: `0.5 + (v - 0.5) * 1` is *not* exactly
        // `v` in binary floating point (0.05 comes back as 0.04999999999999999), and "a user who never
        // moved the slider sees the plate they had before it existed" is a promise about pixels.
        guard contrast != 1 else {
            return DockRGBA(r: colour.r, g: colour.g, b: colour.b, a: alpha)
        }
        func push(_ channel: CGFloat) -> CGFloat {
            min(max(0.5 + (channel - 0.5) * contrast, 0), 1)
        }
        return DockRGBA(r: push(colour.r), g: push(colour.g), b: push(colour.b), a: alpha)
    }
}

