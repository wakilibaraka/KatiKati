import SwiftUI

/// The central navigation and pager hub for the radial dial (Phase 31b).
struct RadialDialCenterHub: View {
    let title: String
    let pageCount: Int
    let pageIndex: Int
    let centerItem: RadialDialItem?
    let isHovered: Bool
    let theme: RadialDialTheme
    let onPreviousPage: () -> Void
    let onNextPage: () -> Void
    let onCenterAction: () -> Void

    @State private var leftChevronHovered = false
    @State private var rightChevronHovered = false

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(hubBackground)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(isHovered ? 0.35 : 0.18), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 3)

            // Content
            if let centerItem, isHovered {
                VStack(spacing: 4) {
                    centerIconView(centerItem.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    Text(verbatim: centerItem.title)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                VStack(spacing: 5) {
                    // Pager row: < title >
                    HStack(spacing: 6) {
                        Button(action: onPreviousPage) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(leftChevronHovered ? 1.0 : 0.6))
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .onHover { leftChevronHovered = $0 }

                        Text(verbatim: title)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .frame(minWidth: 42)

                        Button(action: onNextPage) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(rightChevronHovered ? 1.0 : 0.6))
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .onHover { rightChevronHovered = $0 }
                    }

                    // Dot indicators
                    if pageCount > 1 {
                        HStack(spacing: 4) {
                            ForEach(0..<pageCount, id: \.self) { idx in
                                Circle()
                                    .fill(idx == pageIndex ? Color.white : Color.white.opacity(0.35))
                                    .frame(width: 4, height: 4)
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(width: 96, height: 96)
        .contentShape(Circle())
        .onTapGesture {
            if isHovered && centerItem != nil {
                onCenterAction()
            }
        }
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
        switch theme {
        case .lilacGlass:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.48, green: 0.42, blue: 0.78).opacity(isHovered ? 0.95 : 0.82),
                        Color(red: 0.36, green: 0.30, blue: 0.65).opacity(isHovered ? 0.95 : 0.82)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case .darkObsidian:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.18, green: 0.18, blue: 0.22).opacity(isHovered ? 0.98 : 0.90),
                        Color(red: 0.10, green: 0.10, blue: 0.13).opacity(isHovered ? 0.98 : 0.90)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case .systemFrosted:
            return AnyShapeStyle(
                Color.accentColor.opacity(isHovered ? 0.85 : 0.65)
            )
        case .neonCyber:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.12, blue: 0.22).opacity(isHovered ? 0.98 : 0.90),
                        Color(red: 0.04, green: 0.06, blue: 0.14).opacity(isHovered ? 0.98 : 0.90)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}
