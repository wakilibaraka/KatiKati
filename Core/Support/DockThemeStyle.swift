import Foundation
import CoreGraphics

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
