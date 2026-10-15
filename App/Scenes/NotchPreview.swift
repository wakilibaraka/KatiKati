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
            .accessibilityLabel(Text(skin == .boring ? "Full" : "Compact"))
            .accessibilityHint(Text("Click to expand or collapse the demo preview."))
            .help(Text("Click to expand or collapse the demo preview."))
            caption
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: isExpanded)
    }

    private var silhouette: some View {
        ZStack {
            // The floating-island rendering, which is what the app draws on a display without a
            // notch: in a settings row there is no bezel above the shape, so the hardware notch's
            // flared ears have nothing to meet and the silhouette reads as cut off.
            NotchContinuousMaskShape(
                topCornerRadius: isExpanded ? NotchDesignSpec.openCornerRadii.topFlaring : NotchDesignSpec.closedCornerRadii.topFlaring,
                bottomCornerRadius: isExpanded ? NotchDesignSpec.openCornerRadii.bottomSquircle : NotchDesignSpec.closedCornerRadii.bottomSquircle,
                flaringTopEars: false
            )
            .fill(Color.black)
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
            Text(skin == .boring ? "Full" : "Compact")
            if !isEnabled {
                Text(verbatim: "·")
                Text("Off")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
