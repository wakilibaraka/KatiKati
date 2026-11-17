import CoreGraphics
import Foundation

public enum IslandHardwareCutout: Equatable, Sendable {
    case none
    case classicNotch(width: Double, height: Double, cameraKeepoutWidth: Double)
    case oledDynamicIsland(cutoutWidth: Double, cutoutHeight: Double, topMargin: Double, cameraKeepoutWidth: Double)

    public var isPhysicalCutout: Bool {
        switch self {
        case .none: return false
        case .classicNotch, .oledDynamicIsland: return true
        }
    }

    public var keepoutWidth: Double {
        switch self {
        case .none: return 0
        case let .classicNotch(_, _, cameraKeepoutWidth): return cameraKeepoutWidth
        case let .oledDynamicIsland(_, _, _, cameraKeepoutWidth): return cameraKeepoutWidth
        }
    }
}

public enum IslandNonNotchIdleBehavior: String, CaseIterable, Codable, Hashable, Sendable {
    /// Floating black pill centered below the menu bar at rest.
    case compactPill
    /// Hides when zero activities are active, appearing only on live events or top-edge hover/touch.
    case autoHideAtRest
    /// Expands to KatiKati's wide utility strip at rest on non-notch displays.
    case wideBarAtRest
}

public enum IslandTouchModeSetting: String, CaseIterable, Codable, Hashable, Sendable {
    /// Uses macOS 27 `NSScreen.touchCapabilities` (`.multiTouch`) and `DOCK_TOUCH_ISLAND`.
    case automatic
    /// Forces `>= 44x44 pt` touch ergonomics, pull-down gestures, and hover-free taps even without touch hardware.
    case alwaysOn
    /// Uses compact pointer-only hit boxes even on touch displays.
    case off
}

/// Unified hardware + UI topology resolved for a screen.
public struct IslandDisplayTopology: Equatable, Sendable {
    public let cutout: IslandHardwareCutout
    public let isOLED: Bool
    public let supportsMultiTouch: Bool
    public let isBuiltinDisplay: Bool
    public let screenWidth: Double
    public let screenHeight: Double
    public let menuBarHeight: Double
    public let safeAreaTop: Double

    public init(
        cutout: IslandHardwareCutout,
        isOLED: Bool,
        supportsMultiTouch: Bool,
        isBuiltinDisplay: Bool,
        screenWidth: Double,
        screenHeight: Double,
        menuBarHeight: Double,
        safeAreaTop: Double
    ) {
        self.cutout = cutout
        self.isOLED = isOLED
        self.supportsMultiTouch = supportsMultiTouch
        self.isBuiltinDisplay = isBuiltinDisplay
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.menuBarHeight = menuBarHeight
        self.safeAreaTop = safeAreaTop
    }

    /// Resolves topology from raw Cocoa/CG metrics so tests can deterministically simulate
    /// M1–M4 Notched Macs, M5 OLED Dynamic Island Touch Macs, and Non-Notch External monitors.
    public static func resolve(
        screenWidth: Double,
        screenHeight: Double,
        safeAreaTop: Double,
        auxLeftWidth: Double?,
        auxRightWidth: Double?,
        menuBarHeight: Double,
        isBuiltinDisplay: Bool,
        isOLED: Bool,
        supportsMultiTouch: Bool
    ) -> IslandDisplayTopology {
        let notchDesign = NotchDesignSpec.resolve(
            screenWidth: CGFloat(screenWidth),
            safeAreaTop: CGFloat(safeAreaTop),
            auxLeftWidth: auxLeftWidth.map { CGFloat($0) },
            auxRightWidth: auxRightWidth.map { CGFloat($0) },
            menuBarHeight: CGFloat(menuBarHeight)
        )

        let cutout: IslandHardwareCutout
        if safeAreaTop > 0 {
            let inferredWidth = max(120.0, Double(notchDesign.closedSize.width))
            let inferredHeight = max(24.0, Double(notchDesign.closedSize.height))
            if isBuiltinDisplay && isOLED && inferredWidth <= 170.0 && safeAreaTop >= 36.0 {
                // Hardware Dynamic Island OLED panel (recessed top margin inside bezel).
                cutout = .oledDynamicIsland(
                    cutoutWidth: inferredWidth,
                    cutoutHeight: min(inferredHeight, 37.0),
                    topMargin: max(6.0, (safeAreaTop - min(inferredHeight, 37.0)) / 2.0),
                    cameraKeepoutWidth: max(96.0, Double(notchDesign.cameraKeepoutBox.width))
                )
            } else {
                // Classic M1–M4 top-bezel flush notch cutout.
                cutout = .classicNotch(
                    width: inferredWidth,
                    height: inferredHeight,
                    cameraKeepoutWidth: Double(notchDesign.cameraKeepoutBox.width)
                )
            }
        } else {
            cutout = .none
        }

        return IslandDisplayTopology(
            cutout: cutout,
            isOLED: isOLED,
            supportsMultiTouch: supportsMultiTouch,
            isBuiltinDisplay: isBuiltinDisplay,
            screenWidth: screenWidth,
            screenHeight: screenHeight,
            menuBarHeight: menuBarHeight,
            safeAreaTop: safeAreaTop
        )
    }

    public func isTouchOptimized(setting: IslandTouchModeSetting, debugOverride: Bool = false) -> Bool {
        if debugOverride { return true }
        switch setting {
        case .automatic: return supportsMultiTouch
        case .alwaysOn: return true
        case .off: return false
        }
    }

    public func keylineSetting(userEnabled: Bool) -> IslandKeylineSetting {
        guard userEnabled else { return .off }
        return (isOLED || cutout.isPhysicalCutout) ? .auto : .on
    }

