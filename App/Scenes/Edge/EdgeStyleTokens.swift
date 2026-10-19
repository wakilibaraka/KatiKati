import SwiftUI

/// The numbers and colours one `EdgeBarStyle` gives the whole edge bar (pill, tabs, buttons, flyout plates, note sheets), so
/// the bar and the content behind it never drift into two designs. Paper tokens reproduce the original look exactly.
struct EdgeStyleTokens {
    let style: EdgeBarStyle
    let isDark: Bool
    let reduceTransparency: Bool

    var isGlass: Bool { style == .liquidGlass }
    /// Real `glassEffect` only on macOS 26 and only when transparency is allowed; otherwise frosted material or a solid fill.
    var usesSystemGlass: Bool {
        guard isGlass, !reduceTransparency else { return false }
        if #available(macOS 26.0, *) { return true }
        return false
    }

    var ink: Color { isDark ? .white : Color(white: 0.08) }
    var secondaryInk: Color { isDark ? Color(white: 0.68) : Color(white: 0.40) }
    var rim: Color { Color.white.opacity(isDark ? 0.16 : 0.55) }
    var plateRadius: CGFloat { isGlass ? Self.glassRadius : 20 }
    var shadow: Color { .black.opacity(isGlass ? 0.18 : 0.22) }
    /// Solid stand-in under Reduce Transparency.
    var solid: Color { isDark ? Color(red: 0.16, green: 0.16, blue: 0.18) : Color(white: 0.96) }

    static let glassRadius: CGFloat = 26
    static let morphSpring = Animation.spring(response: 0.4, dampingFraction: 0.82)
}

private struct EdgeTokensKey: EnvironmentKey { static let defaultValue = EdgeBarStyle.paper }

extension EnvironmentValues {
    var edgeBarStyle: EdgeBarStyle {
        get { self[EdgeTokensKey.self] }
        set { self[EdgeTokensKey.self] = newValue }
    }
}

/// A glass surface in `shape`, tinted by `tint`: system Liquid Glass on macOS 26, frosted material below it, a solid fill under
/// Reduce Transparency. Always carries a hairline rim so it reads on any wallpaper.
struct EdgeGlassSurface<S: Shape>: View {
    let shape: S
    var tint: Color? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let t = EdgeStyleTokens(style: .liquidGlass, isDark: scheme == .dark, reduceTransparency: reduceTransparency)
        ZStack {
            if t.usesSystemGlass, #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular.tint(tint?.opacity(0.35)).interactive(false), in: shape)
            } else if reduceTransparency {
                shape.fill(t.solid)
                if let tint { shape.fill(tint.opacity(0.22)) }
            } else {
                shape.fill(.ultraThinMaterial)
                if let tint { shape.fill(tint.opacity(0.25)) }
            }
        }
        .overlay(shape.stroke(t.rim, lineWidth: 0.75))
        .compositingGroup()
        .shadow(color: t.shadow, radius: 8, y: 2)
        .allowsHitTesting(false)
    }
}
