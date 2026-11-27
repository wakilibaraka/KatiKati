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
    /// Hardware camera & sensor keepout area within the closed notch coordinates.
    var cameraKeepoutBox: CGRect

    init(closedSize: CGSize, hasHardwareNotch: Bool, cameraKeepoutBox: CGRect = .zero) {
        self.closedSize = closedSize
        self.hasHardwareNotch = hasHardwareNotch
        self.cameraKeepoutBox = cameraKeepoutBox
    }
}

enum NotchGeometry {
    /// Default closed width when the real width can't be derived (matches the common 14"/16" notch).
    static let fallbackNotchWidth: CGFloat = 185
    /// The fake notch's height when the menu-bar height is unknown.
    static let fallbackHeight: CGFloat = 24
    /// The open (expanded) notch size.
    static let openSize = NotchLayoutSpec.openSize
    /// The original single-row panel's open size (the `classic` skin).
    static let classicOpenSize = CGSize(width: 480, height: 142.5)

    static let dynamicIslandOpenSize = openSize
    static let dynamicIslandPreviewSize = openSize
    static let liquidOpenSize = CGSize(width: 440, height: 152)

    static func openSize(for skin: LiveIslandSkin) -> CGSize {
        switch skin {
        case .liquid: return liquidOpenSize
        case .boring: return openSize
        case .classic: return classicOpenSize
        case .dynamicIsland: return dynamicIslandOpenSize
        }
    }

    /// Silhouette the Settings/guide demo draws: the skin's open panel, or the closed capsule.
    static func previewSize(for skin: LiveIslandSkin, expanded: Bool) -> CGSize {
        guard expanded else {
            return CGSize(width: NotchDesignSpec.fallbackClosedWidth, height: NotchDesignSpec.fallbackClosedHeight)
        }
        switch skin {
        case .liquid: return liquidOpenSize
        case .boring: return openSize
        case .classic: return classicOpenSize
        case .dynamicIsland: return dynamicIslandPreviewSize
        }
    }
    /// Extra width the closed notch grows by on each side to show the live activity.
    static let sneakSide: CGFloat = 64

    /// - Parameters:
    ///   - screenWidth: `screen.frame.width`.
    ///   - safeAreaTop: `screen.safeAreaInsets.top` (> 0 on a notched display).
    ///   - auxLeftWidth / auxRightWidth: `auxiliaryTopLeftArea?.width` / `auxiliaryTopRightArea?.width`.
    ///   - menuBarHeight: `frame.maxY - visibleFrame.maxY`, used as the fake-notch height.
    static func metrics(screenWidth: CGFloat, safeAreaTop: CGFloat, auxLeftWidth: CGFloat?, auxRightWidth: CGFloat?, menuBarHeight: CGFloat) -> NotchMetrics {
        NotchDesignSpec.resolve(
            screenWidth: screenWidth,
            safeAreaTop: safeAreaTop,
            auxLeftWidth: auxLeftWidth,
            auxRightWidth: auxRightWidth,
            menuBarHeight: menuBarHeight
        )
    }

    /// Panel frame (AppKit bottom-left coordinates) for a notch of `size`, top-centred on `screenFrame`.
    static func panelFrame(size: CGSize, in screenFrame: CGRect) -> CGRect {
        CGRect(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
    }

    /// Width of the closed capsule including the activity "sneak" on both sides.
    static func closedCapsuleSize(_ metrics: NotchMetrics, showsActivity: Bool) -> CGSize {
        CGSize(width: metrics.closedSize.width + (showsActivity ? sneakSide * 2 : 0), height: metrics.closedSize.height)
    }

    /// Backing `NSPanel` size for any skin: full stage while expanded, compact (`<= 60 pt` tall) while closed
    /// so a `CAMetalLayer` or non-activating panel never sits over app toolbars below the menu bar.
    static func stageSize(
        for skin: LiveIslandSkin,
        isExpanded: Bool,
        isWide: Bool,
        metrics: NotchMetrics,
        closedSize: CGSize,
        openSize: CGSize,
        hasCompactActivity: Bool = true
    ) -> CGSize {
        switch skin {
        case .liquid:
            if isExpanded {
                return CGSize(width: max(600, openSize.width + 160), height: openSize.height + 80)
            }
            let baseWidth = metrics.hasHardwareNotch ? metrics.closedSize.width : 148
            let baseHeight = metrics.hasHardwareNotch ? metrics.closedSize.height : 28
            let width = isWide
                ? openSize.width
                : (hasCompactActivity ? max(closedSize.width, baseWidth + 140) : baseWidth + 12)
            let height = min(60, baseHeight + (hasCompactActivity ? 16 : 6))
            return CGSize(width: width, height: height)
        case .dynamicIsland:
            if isExpanded {
                return CGSize(width: max(560, openSize.width + 64), height: max(240, openSize.height + 50))
            }
            let width = isWide ? openSize.width : max(closedSize.width, 340)
            let height = min(60, max(44, metrics.closedSize.height + 16))
            return CGSize(width: width, height: height)
        case .boring, .classic:
            return isExpanded ? openSize : closedSize
        }
    }

    /// Backing `NSPanel` frame on `screenBounds` for the given skin and expansion state.
    static func stageFrame(
        for skin: LiveIslandSkin,
        isExpanded: Bool,
        isWide: Bool,
        metrics: NotchMetrics,
        closedSize: CGSize,
        openSize: CGSize,
        screenBounds: CGRect,
        topInset: CGFloat,
        menuBarHeight: CGFloat,
        hasCompactActivity: Bool = true
    ) -> CGRect {
        let size = NotchLayoutSpec.fit(stageSize(
            for: skin,
            isExpanded: isExpanded,
            isWide: isWide,
            metrics: metrics,
            closedSize: closedSize,
            openSize: openSize,
            hasCompactActivity: hasCompactActivity
        ), screenWidth: screenBounds.width, closedWidth: closedSize.width)
        var frame = panelFrame(size: size, in: screenBounds)
        if skin.usesIslandSurfaceEngine, !metrics.hasHardwareNotch, !isWide, menuBarHeight > 0 {
            frame.origin.y -= menuBarHeight
        }
        return frame
    }
}
