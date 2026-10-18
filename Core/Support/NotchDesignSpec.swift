import CoreGraphics
import Foundation

// Phase 33a — NotchDesignSpec: Formalized pure geometry, dimensions, camera keepout, and card tokens
// for the Dynamic Island Notch. Dual-compiled in app and test targets. No AppKit/UIKit dependencies.

struct NotchDesignSpec: Equatable, Sendable {
    // MARK: - Closed Notch Dimensions
    static let fallbackClosedWidth: CGFloat = 185
    static let fallbackClosedHeight: CGFloat = 32
    static let fallbackHeight: CGFloat = 24
    static let fallbackMenuBarHeight: CGFloat = 24

    // Camera & Sensor Hardware Keepout Zone (Centered horizontally flush with top)
    static let cameraKeepoutWidth: CGFloat = 160
    static let cameraKeepoutHeight: CGFloat = 32

    // MARK: - Closed Flanking Wings (Left & Right of Camera Keepout)
    static let wingWidthRange: ClosedRange<CGFloat> = 48...88
    static let wingHorizontalPadding: CGFloat = 12
    static let wingIconSize: CGFloat = 14
    static let wingTextSize: CGFloat = 12
    static let wingContentHeight: CGFloat = 26

    // MARK: - Open Bento Dimensions
    static let openSizeStandard = CGSize(width: 660, height: 216)
    static let openSizeCompact = CGSize(width: 520, height: 160)

    // Curvature continuous radii (squircle flaring top ears & bottom squircle)
    static let closedCornerRadii = (topFlaring: CGFloat(8), bottomSquircle: CGFloat(14))
    static let openCornerRadii = (topFlaring: CGFloat(22), bottomSquircle: CGFloat(26))

    // MARK: - Bento Grid Tokens
    static let gridPadding = (top: CGFloat(8), leading: CGFloat(16), bottom: CGFloat(16), trailing: CGFloat(16))
    static let cardSpacing: CGFloat = 12
    static let cardPadding: CGFloat = 14
    static let cardCornerRadius: CGFloat = 18
    static let cardStrokeWidth: CGFloat = 1.0
    static let cardStrokeOpacity: Double = 0.08
    // 0.10, not 0.06: the paler fill kept white card text unreadable over a busy window behind
    // the glass (live-checked 2026-10-17 — OCR read the background through the cards). Unpinned
    // by tests; the plate itself stays solid (`NotchDesignSpecTests` pins plate alpha >= 0.94).
    static let cardFillOpacity: Double = 0.10

    // MARK: - Resolver
    static func resolve(
        screenWidth: CGFloat,
        safeAreaTop: CGFloat,
        auxLeftWidth: CGFloat?,
        auxRightWidth: CGFloat?,
        menuBarHeight: CGFloat
    ) -> NotchMetrics {
        let hasHardware = safeAreaTop > 0
        let closedWidth: CGFloat
        if let l = auxLeftWidth, let r = auxRightWidth, l >= 0, r >= 0, screenWidth - l - r > 0 {
            closedWidth = screenWidth - l - r + 4
        } else {
            closedWidth = fallbackClosedWidth
        }

        let closedHeight: CGFloat
        if hasHardware {
            closedHeight = safeAreaTop
        } else {
            closedHeight = menuBarHeight > 0 ? menuBarHeight : fallbackHeight
        }

        let keepoutOriginX = max(0, (closedWidth - cameraKeepoutWidth) / 2)
        let keepoutBox = hasHardware
            ? CGRect(x: keepoutOriginX, y: 0, width: min(cameraKeepoutWidth, closedWidth), height: closedHeight)
            : .zero

        return NotchMetrics(
            closedSize: CGSize(width: closedWidth, height: closedHeight),
            hasHardwareNotch: hasHardware,
            cameraKeepoutBox: keepoutBox
        )
    }

    /// Clamp a requested wing width within the ergonomic safe range
    static func clampWingWidth(_ requested: CGFloat) -> CGFloat {
        min(max(requested, wingWidthRange.lowerBound), wingWidthRange.upperBound)
    }

    /// Calculate open panel size fitted to screen width with minimum margins
    static func openPanelSize(screenWidth: CGFloat, closedWidth: CGFloat, isCompact: Bool = false) -> CGSize {
        let base = isCompact ? openSizeCompact : openSizeStandard
        let width = min(base.width, max(closedWidth, screenWidth - 24))
        return CGSize(width: width, height: base.height)
    }

    /// Convenience openSize for screen width
    static func openSize(forScreenWidth screenWidth: CGFloat) -> CGSize {
        openPanelSize(screenWidth: screenWidth, closedWidth: fallbackClosedWidth)
    }
}

/// Phase 12 — the notch's plate colour and the scheme its content is drawn in.
///
/// Owner decision (2026-10-15): the notch tints **only as a floating island**. A hardware notch keeps
/// a black plate, because the shape has to meet the bezel and any tint there draws a seam against the
/// screen it is cut into. `auto` / `system` tint nothing at all (`tintsPlate`), so the default look
/// is the black plate the island has always drawn.
///
/// Next to `NotchDesignSpec` and dual-compiled for its reason: the invariant below is a test, not a
/// comment. The views half (`Color`, `ColorScheme`) stays in `NotchIslandView`.
enum NotchTheme {
    struct Resolution: Equatable {
        let plate: DockRGBA
        /// `true` = dark content (a pale plate); `false` = light content, which is what every notch
        /// surface is drawn for today.
        let prefersDarkContent: Bool
    }

    static let blackPlate = DockRGBA(r: 0, g: 0, b: 0, a: 1)

    /// **Invariant:** a hardware notch is always black with light content.
    static func resolve(
        hasHardwareNotch: Bool,
        tintsPlate: Bool,
        tokens: DockThemeStyleTokens
    ) -> Resolution {
        guard !hasHardwareNotch, tintsPlate else {
            return Resolution(plate: blackPlate, prefersDarkContent: false)
        }
        // A floating island carries the preset's tint, near-opaque so the silhouette still reads as a
        // solid shape over the desktop.
        return Resolution(
            plate: DockRGBA(r: tokens.baseTint.r, g: tokens.baseTint.g, b: tokens.baseTint.b,
                            a: max(tokens.baseTint.a, 0.94)),
            prefersDarkContent: tokens.prefersDarkContent
        )
    }
}
