import CoreGraphics
import Foundation

// Phase 8b-7 — pure geometry for the notch surface (KatiKati's adapter around the vendored boring.notch
// window and shape; see Vendor/boring.notch).
//
// boring.notch derives the closed-notch size from `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` /
// `safeAreaInsets.top` and falls back to a fixed size on Macs without a notch. This is that rule as a
// pure function (no NSScreen), so a real notch, a notch-less display (fake notch) and odd inputs are
// unit-tested. Dual-compiled.

struct NotchMetrics: Equatable {
    /// Size of the closed notch capsule (the black area flush with the top edge).
    var closedSize: CGSize
    /// `true` when the screen has real notch hardware; `false` means the notch is drawn as a fake pill.
    var hasHardwareNotch: Bool
}

enum NotchGeometry {
    /// Default closed width when the real width can't be derived (matches the common 14"/16" notch).
    static let fallbackNotchWidth: CGFloat = 185
    /// The fake notch's height when the menu-bar height is unknown.
    static let fallbackHeight: CGFloat = 24
    /// The open (expanded) notch size.
    static let openSize = CGSize(width: 420, height: 130)
    /// Extra width the closed notch grows by on each side to show the live activity.
    static let sneakSide: CGFloat = 64

    /// - Parameters:
    ///   - screenWidth: `screen.frame.width`.
    ///   - safeAreaTop: `screen.safeAreaInsets.top` (> 0 on a notched display).
    ///   - auxLeftWidth / auxRightWidth: `auxiliaryTopLeftArea?.width` / `auxiliaryTopRightArea?.width`.
    ///   - menuBarHeight: `frame.maxY - visibleFrame.maxY`, used as the fake-notch height.
    static func metrics(screenWidth: CGFloat, safeAreaTop: CGFloat, auxLeftWidth: CGFloat?, auxRightWidth: CGFloat?, menuBarHeight: CGFloat) -> NotchMetrics {
        var width = fallbackNotchWidth
        if let l = auxLeftWidth, let r = auxRightWidth, l >= 0, r >= 0, screenWidth - l - r > 0 {
            width = screenWidth - l - r + 4
        }
        let hasNotch = safeAreaTop > 0
        let height: CGFloat
        if hasNotch {
            height = safeAreaTop
        } else {
            height = menuBarHeight > 0 ? menuBarHeight : fallbackHeight
        }
        return NotchMetrics(closedSize: CGSize(width: width, height: height), hasHardwareNotch: hasNotch)
    }

    /// Panel frame (AppKit bottom-left coordinates) for a notch of `size`, top-centred on `screenFrame`.
    static func panelFrame(size: CGSize, in screenFrame: CGRect) -> CGRect {
        CGRect(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
    }

    /// Width of the closed capsule including the activity "sneak" on both sides.
    static func closedCapsuleSize(_ metrics: NotchMetrics, showsActivity: Bool) -> CGSize {
        CGSize(width: metrics.closedSize.width + (showsActivity ? sneakSide * 2 : 0), height: metrics.closedSize.height)
    }
}
