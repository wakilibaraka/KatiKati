import SwiftUI

/// Single interactive wedge view on the radial dial (Phase 31b).
struct RadialDialWedgeView: View {
    let sector: RadialDialGeometry.Sector
    let item: RadialDialItem
    let isHovered: Bool
    let theme: RadialDialTheme
    let center: CGPoint
    let onSelect: () -> Void

    var body: some View {
        ZStack {
            // Sector background fill
            RadialSectorShape(
                startAngle: Angle(radians: Double(sector.startAngle)),
                endAngle: Angle(radians: Double(sector.endAngle)),
                innerRadius: sector.innerRadius,
                outerRadius: sector.outerRadius
            )
            .fill(wedgeFill)

            // Wedge divider / boundary stroke
            RadialSectorShape(
                startAngle: Angle(radians: Double(sector.startAngle)),
                endAngle: Angle(radians: Double(sector.endAngle)),
                innerRadius: sector.innerRadius,
                outerRadius: sector.outerRadius
            )
            .stroke(Color.white.opacity(isHovered ? 0.35 : 0.12), lineWidth: 1)

            // Content positioned at the geometric sector center
            let pos = contentPosition
            VStack(spacing: 2) {
                iconView(item.icon)
                    .frame(width: 26, height: 26)

                Text(verbatim: item.title)
                    .font(.system(size: 10, weight: isHovered ? .bold : .medium, design: .rounded))
                    .foregroundColor(isHovered ? .white : .white.opacity(0.85))
                    .lineLimit(1)
                    .shadow(color: Color.black.opacity(0.6), radius: 2, x: 0, y: 1)

                if item.hasSubmenu {
                    Text(verbatim: "•••")
                        .font(.system(size: 6, weight: .black))
                        .foregroundColor(isHovered ? .white : .white.opacity(0.5))
                        .offset(y: -2)
                }
            }
            .scaleEffect(isHovered ? 1.08 : 1.0)
            .position(pos)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
        }
    }

    private var contentPosition: CGPoint {
        // Slightly shift outward on hover (spring motion)
        let fraction: CGFloat = isHovered ? 0.54 : 0.50
        return sector.centerPoint(in: center, atFraction: fraction)
    }

    @ViewBuilder
    private func iconView(_ icon: RadialDialIcon) -> some View {
        switch icon {
        case .sfSymbol(let name), .system(let name):
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .foregroundColor(iconColor)
        case .app(let bundleID):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(5)
                    .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(iconColor)
            }
        }
    }

    private var iconColor: Color {
        if isHovered { return .white }
        if let hex = item.accentHex, let color = Color(hex: hex) {
            return color
        }
        return .white.opacity(0.9)
    }

    private var wedgeFill: some ShapeStyle {
        if !isHovered {
            return AnyShapeStyle(Color.white.opacity(0.04))
        }

        switch theme {
        case .lilacGlass:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.58, green: 0.48, blue: 0.95).opacity(0.85),
                        Color(red: 0.38, green: 0.28, blue: 0.78).opacity(0.85)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .darkObsidian:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.24),
                        Color.white.opacity(0.12)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case .systemFrosted:
            return AnyShapeStyle(
                Color.accentColor.opacity(0.5)
            )
        case .neonCyber:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.0, green: 0.85, blue: 0.95).opacity(0.75),
                        Color(red: 0.85, green: 0.15, blue: 0.65).opacity(0.65)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
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
