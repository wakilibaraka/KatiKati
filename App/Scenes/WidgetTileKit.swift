import AppKit
import SwiftUI

// Shared widget tile system (Phase 5e/5g): solid rounded tiles on a transparent window. Used by
// the calendar (right) and weather (left) stacks — one surface, one palette, one layout vocabulary.

struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Colours for one render pass: solid base by appearance, accent by palette.
struct TileEnv {
    let palette: TilePalette
    let isDark: Bool

    var base: Color { isDark ? Color(red: 0.14, green: 0.14, blue: 0.16) : .white }
    var text: Color { isDark ? .white : Color(white: 0.08) }
    var secondary: Color { isDark ? Color(white: 0.62) : Color(white: 0.42) }
    var hairline: Color { isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06) }

    func accent(_ tile: TileKind) -> Color {
        let c = palette.accent(for: tile)
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    /// White on saturated accents; near-black on light ones (yellow, pastel) so bands stay legible.
    func onAccent(_ tile: TileKind) -> Color {
        let c = palette.accent(for: tile)
        return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) > 0.68 ? Color(white: 0.12) : .white
    }
}

extension View {
    func tileSurface(_ env: TileEnv, radius: CGFloat = 22) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(env.base))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(env.hairline, lineWidth: 0.5))
            .shadow(color: .black.opacity(env.isDark ? 0.45 : 0.20), radius: 7, y: 3)
    }
}

// MARK: - Band tile chrome

struct BandTile<Header: View, Body: View>: View {
    let env: TileEnv
    let kind: TileKind
    let width: CGFloat
    let height: CGFloat
    var band: CGFloat = 30
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Body

    var body: some View {
        VStack(spacing: 0) {
            header()
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(env.onAccent(kind))
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: band, maxHeight: band, alignment: .leading)
                .background(env.accent(kind))
            content()
                .foregroundColor(env.text)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: width, height: height)
        .tileSurface(env)
    }
}

