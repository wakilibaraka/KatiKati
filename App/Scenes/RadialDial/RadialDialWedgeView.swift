import SwiftUI

/// Single interactive wedge view on the radial dial (SLICE RD-2).
struct RadialDialWedgeView: View {
    let sector: RadialDialGeometry.Sector
    let node: RadialSliceNode
    let isHovered: Bool
    let appeared: Bool
    let reduceMotion: Bool
    let theme: RadialDialTheme
    let center: CGPoint

    /// Half the angular gap between neighbours; the round-join stroke below closes most of it.
    private static let halfGap: Double = 0.032
    private static let corner: CGFloat = 4

    private var accent: Color? { node.accentHex.flatMap { Color(hex: $0) } }
    private var lift: CGFloat { isHovered && !reduceMotion ? 7 : 0 }

    private var shape: RadialSectorShape {
        RadialSectorShape(
            startAngle: Angle(radians: Double(sector.startAngle) + Self.halfGap),
            endAngle: Angle(radians: Double(sector.endAngle) - Self.halfGap),
            innerRadius: sector.innerRadius + Self.corner / 2,
            outerRadius: sector.outerRadius - Self.corner / 2
        )
    }

    var body: some View {
        ZStack {
            // Resting tint: each wedge keeps a quiet hint of its own colour.
            layer(AnyShapeStyle((accent ?? .white).opacity(accent == nil ? 0.06 : 0.16)))

            // Hover tint fades in over the resting one (gradient styles can't cross-animate).
            layer(hoverFill)
                .opacity(isHovered ? 1 : 0)
                .shadow(color: (accent ?? .white).opacity(isHovered ? 0.65 : 0), radius: 14)

            shape
                .stroke(Color.white.opacity(isHovered ? 0.55 : 0.10), lineWidth: isHovered ? 1.5 : 1)

            content
        }
        .offset(x: cos(sector.midAngle) * lift, y: sin(sector.midAngle) * lift)
        .animation(hoverAnimation, value: isHovered)
        // Entrance: wedges bloom outward from the hub with RD-2 spring physics.
        .scaleEffect(appeared ? 1 : 0.55)
        .opacity(appeared ? 1 : 0)
        .animation(
            reduceMotion ? .easeOut(duration: 0.12)
                : .spring(response: 0.32, dampingFraction: 0.78).delay(Double(sector.index) * 0.018),
            value: appeared
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: node.title))
        .accessibilityAddTraits(.isButton)
    }

    private var hoverAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.24, dampingFraction: 0.68)
    }

    private func layer(_ style: AnyShapeStyle) -> some View {
        ZStack {
            shape.fill(style)
            shape.stroke(style, style: StrokeStyle(lineWidth: Self.corner, lineJoin: .round))
        }
    }

    private var content: some View {
        let pos = sector.centerPoint(in: center, atFraction: 0.48)
        return ZStack {
            VStack(spacing: 3) {
                iconView(node.icon)
                    .frame(width: 26, height: 26)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                HStack(spacing: 2) {
                    Text(verbatim: node.title)
                        .font(.system(size: 10, weight: isHovered ? .bold : .medium, design: .rounded))
                        .foregroundColor(.white.opacity(isHovered ? 1 : 0.88))
                        .lineLimit(1)
                    if node.isSubmenu {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.white.opacity(isHovered ? 0.95 : 0.6))
                    }
                }
                .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
            }
            .scaleEffect(isHovered && !reduceMotion ? 1.08 : 1)
            .position(pos)

            if sector.index < 8 {
                Text(verbatim: "\(sector.index + 1)")
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(isHovered ? 1 : 0.72))
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(Color.black.opacity(isHovered ? 0.45 : 0.22)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(isHovered ? 0.55 : 0.16), lineWidth: 0.75))
                    .position(sector.centerPoint(in: center, atFraction: 0.86))
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private func iconView(_ icon: RadialDialIcon) -> some View {
        switch icon {
        case .sfSymbol(let name), .system(let name):
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .foregroundColor(isHovered ? .white : (accent ?? .white.opacity(0.9)))
        case .app(let bundleID):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.white.opacity(0.9))
            }
        }
    }

    private var hoverFill: AnyShapeStyle {
        switch theme {
        case .lilacGlass, .systemFrosted:
            let base = accent ?? (theme == .lilacGlass ? Color(red: 0.58, green: 0.48, blue: 0.95) : .accentColor)
            return AnyShapeStyle(LinearGradient(
                colors: [base.opacity(0.95), base.opacity(0.62)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .darkObsidian:
            return AnyShapeStyle(LinearGradient(
                colors: [.white.opacity(0.30), .white.opacity(0.14)],
                startPoint: .top, endPoint: .bottom))
        case .neonCyber:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.0, green: 0.85, blue: 0.95).opacity(0.8),
                         Color(red: 0.85, green: 0.15, blue: 0.65).opacity(0.7)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
}

// Hex color helper
private extension Color {
    init?(hex: String) {
        let r, g, b, a: Double
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: cleanHex).scanHexInt64(&int) else { return nil }
        switch cleanHex.count {
        case 6: // RGB (24-bit)
            (r, g, b, a) = (
                Double((int >> 16) & 0xff) / 255,
                Double((int >> 8) & 0xff) / 255,
                Double(int & 0xff) / 255,
                1.0
            )
        case 8: // ARGB (32-bit)
            (r, g, b, a) = (
                Double((int >> 16) & 0xff) / 255,
                Double((int >> 8) & 0xff) / 255,
                Double(int & 0xff) / 255,
                Double((int >> 24) & 0xff) / 255
            )
        default:
            return nil
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
