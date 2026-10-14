import CoreGraphics
import Foundation

// Phase 33g — Non-Notched Display Fallback Plan
// Pure geometry, placement, and offset solver for external monitors and non-notched displays.
// Dual-compiled in app and test targets. Zero AppKit dependencies.

struct NotchFallbackPlan: Equatable, Sendable {
    // MARK: - Floating Dimensions (Non-Notched)
    static let floatingClosedSize = CGSize(width: 185, height: 28)
    static let floatingClosedCornerRadius: CGFloat = 14.0
    static let floatingOpenCornerRadius: CGFloat = 22.0
    static let floatingTopMargin: CGFloat = 8.0

    /// Detects whether the active display has a physical hardware notch cutout.
    static func isNotchedDisplay(safeAreaTop: CGFloat) -> Bool {
        safeAreaTop > 0
    }

    /// Computes the top Y-offset for positioning the floating island below the menu bar on external displays.
    static func floatingTopOffset(menuBarHeight: CGFloat) -> CGFloat {
        let bar = menuBarHeight > 0 ? menuBarHeight : 24.0
        return bar + floatingTopMargin
    }

    /// Solves the usable horizontal width for activity wings.
    /// Hardware notch: keepout zone occupies 160pt in the center.
    /// Non-notched floating island: keepout is 0pt, allowing symmetric content layout.
    static func usableWingWidth(closedWidth: CGFloat, hasHardwareNotch: Bool) -> CGFloat {
        if hasHardwareNotch {
            let keepout = min(NotchDesignSpec.cameraKeepoutWidth, closedWidth)
            return max(0, (closedWidth - keepout) / 2)
        } else {
            return closedWidth / 2
        }
    }

    /// Solves the target frame for the notch panel window on screen.
    static func panelFrame(
        metrics: NotchMetrics,
        screenBounds: CGRect,
        isOpen: Bool,
        menuBarHeight: CGFloat
    ) -> CGRect {
        let size = isOpen ? NotchDesignSpec.openSize(forScreenWidth: screenBounds.width) : metrics.closedSize
        let x = screenBounds.midX - (size.width / 2)

        if metrics.hasHardwareNotch {
            return CGRect(x: x, y: 0, width: size.width, height: size.height)
        } else {
            let topY = floatingTopOffset(menuBarHeight: menuBarHeight)
            return CGRect(x: x, y: topY, width: size.width, height: size.height)
        }
    }
}
