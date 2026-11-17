import AppKit
import Foundation

/// AppKit bridge inspecting macOS display topology, OLED capabilities, and macOS 27 hardware multi-touch.
@MainActor
enum ScreenTouchCapabilities {
    /// Returns true if the given `NSScreen` reports native hardware multi-touch capability on macOS 27+.
    static func hardwareSupportsMultiTouch(for screen: NSScreen) -> Bool {
        if #available(macOS 27.0, *) {
            if screen.touchCapabilities.contains(.multiTouch) {
                return true
            }
            return NSEvent.isTouchSwipeNavigationEnabled && isBuiltinDisplay(screen)
        }
        return false
    }

    static func isBuiltinDisplay(_ screen: NSScreen) -> Bool {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(CGDirectDisplayID(screenNumber.uint32Value)) != 0
    }

    static func isLikelyOLEDDisplay(_ screen: NSScreen) -> Bool {
        // Heuristic: built-in PROLED XDR / OLED displays report extended dynamic range > 1.0 with high EDR headroom
        // or are identified as builtin displays paired with hardware multi-touch on macOS 27+.
        guard isBuiltinDisplay(screen) else { return false }
        if hardwareSupportsMultiTouch(for: screen) { return true }
        return screen.maximumPotentialExtendedDynamicRangeColorComponentValue >= 2.0 && screen.safeAreaInsets.top > 0
    }

    /// Resolves the live `IslandDisplayTopology` for any `NSScreen` + current user/debug touch override.
    static func resolveTopology(for screen: NSScreen) -> IslandDisplayTopology {
        let frame = screen.frame
        let safeTop = Double(screen.safeAreaInsets.top)
        let menuBarHeight = max(24.0, Double(frame.maxY - screen.visibleFrame.maxY))
        let auxLeft = screen.auxiliaryTopLeftArea.map { Double($0.width) }
        let auxRight = screen.auxiliaryTopRightArea.map { Double($0.width) }

        return IslandDisplayTopology.resolve(
            screenWidth: Double(frame.width),
            screenHeight: Double(frame.height),
            safeAreaTop: safeTop,
            auxLeftWidth: auxLeft,
            auxRightWidth: auxRight,
            menuBarHeight: menuBarHeight,
            isBuiltinDisplay: isBuiltinDisplay(screen),
            isOLED: isLikelyOLEDDisplay(screen),
            supportsMultiTouch: hardwareSupportsMultiTouch(for: screen)
        )
    }

    static func isTouchModeActive(for screen: NSScreen, setting: IslandTouchModeSetting) -> Bool {
        let debugForce = DebugSwitch.touchIsland.isEnabled()
        let topology = resolveTopology(for: screen)
        return topology.isTouchOptimized(setting: setting, debugOverride: debugForce)
    }
}
