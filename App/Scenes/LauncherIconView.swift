import SwiftUI

/// The launcher FAB glyph (Phase 7B-L7): a gradient squircle with one of three marks. Pure SwiftUI shapes, so it is
/// sharp at any size and costs nothing at rest.
struct LauncherIconView: View {
    let style: LauncherIconStyle
    let size: CGFloat

    var body: some View {
        if style == .glass {
            // The glass launcher icon: a supplied artwork (background removed), shipped as an asset.
            Image("LauncherIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.22), radius: size * 0.07, y: size * 0.03)
                .accessibilityHidden(true)
        } else {
            gradientIcon
        }
    }

    private var gradientIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.42, green: 0.36, blue: 0.98), Color(red: 0.20, green: 0.72, blue: 0.96)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: max(0.5, size * 0.02))
            mark
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.18), radius: size * 0.08, y: size * 0.03)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var mark: some View {
        switch style {
        case .glass:
            EmptyView()
        case .orbit:
            ZStack {
                Circle().fill(Color.white).frame(width: size * 0.26, height: size * 0.26)
                Ellipse().stroke(Color.white.opacity(0.9), lineWidth: size * 0.07)
                    .frame(width: size * 0.74, height: size * 0.32)
                    .rotationEffect(.degrees(-28))
                Circle().fill(Color.white).frame(width: size * 0.11, height: size * 0.11)
                    .offset(x: size * 0.31, y: -size * 0.09)
            }
        case .tiles:
            let t = size * 0.2, g = size * 0.07
            VStack(spacing: g) {
                HStack(spacing: g) { tile(t, 0.95); tile(t, 0.6) }
                HStack(spacing: g) { tile(t, 0.6); tile(t, 0.95) }
            }
        case .petal:
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    Ellipse().fill(Color.white.opacity(i % 2 == 0 ? 0.95 : 0.65))
                        .frame(width: size * 0.2, height: size * 0.42)
                        .offset(y: -size * 0.14)
                        .rotationEffect(.degrees(Double(i) * 90))
                }
            }
        }
    }

    private func tile(_ t: CGFloat, _ opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: t * 0.32, style: .continuous).fill(Color.white.opacity(opacity)).frame(width: t, height: t)
    }
}
