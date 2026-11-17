import SwiftUI

/// The central navigation and breadcrumb hub for the radial dial (SLICE RD-2).
struct RadialDialCenterHub: View {
    let title: String
    let breadcrumbs: [String]
    let canGoBack: Bool
    let isHovered: Bool
    let theme: RadialDialTheme

    var body: some View {
        ZStack {
            Circle()
                .fill(hubBackground)
                .overlay(Circle().strokeBorder(Color.white.opacity(isHovered ? 0.45 : 0.2), lineWidth: 1))
                .overlay(Circle().inset(by: 5).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)

            VStack(spacing: 4) {
                if canGoBack {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Text(isHovered ? "Back" : title)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                        .lineLimit(1)
                } else {
                    Image(systemName: "circle.grid.cross.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(isHovered ? 1 : 0.88))
                    Text(verbatim: title)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                if breadcrumbs.count > 1 {
                    HStack(spacing: 3) {
                        ForEach(0..<breadcrumbs.count, id: \.self) { idx in
                            Capsule()
                                .fill(Color.white.opacity(idx == breadcrumbs.count - 1 ? 1 : 0.35))
                                .frame(width: idx == breadcrumbs.count - 1 ? 10 : 4, height: 3.5)
                        }
                    }
                }
            }
            .frame(width: 72)
        }
        .frame(width: RadialDialMetrics.hubSize, height: RadialDialMetrics.hubSize)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: canGoBack)
    }

    private var hubBackground: some ShapeStyle {
        let lift = isHovered ? 0.98 : 0.88
        switch theme {
        case .lilacGlass:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.50, green: 0.43, blue: 0.82).opacity(lift),
                         Color(red: 0.34, green: 0.28, blue: 0.62).opacity(lift)],
                startPoint: .top, endPoint: .bottom))
        case .darkObsidian:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.18, green: 0.18, blue: 0.22).opacity(lift),
                         Color(red: 0.10, green: 0.10, blue: 0.13).opacity(lift)],
                startPoint: .top, endPoint: .bottom))
        case .systemFrosted:
            return AnyShapeStyle(Color.accentColor.opacity(isHovered ? 0.85 : 0.65))
        case .neonCyber:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.08, green: 0.12, blue: 0.22).opacity(lift),
                         Color(red: 0.04, green: 0.06, blue: 0.14).opacity(lift)],
                startPoint: .top, endPoint: .bottom))
        }
    }
}
