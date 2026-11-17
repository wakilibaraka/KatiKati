import AppKit
import SwiftUI

private struct IslandTouchModeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var islandTouchMode: Bool {
        get { self[IslandTouchModeKey.self] }
        set { self[IslandTouchModeKey.self] = newValue }
    }
}

/// Touch-optimized circular control whose visual size stays crisp (`36...49 pt`) while always
/// guaranteeing an interactive `>= 44x44 pt` hit box when `touchMode == true`.
struct IslandRoundButton<Icon: View>: View {
    let visualSize: CGFloat
    var fill: Color = IslandTheme.Ink.fill
    var foreground: Color = IslandTheme.Ink.primary
    var accessibilityLabel: String
    let action: () -> Void
    @ViewBuilder var icon: () -> Icon

    @Environment(\.islandTouchMode) private var touchMode
    @State private var isPressed = false

    init(
        size: CGFloat = 44,
        fill: Color = IslandTheme.Ink.fill,
        foreground: Color = IslandTheme.Ink.primary,
        accessibilityLabel: String,
        action: @escaping () -> Void,
        @ViewBuilder icon: @escaping () -> Icon
    ) {
        self.visualSize = size
        self.fill = fill
        self.foreground = foreground
        self.accessibilityLabel = accessibilityLabel
        self.action = action
        self.icon = icon
    }

    var body: some View {
        let hitSide = touchMode ? max(visualSize, IslandTouchHitPolicy.minimumTouchTargetSize.width) : visualSize
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isPressed ? fill.opacity(1.35) : fill)
                    .frame(width: visualSize, height: visualSize)
                    .scaleEffect(isPressed ? 0.94 : 1.0)
                icon()
                    .foregroundStyle(foreground)
            }
            .frame(width: hitSide, height: hitSide)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
        .onLongPressGesture(minimumDuration: 0, maximumDistance: 24, pressing: { pressing in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

/// Touch-optimized pill control (used in bottom action rows and mode switchers).
struct IslandPillButton<LabelContent: View>: View {
    var fill: Color = IslandTheme.Ink.fill
    var foreground: Color = IslandTheme.Ink.primary
    var minHeight: CGFloat = 44
    var horizontalPadding: CGFloat = 14
    var accessibilityLabel: String
    let action: () -> Void
    @ViewBuilder var label: () -> LabelContent

    @Environment(\.islandTouchMode) private var touchMode
    @State private var isPressed = false

    var body: some View {
        let targetHeight = touchMode ? max(minHeight, IslandTouchHitPolicy.minimumTouchTargetSize.height) : minHeight
        Button(action: action) {
            label()
                .foregroundStyle(foreground)
                .padding(.horizontal, horizontalPadding)
                .frame(minWidth: touchMode ? 44 : nil, minHeight: minHeight)
                .background(
                    Capsule()
                        .fill(isPressed ? fill.opacity(1.35) : fill)
                )
                .frame(minHeight: targetHeight)
                .contentShape(Rectangle())
                .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
        .onLongPressGesture(minimumDuration: 0, maximumDistance: 24, pressing: { pressing in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

/// 52x52 continuous-corner tile used on expanded leading slots.
struct IslandTileArtwork: View {
    var image: NSImage? = nil
    var systemImage: String? = nil
    var accent: Color = IslandTheme.Accent.blue
    var size: CGFloat = IslandTheme.Size.expandedTile
    var radius: CGFloat = IslandTheme.Size.expandedTileRadius

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(accent.opacity(0.22))
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: size * 0.44, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(IslandContinuousRectShape(radius: radius, smoothing: 0.72))
    }
}

struct IslandTitleStack: View {
    let title: String
    var subtitle: String? = nil
    var subtitleColor: Color = IslandTheme.Ink.secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: title)
                .font(.system(size: IslandTheme.Size.title, weight: .semibold))
                .foregroundStyle(IslandTheme.Ink.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            if let subtitle, !subtitle.isEmpty {
                Text(verbatim: subtitle)
                    .font(.system(size: IslandTheme.Size.subtitle, weight: .regular))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct IslandExpandedValueStack: View {
    let value: String
    var caption: String? = nil
    var accent: Color = IslandTheme.Ink.primary

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            IslandNumberText(
                value: value,
                fontSize: IslandTheme.Size.expandedValue,
                weight: .bold,
                color: accent
            )
            if let caption, !caption.isEmpty {
                Text(verbatim: caption)
                    .font(.system(size: IslandTheme.Size.caption, weight: .medium))
                    .foregroundStyle(IslandTheme.Ink.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Container holding rendered views for every island presentation slot of an activity.
@MainActor
struct IslandActivityViews {
    var measure: IslandContentMeasure
    var compactLeading: AnyView
    var compactTrailing: AnyView
    var minimal: AnyView
    var expandedLeading: AnyView
    var expandedCenter: AnyView
    var expandedTrailing: AnyView
    var expandedBottom: AnyView?
}

@MainActor
final class IslandPresetRegistry: ObservableObject {
    @Published private(set) var revision: Int = 0
    private var entries: [String: IslandActivityViews] = [:]

    func register(id: String, views: IslandActivityViews) {
        entries[id] = views
        revision &+= 1
    }

    func unregister(id: String) {
        if entries.removeValue(forKey: id) != nil {
            revision &+= 1
        }
    }

    func clear() {
        if !entries.isEmpty {
            entries.removeAll()
            revision &+= 1
        }
    }

    func views(for activity: IslandActivityRecord) -> IslandActivityViews {
        if let custom = entries[activity.id] {
            return custom
        }
        let accent = IslandTheme.Accent.lagoon
        let title = activity.label
        return IslandActivityViews(
            measure: IslandContentMeasure(
                leading: 22,
                trailing: 28,
                attached: 22,
                detached: 22,
                split: IslandSplitMeasure(
                    attached: IslandSlotPair(leading: 20, trailing: 22),
                    detached: IslandSlotPair(leading: 20, trailing: 0)
                ),
                expandedHeight: 74
            ),
            compactLeading: AnyView(
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            ),
            compactTrailing: AnyView(
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
            ),
            minimal: AnyView(
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            ),
            expandedLeading: AnyView(
                IslandTileArtwork(systemImage: "sparkles", accent: accent)
            ),
            expandedCenter: AnyView(
                IslandTitleStack(title: title, subtitle: "KatiKati")
            ),
            expandedTrailing: AnyView(
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(IslandTheme.Ink.secondary)
            ),
            expandedBottom: nil
        )
    }
}
