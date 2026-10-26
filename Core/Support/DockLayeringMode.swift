import AppKit
import Foundation

/// Defines how the custom dock interacts with standard macOS application windows.
/// Combines Zero-Permission fallbacks with With-Permission window clamping and legacy presets.
public enum DockLayeringMode: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Mode 0 (Legacy Preset): App windows stay under the dock (`kCGDockWindowLevel` = 20) unless in fullscreen or user autohide.
    case alwaysOnTop = "alwaysOnTop"

    /// Mode A (Zero Permissions): Dock stays above windows (`kCGDockWindowLevel` = 20) UNTIL an active window
    /// overlaps the dock's frame, at which point the dock drops below the window (`kCGNormalWindowLevel - 1` = -1).
    case dynamicSmartZOrder = "dynamicSmartZOrder"

    /// Mode B (Zero Permissions): Keeps Dock on `.normal` (Level 0) and calls `order(.below, relativeTo:)`
    /// or `CGSOrderWindow` relative to the frontmost window ID so only the active window covers the dock.
    case sameLevelRelativeOrder = "sameLevelRelativeOrder"

    /// Mode C (Zero Permissions): App windows ALWAYS render on top of the dock (`kCGNormalWindowLevel - 1` = -1).
    /// Moving the cursor to the bottom screen edge temporarily elevates the dock above windows.
    case alwaysBelowWindowsWithEdgePeek = "alwaysBelowWindowsWithEdgePeek"

    /// Mode D (Zero Permissions): Native Dock "Intellihide" — Dock sits at `kCGDockWindowLevel` and
    /// smoothly slides off-screen when a window intersects the dock area, reappearing on bottom-edge hover.
    case nativeAutoHideDodge = "nativeAutoHideDodge"

    /// Mode E (Zero Permissions): Click-Through Ghost Fallback (`ignoresMouseEvents = true`).
    /// When overlapped, the dock becomes click-through and semi-transparent so clicks reach the window beneath.
    case clickThroughGhostFallback = "clickThroughGhostFallback"

    /// Mode F (Zero Permissions): Native Dock `visibleFrame` Piggyback.
    /// Keeps Apple's Dock unhidden at matching height and overlays custom dock at Level 21 (`kCGDockWindowLevel + 1`),
    /// forcing macOS WindowServer to natively subtract the dock height from `NSScreen.visibleFrame`.
    case nativeDockVisibleFramePiggyback = "nativeDockVisibleFramePiggyback"

    /// Mode G (With Permissions): Reserves bottom screen area by clamping standard windows via `AXUIElement`
    /// (with AppleScript `System Events` fallback). Automatically cascades to `.dynamicSmartZOrder` if permissions are absent.
    case reserveScreenSpaceStrut = "reserveScreenSpaceStrut"

    public var id: String { rawValue }

    /// Localized title key for display.
    public var title: String {
        switch self {
        case .alwaysOnTop:
            return String(localized: "Always On Top (Standard)")
        case .dynamicSmartZOrder:
            return String(localized: "Dynamic Smart Z-Order (Intellilevel)")
        case .sameLevelRelativeOrder:
            return String(localized: "Same-Level Relative Ordering (orderBelow)")
        case .alwaysBelowWindowsWithEdgePeek:
            return String(localized: "Always Below Windows (Edge Peek)")
        case .nativeAutoHideDodge:
            return String(localized: "Native Auto-Hide (Dodge Windows)")
        case .clickThroughGhostFallback:
            return String(localized: "Click-Through Ghost Fallback (Zero-Perm)")
        case .nativeDockVisibleFramePiggyback:
            return String(localized: "Native Dock visibleFrame Piggyback (Zero-Perm Strut)")
        case .reserveScreenSpaceStrut:
            return String(localized: "Reserve Screen Space (AX Strut Clamp)")
        }
    }

    /// Descriptive summary explaining how the mode behaves.
    public var subtitle: String {
        switch self {
        case .alwaysOnTop:
            return String(localized: "Dock floats above normal application windows at all times.")
        case .dynamicSmartZOrder:
            return String(localized: "Floats at native level when clear, drops below windows when overlapped, and peeks on edge hover.")
        case .sameLevelRelativeOrder:
            return String(localized: "Renders at normal window level, ordering directly below the frontmost active window.")
        case .alwaysBelowWindowsWithEdgePeek:
            return String(localized: "Windows always render on top of the dock; resting the pointer at the bottom edge brings it to the front.")
        case .nativeAutoHideDodge:
            return String(localized: "Smoothly slides offscreen when an active window enters the dock zone, sliding back on hover.")
        case .clickThroughGhostFallback:
            return String(localized: "Becomes click-through and subtle when covered so you can interact with the window underneath.")
        case .nativeDockVisibleFramePiggyback:
            return String(localized: "Sits above Apple's Dock to natively reserve window working area with zero permissions.")
        case .reserveScreenSpaceStrut:
            return String(localized: "Clamps overlapping windows above the dock. Gracefully falls back to dynamic Z-order if permissions are missing.")
        }
    }

    /// Whether this mode requires macOS Accessibility (TCC) permissions.
    public var requiresAccessibility: Bool {
        self == .reserveScreenSpaceStrut
    }

    /// Whether this mode works 100% out of the box without any permissions or TCC prompts.
    public var isZeroPermission: Bool {
        !requiresAccessibility
    }
}

// MARK: - Exact CoreGraphics Window Levels

/// CoreGraphics window levels from `CGWindowLevel.h`
/// Reference: https://gist.github.com/rismay/ab10e87dc10a76c25986d52c65441bf2
public enum MacDockWindowLevel {
    /// Sits above desktop wallpaper & desktop icons, but strictly BELOW normal app windows (Level -1).
    /// Guarantees standard application windows (Level 0) render ON TOP of the dock.
    public static var belowNormalWindows: NSWindow.Level {
        let normalLevel = Int(CGWindowLevelForKey(.normalWindow)) // 0
        return NSWindow.Level(rawValue: normalLevel - 1)          // -1
    }

    /// Alternative sub-window level pinned just above desktop icons (`kCGDesktopIconWindowLevelKey + 1`).
    public static var aboveDesktopIcons: NSWindow.Level {
        let desktopIconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        return NSWindow.Level(rawValue: desktopIconLevel + 1)
    }

    /// Standard application window level (`kCGNormalWindowLevelKey` = 0).
    public static var normalWindow: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.normalWindow)))
    }

    /// Native macOS Dock window level (`kCGDockWindowLevelKey` = 20).
    public static var nativeDock: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
    }

    /// Sits 1 level above Apple's native Dock (`kCGDockWindowLevelKey + 1` = 21)
    /// for the `.nativeDockVisibleFramePiggyback` fallback.
    public static var aboveNativeDock: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
    }

    /// Screen-edge sensor level (`kCGStatusWindowLevelKey + 1` = 26) so the 2pt bottom strip
    /// always catches mouse hover even when a window covers the dock.
    public static var edgeTriggerSensor: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
    }
}