    public func adaptsAsFloatingBelowMenuBar(nonNotchBehavior: IslandNonNotchIdleBehavior) -> Bool {
        cutout == .none && nonNotchBehavior != .autoHideAtRest
    }

    public func hidesAtRest(activeCount: Int, nonNotchBehavior: IslandNonNotchIdleBehavior) -> Bool {
        cutout == .none && nonNotchBehavior == .autoHideAtRest && activeCount == 0
    }

    /// Computes live `IslandMetrics` calibrated for this display topology and touch ergonomics.
    public func islandMetrics(
        nonNotchBehavior: IslandNonNotchIdleBehavior = .compactPill,
        touchEnabled: Bool = false
    ) -> IslandMetrics {
        let touchLift = touchEnabled ? 2.0 : 0.0
        switch cutout {
        case let .classicNotch(width, height, _):
            let capsuleHeight = max(height, touchEnabled ? 40.0 : 34.0)
            var metrics = IslandMetrics.macAdapted(
                topOffset: 0.0,
                cutoutWidth: width,
                capsuleHeight: capsuleHeight,
                maxCompactWidth: max(width + 180.0, 380.0),
                expandedWidth: 480.0,
                expandedMinHeight: 112.0 + touchLift * 2.0,
                expandedMaxHeight: 194.0
            )
            metrics.expanded.top = 0.0
            metrics.expanded.radius = 28.0
            metrics.contentClip.radius = 22.0
            return metrics

        case let .oledDynamicIsland(cutoutWidth, cutoutHeight, topMargin, _):
            let capsuleHeight = max(cutoutHeight, touchEnabled ? 40.0 : 36.85)
            var metrics = IslandMetrics.macAdapted(
                topOffset: topMargin,
                cutoutWidth: cutoutWidth,
                capsuleHeight: capsuleHeight,
                maxCompactWidth: 360.0,
                expandedWidth: 460.0,
                expandedMinHeight: 104.0 + touchLift * 2.0,
                expandedMaxHeight: 188.0
            )
            metrics.keyline.alpha = 0.16
            return metrics

        case .none:
            let idleWidth: Double = nonNotchBehavior == .wideBarAtRest ? 236.0 : 168.0
            let capsuleHeight = touchEnabled ? 40.0 : 34.0
            let floatingTop = 8.0
            var metrics = IslandMetrics.macAdapted(
                topOffset: floatingTop,
                cutoutWidth: idleWidth,
                capsuleHeight: capsuleHeight,
                maxCompactWidth: 340.0,
                expandedWidth: 452.0,
                expandedMinHeight: 102.0 + touchLift * 2.0,
                expandedMaxHeight: 186.0
            )
            metrics.expanded.top = floatingTop
            metrics.expanded.radius = 36.0
            metrics.contentClip.radius = 28.0
            return metrics
        }
    }

    /// Top-down keepout box relative to the island host stage (`0,0` top-left of `stageWidth`).
    public func cameraKeepoutRect(stageWidth: Double, metrics: IslandMetrics) -> CGRect? {
        let keepoutWidth = cutout.keepoutWidth
        guard keepoutWidth > 0 else { return nil }
        let height = metrics.idle.height
        return CGRect(
            x: (stageWidth - keepoutWidth) / 2.0,
            y: metrics.top,
            width: keepoutWidth,
            height: height
        )
    }
}

/// Touch ergonomic policies (HIG `>= 44x44 pt` targets, rubber-band drag curve, velocity handoff).
public enum IslandTouchHitPolicy {
    public static let minimumTouchTargetSize = CGSize(width: 44.0, height: 44.0)

    /// Expands a visual control frame to at least `44x44 pt` centered on its midpoint when `touchEnabled == true`.
    public static func interactiveHitRect(
        for frame: CGRect,
        within bounds: CGRect? = nil,
        touchEnabled: Bool
    ) -> CGRect {
        guard touchEnabled else { return frame }
        let targetWidth = max(frame.width, minimumTouchTargetSize.width)
        let targetHeight = max(frame.height, minimumTouchTargetSize.height)
        var expanded = CGRect(
            x: frame.midX - targetWidth / 2.0,
            y: frame.midY - targetHeight / 2.0,
            width: targetWidth,
            height: targetHeight
        )
        if let bounds {
            expanded = expanded.intersection(bounds)
        }
        return expanded
    }

    /// Classic Apple rubber-band transfer function `(1 - 1 / ((|x| * c / d) + 1)) * d`.
    public static func rubberBandedOffset(
        _ translation: Double,
        dimension: Double = 64.0,
        coefficient: Double = 0.55
    ) -> Double {
        guard dimension > 0, coefficient > 0 else { return 0 }
        let sign = translation >= 0 ? 1.0 : -1.0
        let absDelta = abs(translation)
        let clamped = (1.0 - (1.0 / ((absDelta * coefficient / dimension) + 1.0))) * dimension
        return clamped * sign
    }

    /// Determines whether a vertical pan/drag should commit an expand (`+offset/+velocity`) or collapse (`-offset/-velocity`).
    public static func shouldCommitPull(
        translationY: Double,
        velocityY: Double,
        isExpanded: Bool,
        touchEnabled: Bool
    ) -> Bool {
        let distanceThreshold = touchEnabled ? 20.0 : 24.0
        let velocityThreshold = 240.0
        if !isExpanded {
            return translationY >= distanceThreshold || (translationY >= 8.0 && velocityY >= velocityThreshold)
        } else {
            return translationY <= -distanceThreshold || (translationY <= -8.0 && velocityY <= -velocityThreshold)
        }
    }
}
