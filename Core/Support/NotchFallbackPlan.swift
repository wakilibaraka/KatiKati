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

// MARK: - Droppy-Inspired Slice A-Glass: NotchGlassStyle & NotchGlassPolicy

/// Glass style preferences for the Dynamic Island / Notch
enum NotchGlassStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case dynamicGlass
    case liquidClear
    case solidBlack

    var id: String { rawValue }
    static let defaultsKey = "com.katikati.notch.glassStyle"

    static func current(_ d: UserDefaults = .standard) -> NotchGlassStyle {
        NotchGlassStyle(rawValue: d.string(forKey: defaultsKey) ?? "") ?? .dynamicGlass
    }
}

/// Pure evaluation of glass material and plate styling based on user style, power mode, and hardware notch status.
enum NotchGlassPolicy {
    struct ResolvedGlass: Equatable, Sendable {
        let effectiveStyle: NotchGlassStyle
        let plateOpacity: Double
        let blurRadius: CGFloat
        let strokeOpacity: Double
        let isPowerSavingOpaque: Bool
    }

    /// Evaluates effective glass appearance. Low power mode forces solid black to save GPU rendering cost.
    /// Hardware notch display in closed state also stays solid black to blend with the bezel.
    static func resolve(
        style: NotchGlassStyle,
        isLowPowerMode: Bool,
        hasHardwareNotch: Bool,
        isOpen: Bool
    ) -> ResolvedGlass {
        if isLowPowerMode {
            return ResolvedGlass(
                effectiveStyle: .solidBlack,
                plateOpacity: 1.0,
                blurRadius: 0.0,
                strokeOpacity: 0.08,
                isPowerSavingOpaque: true
            )
        }

        if hasHardwareNotch && !isOpen {
            return ResolvedGlass(
                effectiveStyle: .solidBlack,
                plateOpacity: 1.0,
                blurRadius: 0.0,
                strokeOpacity: 0.0,
                isPowerSavingOpaque: false
            )
        }

        switch style {
        case .dynamicGlass:
            return ResolvedGlass(
                effectiveStyle: .dynamicGlass,
                plateOpacity: 0.82,
                blurRadius: 24.0,
                strokeOpacity: 0.16,
                isPowerSavingOpaque: false
            )
        case .liquidClear:
            return ResolvedGlass(
                effectiveStyle: .liquidClear,
                plateOpacity: 0.55,
                blurRadius: 36.0,
                strokeOpacity: 0.22,
                isPowerSavingOpaque: false
            )
        case .solidBlack:
            return ResolvedGlass(
                effectiveStyle: .solidBlack,
                plateOpacity: 1.0,
                blurRadius: 0.0,
                strokeOpacity: 0.10,
                isPowerSavingOpaque: false
            )
        }
    }
}
