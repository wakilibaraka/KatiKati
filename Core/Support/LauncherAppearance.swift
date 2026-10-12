import Foundation

/// Launcher backdrop (Phase 7B-L6). Raw values are stored in `com.katikati.launcher.theme`; never rename them.
enum LauncherTheme: String, CaseIterable, Sendable {
    case system     // follows macOS light/dark over a blurred desktop
    case light
    case dark
    case glass      // lighter blur, little dimming
    case desktop    // the current desktop picture, blurred

    static let `default`: LauncherTheme = .system
    static func parse(_ stored: String?) -> LauncherTheme { stored.flatMap(LauncherTheme.init(rawValue:)) ?? .default }
}

/// A colour wash laid over the backdrop. `none` leaves it untouched.
enum LauncherTint: String, CaseIterable, Sendable {
    case none, blue, purple, pink, orange, green

    static let `default`: LauncherTint = .none
    static func parse(_ stored: String?) -> LauncherTint { stored.flatMap(LauncherTint.init(rawValue:)) ?? .default }

    /// sRGB components for the wash, nil for `none`.
    var rgb: (r: Double, g: Double, b: Double)? {
        switch self {
        case .none: return nil
        case .blue: return (0.20, 0.45, 1.00)
        case .purple: return (0.55, 0.30, 0.95)
        case .pink: return (1.00, 0.35, 0.60)
        case .orange: return (1.00, 0.55, 0.20)
        case .green: return (0.20, 0.75, 0.45)
        }
    }

    /// Strength of the wash over the blur.
    static let washOpacity = 0.28
}

/// The launcher FAB's glyph (Phase 7B-L7). Raw values are stored in `com.katikati.launcher.icon`; never rename them.
enum LauncherIconStyle: String, CaseIterable, Sendable {
    /// App-style frosted-glass panel with a search pill and app tiles (default).
    case glass
    case orbit
    case tiles
    case petal

    static let `default`: LauncherIconStyle = .glass
    static func parse(_ stored: String?) -> LauncherIconStyle { stored.flatMap(LauncherIconStyle.init(rawValue:)) ?? .default }
}
