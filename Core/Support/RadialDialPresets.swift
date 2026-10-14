import Foundation
import CoreGraphics

/// Generates standard multi-page definitions and item configurations for the radial dial (Phase 31d).
enum RadialDialPresets {

    /// Standard default pages: Main launcher, Window snapping, and Tools & Media.
    static func defaultPages() -> [RadialDialPage] {
        [
            mainPage(),
            snappingPage(),
            toolsPage()
        ]
    }

    /// Page 1: Main hybrid page (Apps + Core Navigation, inspired by Image 2).
    static func mainPage() -> RadialDialPage {
        RadialDialPage(
            id: .main,
            title: "main",
            centerItem: RadialDialItem(
                id: "main_hub",
                title: "KatiKati",
                icon: .system("circle.grid.cross.fill"),
                accentHex: "#8B5CF6",
                action: .page(.snapping)
            ),
            items: [
                RadialDialItem(
                    id: "app_finder",
                    title: "Finder",
                    icon: .app(bundleID: "com.apple.finder"),
                    action: .launchApp(bundleID: "com.apple.finder", name: "Finder")
                ),
                RadialDialItem(
                    id: "app_safari",
                    title: "Safari",
                    icon: .app(bundleID: "com.apple.Safari"),
                    action: .launchApp(bundleID: "com.apple.Safari", name: "Safari")
                ),
                RadialDialItem(
                    id: "app_terminal",
                    title: "Terminal",
                    icon: .app(bundleID: "com.apple.Terminal"),
                    action: .launchApp(bundleID: "com.apple.Terminal", name: "Terminal")
                ),
                RadialDialItem(
                    id: "app_music",
                    title: "Music",
                    icon: .app(bundleID: "com.apple.Music"),
                    action: .launchApp(bundleID: "com.apple.Music", name: "Music")
                ),
                RadialDialItem(
                    id: "nav_snapping",
                    title: "Snapping",
                    icon: .sfSymbol("rectangle.split.2x1"),
                    accentHex: "#6366F1",
                    hasSubmenu: true,
                    action: .page(.snapping)
                ),
                RadialDialItem(
                    id: "nav_tools",
                    title: "Tools",
                    icon: .sfSymbol("wrench.and.screwdriver"),
                    accentHex: "#EC4899",
                    hasSubmenu: true,
                    action: .page(.tools)
                ),
                RadialDialItem(
                    id: "act_clipboard",
                    title: "Clipboard",
                    icon: .sfSymbol("doc.on.clipboard"),
                    accentHex: "#14B8A6",
                    action: .clipboard
                ),
                RadialDialItem(
                    id: "act_shelf",
                    title: "Shelf",
                    icon: .sfSymbol("tray.and.arrow.down.fill"),
                    accentHex: "#3B82F6",
                    action: .openShelf
                ),
                RadialDialItem(
                    id: "act_capture",
                    title: "Capture",
                    icon: .sfSymbol("camera.viewfinder"),
                    accentHex: "#F59E0B",
                    action: .captureArea
                ),
                RadialDialItem(
                    id: "act_tiling",
                    title: "Tiling",
                    icon: .sfSymbol("rectangle.split.2x2"),
                    accentHex: "#8B5CF6",
                    action: .toggleTiling
                )
            ]
        )
    }

    /// Page 2: Window Snapping (Loop / Blossom style with live preview).
    static func snappingPage() -> RadialDialPage {
        RadialDialPage(
            id: .snapping,
            title: "snap",
            centerItem: RadialDialItem(
                id: "snap_maximize",
                title: "Maximize",
                icon: .sfSymbol("arrow.up.left.and.arrow.down.right"),
                accentHex: "#8B5CF6",
                action: .snap(.maximize)
            ),
            items: [
                RadialDialItem(
                    id: "snap_top",
                    title: "Top",
                    icon: .sfSymbol("rectangle.portrait.topthird.inset.filled"),
                    accentHex: "#3B82F6",
                    action: .snap(.topHalf)
                ),
                RadialDialItem(
                    id: "snap_top_right",
                    title: "Top Right",
                    icon: .sfSymbol("rectangle.inset.topright.filled"),
                    accentHex: "#6366F1",
                    action: .snap(.topRight)
                ),
                RadialDialItem(
                    id: "snap_right",
                    title: "Right",
                    icon: .sfSymbol("rectangle.righthalf.inset.filled"),
                    accentHex: "#8B5CF6",
                    action: .snap(.rightHalf)
                ),
                RadialDialItem(
                    id: "snap_bottom_right",
                    title: "Bottom Right",
                    icon: .sfSymbol("rectangle.inset.bottomright.filled"),
                    accentHex: "#EC4899",
                    action: .snap(.bottomRight)
                ),
                RadialDialItem(
                    id: "snap_bottom",
                    title: "Bottom",
                    icon: .sfSymbol("rectangle.bottomhalf.inset.filled"),
                    accentHex: "#EF4444",
                    action: .snap(.bottomHalf)
                ),
                RadialDialItem(
                    id: "snap_bottom_left",
                    title: "Bottom Left",
                    icon: .sfSymbol("rectangle.inset.bottomleft.filled"),
                    accentHex: "#F59E0B",
                    action: .snap(.bottomLeft)
                ),
                RadialDialItem(
                    id: "snap_left",
                    title: "Left",
                    icon: .sfSymbol("rectangle.lefthalf.inset.filled"),
                    accentHex: "#10B981",
                    action: .snap(.leftHalf)
                ),
                RadialDialItem(
                    id: "snap_top_left",
                    title: "Top Left",
                    icon: .sfSymbol("rectangle.inset.topleft.filled"),
                    accentHex: "#14B8A6",
                    action: .snap(.topLeft)
                )
            ]
        )
    }

    /// Page 3: Tools & Media (inspired by Image 1).
    static func toolsPage() -> RadialDialPage {
        RadialDialPage(
            id: .tools,
            title: "tools",
            centerItem: RadialDialItem(
                id: "tools_hub",
                title: "Main",
                icon: .sfSymbol("house.fill"),
                accentHex: "#EC4899",
                action: .page(.main)
            ),
            items: [
                RadialDialItem(
                    id: "tool_playpause",
                    title: "Play/Pause",
                    icon: .sfSymbol("playpause.fill"),
                    accentHex: "#10B981",
                    action: .mediaPlayPause
                ),
                RadialDialItem(
                    id: "tool_next",
                    title: "Next",
                    icon: .sfSymbol("forward.fill"),
                    accentHex: "#3B82F6",
                    action: .mediaNext
                ),
                RadialDialItem(
                    id: "tool_capture",
                    title: "Screenshot",
                    icon: .sfSymbol("camera.viewfinder"),
                    accentHex: "#EC4899",
                    action: .captureArea
                ),
                RadialDialItem(
                    id: "tool_ocr",
                    title: "Scan Text",
                    icon: .sfSymbol("viewfinder.text"),
                    accentHex: "#F59E0B",
                    action: .captureOCR
                ),
                RadialDialItem(
                    id: "tool_shelf",
                    title: "Shelf",
                    icon: .sfSymbol("tray.and.arrow.down.fill"),
                    accentHex: "#6366F1",
                    action: .openShelf
                ),
                RadialDialItem(
                    id: "tool_clipboard",
                    title: "Clipboard",
                    icon: .sfSymbol("doc.on.clipboard"),
                    accentHex: "#14B8A6",
                    action: .clipboard
                )
            ]
        )
    }
}
