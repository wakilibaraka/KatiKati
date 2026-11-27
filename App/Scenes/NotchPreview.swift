import AppKit
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
    @AppStorage(IslandSurfaceGlassPolicy.liquidGlassEnabledKey) private var glassEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var size: CGSize { NotchGeometry.previewSize(for: skin, expanded: isExpanded) }
    private var hasPhysicalCutout: Bool { (NSScreen.main?.safeAreaInsets.top ?? 0) > 0 }
    private var usesLiquidGlass: Bool {
        skin.usesLiquidGlassBackdrop && IslandSurfaceGlassPolicy.shouldUseLiquidGlass(
            hasPhysicalCutout: hasPhysicalCutout,
            isOLED: false,
            presentation: isExpanded ? .expanded : .idle,
            glassEnabled: glassEnabled,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }
    private var dynamicIslandShape: AnyShape {
        let radii = isExpanded ? NotchDesignSpec.openCornerRadii : NotchDesignSpec.closedCornerRadii
        if hasPhysicalCutout {
            return AnyShape(NotchContinuousMaskShape(
                topCornerRadius: radii.topFlaring,
                bottomCornerRadius: radii.bottomSquircle,
                flaringTopEars: false
            ))
        }
        return AnyShape(NotchPreviewContinuousShape(radius: isExpanded ? 32 : 16))
    }

    private var skinTitle: String {
        switch skin {
        case .liquid: return String(localized: "Liquid")
        case .boring: return String(localized: "Full")
        case .classic: return String(localized: "Compact")
        case .dynamicIsland: return String(localized: "Dynamic Island")
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
            .accessibilityValue(Text(isExpanded ? "Expanded" : "Collapsed"))
            .accessibilityHint(Text("Click to expand or collapse the demo preview."))
            .help(Text("Click to expand or collapse the demo preview."))
            caption
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.84), value: isExpanded)
    }

    private var silhouette: some View {
        ZStack {
            if skin.usesLiquidGlassBackdrop {
                let shape = dynamicIslandShape
                if usesLiquidGlass {
                    shape.fill(.ultraThinMaterial)
                        .overlay(shape.fill(Color.black.opacity(0.34)))
                } else {
                    shape.fill(Color.black)
                }
                shape.stroke(Color.white.opacity(usesLiquidGlass ? 0.18 : 0.08), lineWidth: 1)
            } else if skin == .dynamicIsland || skin == .liquid {
                NotchPreviewContinuousShape(radius: isExpanded ? 32 : 16)
                    .fill(Color.black)
                    .overlay(
                        NotchPreviewContinuousShape(radius: isExpanded ? 32 : 16)
                            .stroke(Color.white.opacity(0.28), lineWidth: 1.5)
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
        Group {
            switch skin {
            case .boring, .dynamicIsland:
                VStack(spacing: 8) {
                    HStack {
                        previewLine(width: 56, opacity: 0.24)
                        Spacer()
                        previewLine(width: 28, opacity: 0.14)
                    }
                    HStack(spacing: 8) {
                        plate
                        plate
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 14)
            case .classic:
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 6) {
                        previewLine(width: 90, opacity: 0.24)
                        previewLine(width: 58, opacity: 0.13)
                    }
                    Spacer(minLength: 8)
                    previewLine(width: 24, opacity: 0.22)
                }
                .padding(.horizontal, 22)
            case .liquid:
                HStack(spacing: 10) {
                    plate
                    plate
                    Circle()
                        .fill(Color.accentColor.opacity(0.24))
                        .frame(width: 18, height: 18)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            case .dynamicIsland:
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 6) {
                        previewLine(width: 92, opacity: 0.24)
                        previewLine(width: 64, opacity: 0.13)
                    }
                    Spacer(minLength: 8)
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 2)
                        .frame(width: 18, height: 18)
                }
                .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var plate: some View {
        RoundedRectangle(cornerRadius: NotchLayoutSpec.cardRadius, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .overlay {
                RoundedRectangle(cornerRadius: NotchLayoutSpec.cardRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func previewLine(width: CGFloat, opacity: Double) -> some View {
        Capsule()
            .fill(Color.white.opacity(opacity))
            .frame(width: width, height: 5)
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
