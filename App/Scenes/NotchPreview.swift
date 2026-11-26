import SwiftUI

/// Demo of the notch island for Settings and the setup guide: the real closed and open silhouettes at
/// the sizes the selected skin actually uses, growing and shrinking on a click.
///
/// Deliberately isolated — it reads no feed, media, timer or panel, and draws placeholder plates
/// instead of numbers, so the demo can never pass invented values off as live data
/// (Phase 34 witness: notch surfaces ship no mock literals).
struct NotchPreview: View {
    let skin: LiveIslandSkin
    let isEnabled: Bool
    @State private var isExpanded = true

    private var size: CGSize { NotchGeometry.previewSize(for: skin, expanded: isExpanded) }

    private var skinTitle: String {
        switch skin {
        case .liquid: return String(localized: "Liquid")
        case .boring: return String(localized: "Full")
        case .classic: return String(localized: "Compact")
        case .dynamicIsland: return String(localized: "Dynamic Island")
        case .superGlass: return String(localized: "Super Glass")
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Button { isExpanded.toggle() } label: {
                silhouette
                    // Fit, never upscale: the open panel is 640 pt wide — wider than the guide's
                    // 520 pt column — and the closed capsule is 185 pt. The height is stated
                    // explicitly because a `Shape` has no intrinsic size: with a flexible height
                    // `.fit` solves the ratio against whatever the surrounding form proposes.
                    .aspectRatio(size.width / size.height, contentMode: .fit)
                    .frame(height: size.height)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: skinTitle))
            .accessibilityHint(Text("Click to expand or collapse the demo preview."))
            .help(Text("Click to expand or collapse the demo preview."))
            caption
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: isExpanded)
    }

    private var silhouette: some View {
        ZStack {
            if skin == .dynamicIsland || skin == .liquid || skin == .superGlass {
                NotchPreviewContinuousShape(radius: isExpanded ? 32 : 16)
                    .fill(Color.black)
                    .overlay(
                        NotchPreviewContinuousShape(radius: isExpanded ? 32 : 16)
                            .stroke(Color.white.opacity(skin == .superGlass ? 0.28 : 0.16), lineWidth: 1.5)
                    )
            } else {
                // The floating-island rendering, which is what the app draws on a display without a
                // notch: in a settings row there is no bezel above the shape, so the hardware notch's
                // flared ears have nothing to meet and the silhouette reads as cut off.
                NotchContinuousMaskShape(
                    topCornerRadius: isExpanded ? NotchDesignSpec.openCornerRadii.topFlaring : NotchDesignSpec.closedCornerRadii.topFlaring,
                    bottomCornerRadius: isExpanded ? NotchDesignSpec.openCornerRadii.bottomSquircle : NotchDesignSpec.closedCornerRadii.bottomSquircle,
                    flaringTopEars: false
                )
                .fill(Color.black)
            }
            if isExpanded { placeholderPlates }
        }
        .opacity(isEnabled ? 1 : 0.45)
        .contentShape(Rectangle())
    }

    /// Neutral plates where content would be: the demo shows the silhouette, never invented data.
    private var placeholderPlates: some View {
        HStack(spacing: NotchLayoutSpec.cardPadding) {
            plate
            VStack(spacing: NotchLayoutSpec.cardPadding) {
                plate
                plate
            }
        }
        .padding(.horizontal, NotchDesignSpec.gridPadding.leading)
        .padding(.vertical, NotchDesignSpec.gridPadding.top + 6)
    }

    private var plate: some View {
        RoundedRectangle(cornerRadius: NotchLayoutSpec.cardRadius, style: .continuous)
            .fill(Color.white.opacity(NotchLayoutSpec.cardFillOpacity))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var caption: some View {
        HStack(spacing: 6) {
            Text("Preview")
            Text(verbatim: "·")
            Text(verbatim: skinTitle)
            if !isEnabled {
                Text(verbatim: "·")
                Text("Off")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct NotchPreviewContinuousShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(
            continuousRectCGPath(
                x: Double(rect.minX),
                y: Double(rect.minY),
                width: Double(rect.width),
                height: Double(rect.height),
                radius: Double(radius),
                smoothing: 0.72
            )
        )
    }
}
