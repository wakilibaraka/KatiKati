import SwiftUI

/// The central navigation and pager hub for the radial dial (Phase 31b).
/// Purely visual: the dial's pointer-up handler reads the click zone (see `RadialDialState.hubZone`),
/// so a click on a chevron can never also fire the center action.
struct RadialDialCenterHub: View {
    let title: String
    let pageCount: Int
    let pageIndex: Int
    let centerItem: RadialDialItem?
    let isHovered: Bool
    /// -1 over the left chevron, 1 over the right one, 0 elsewhere on the hub.
    let zone: Int
    let theme: RadialDialTheme

    var body: some View {
        ZStack {
            Circle()
                .fill(hubBackground)
                .overlay(Circle().strokeBorder(Color.white.opacity(isHovered ? 0.4 : 0.2), lineWidth: 1))
                .overlay(Circle().inset(by: 5).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)

            HStack(spacing: 0) {
                chevron("chevron.left", active: isHovered && zone < 0)
                centerContent
                    .frame(width: 52)
                chevron("chevron.right", active: isHovered && zone > 0)
            }
        }
        .frame(width: RadialDialMetrics.hubSize, height: RadialDialMetrics.hubSize)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: zone)
    }

    @ViewBuilder
    private var centerContent: some View {
        if let centerItem, isHovered, zone == 0 {
            VStack(spacing: 3) {
                centerIconView(centerItem.icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.white)
                Text(verbatim: centerItem.title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
            }
            .transition(.opacity)
        } else {
            VStack(spacing: 5) {
                Text(verbatim: title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if pageCount > 1 {
                    HStack(spacing: 4) {
                        ForEach(0..<pageCount, id: \.self) { idx in
                            Capsule()
                                .fill(Color.white.opacity(idx == pageIndex ? 1 : 0.35))
                                .frame(width: idx == pageIndex ? 10 : 4, height: 4)
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: pageIndex)
                }
            }
            .transition(.opacity)
        }
    }

    private func chevron(_ name: String, active: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white.opacity(active ? 1 : 0.55))
            .scaleEffect(active ? 1.2 : 1)
            .frame(width: 22)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func centerIconView(_ icon: RadialDialIcon) -> some View {
        switch icon {
        case .sfSymbol(let name), .system(let name):
            Image(systemName: name)
        case .app(let bundleID):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.fill")
            }
        }
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
