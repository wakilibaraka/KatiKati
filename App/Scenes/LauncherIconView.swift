import SwiftUI

/// The launcher FAB glyph: rendered with liquid glass depth, Apple jewel-tone gradients,
/// and smooth scale transitions. Pure SwiftUI shapes, sharp at any display scale.
struct LauncherIconView: View {
    let style: LauncherIconStyle
    let size: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch style {
        case .liquidBento:
            liquidBentoIcon
        case .visionMono:
            visionMonoIcon
        case .starburstAperture:
            starburstApertureIcon
        case .themed:
            themedIcon
        case .glass:
            Image("LauncherIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.22), radius: size * 0.07, y: size * 0.03)
                .accessibilityHidden(true)
        case .orbit, .tiles, .petal:
            gradientIcon
        }
    }

    // MARK: - Preset 1: Liquid Bento Matrix (Default)

    private var liquidBentoIcon: some View {
        let cell = size * 0.22
        let gap = size * 0.075
        let palettes: [[Color]] = [
            // Row 0
            [Color(red: 1.0, green: 0.44, blue: 0.35), Color(red: 0.95, green: 0.28, blue: 0.24)],
            [Color(red: 1.0, green: 0.68, blue: 0.20), Color(red: 0.95, green: 0.52, blue: 0.14)],
            [Color(red: 1.0, green: 0.84, blue: 0.26), Color(red: 0.96, green: 0.72, blue: 0.18)],
            // Row 1
            [Color(red: 0.32, green: 0.88, blue: 0.54), Color(red: 0.18, green: 0.74, blue: 0.42)],
            [Color(red: 0.24, green: 0.82, blue: 0.96), Color(red: 0.12, green: 0.68, blue: 0.88)],
            [Color(red: 0.30, green: 0.58, blue: 0.98), Color(red: 0.18, green: 0.44, blue: 0.92)],
            // Row 2
            [Color(red: 0.50, green: 0.40, blue: 0.96), Color(red: 0.38, green: 0.26, blue: 0.88)],
            [Color(red: 0.80, green: 0.38, blue: 0.94), Color(red: 0.66, green: 0.24, blue: 0.84)],
            [Color(red: 0.98, green: 0.34, blue: 0.60), Color(red: 0.88, green: 0.20, blue: 0.46)]
        ]

        return ZStack {
            // Frosted micro-plate backing
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color.white.opacity(scheme == .dark ? 0.06 : 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(Color.white.opacity(scheme == .dark ? 0.16 : 0.30), lineWidth: 0.75)
                )

            // 3x3 Jewel Bento Matrix
            VStack(spacing: gap) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<3, id: \.self) { col in
                            let index = row * 3 + col
                            let colors = palettes[index]
                            RoundedRectangle(cornerRadius: cell * 0.34, style: .continuous)
                                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .overlay(
                                    RoundedRectangle(cornerRadius: cell * 0.34, style: .continuous)
                                        .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
                                )
                                .shadow(color: colors[0].opacity(0.35), radius: 1.5, x: 0, y: 1)
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: - Preset 2: Vision Monochrome

    private var visionMonoIcon: some View {
        let cell = size * 0.22
        let gap = size * 0.075

        return ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color.white.opacity(scheme == .dark ? 0.08 : 0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(Color.white.opacity(scheme == .dark ? 0.20 : 0.35), lineWidth: 0.75)
                )

            VStack(spacing: gap) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<3, id: \.self) { col in
                            RoundedRectangle(cornerRadius: cell * 0.34, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [Color.white.opacity(0.92), Color.white.opacity(0.60)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .overlay(
                                    RoundedRectangle(cornerRadius: cell * 0.34, style: .continuous)
                                        .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
                                )
                                .shadow(color: Color.black.opacity(0.2), radius: 1, x: 0, y: 1)
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: - Preset 3: Starburst Aperture

    private var starburstApertureIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.42, green: 0.36, blue: 0.98), Color(red: 0.20, green: 0.72, blue: 0.96)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(Color.white.opacity(0.3), lineWidth: 0.75)
                )

            ForEach(0..<8, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(i % 2 == 0 ? 0.95 : 0.72))
                    .frame(width: size * 0.11, height: size * 0.28)
                    .offset(y: -size * 0.16)
                    .rotationEffect(.degrees(Double(i) * 45.0))
            }

            Circle()
                .fill(Color.white)
                .frame(width: size * 0.22, height: size * 0.22)
                .shadow(color: Color.black.opacity(0.25), radius: 1.5, x: 0, y: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(red: 0.42, green: 0.36, blue: 0.98).opacity(0.3), radius: size * 0.08, y: size * 0.03)
        .accessibilityHidden(true)
    }

    // MARK: - Legacy Styles

    private var themedIcon: some View {
        let hues = LauncherIconStyle.themedCellHues
        let cell = size * 0.19, gap = size * 0.065
        return ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [Color.accentColor.opacity(scheme == .dark ? 0.38 : 0.28),
                                              Color.accentColor.opacity(scheme == .dark ? 0.12 : 0.06)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(Color.white.opacity(scheme == .dark ? 0.22 : 0.5), lineWidth: max(0.5, size * 0.025))
            VStack(spacing: gap) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<3, id: \.self) { col in
                            RoundedRectangle(cornerRadius: cell * 0.32, style: .continuous)
                                .fill(Color(hue: hues[row * 3 + col], saturation: 0.72, brightness: scheme == .dark ? 0.95 : 0.9))
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.2), radius: size * 0.08, y: size * 0.03)
        .accessibilityHidden(true)
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
        case .liquidBento, .visionMono, .starburstAperture, .glass, .themed:
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
