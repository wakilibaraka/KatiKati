import Combine
import Foundation

/// 设置窗口的十九个标签页（2026-10-20：坞站小组件/小组件拆页、天气独立成页、窗口管理拆成
/// 平铺+窗口管理、启动器拆出命令栏；2026-10-22：通知从「高级」独立成页）。标题复用原分区标题的
/// 本地化 key；图标全部 macOS 11 起可用（对照 CoreGlyphs name_availability 核过）。
/// 纯 Foundation/Combine——测试 target 也编译它，别引 AppKit。
enum SettingsTab: String, CaseIterable {
    case general
    case appearance
    // The dock's widgets: the chips' order, sizes, and presets.
    case dockItems
    // The widget panes' look.
    case widgets
    case weather
    case notch
    // Battery, charging and peripheral alerts, their history, and where macOS banners land.
    case notifications
    case edgeBars
    // Raw value stays "tiling": it is the toolbar item identifier.
    case tiling
    case windowManagement
    case launcher
    case commandBar
    case controlCenter
    case shortcuts
    // Split out of Shortcuts and Tools by the sidebar redesign (2026-10-18); About's rows live on Info.
    case radialDial
    case downloads
    // Takes the slot the About page left (2026-10-15). About's four rows
    // moved to General, where they are read — a page of four rows nobody visits was the wrong
    // trade (`Docs/SETTINGS.md` §3).
    case tools
    case info
    // Last (owner, 2026-10-15): the page you visit once sits at the end of the strip, so the tools
    // used mid-session are no longer behind it.
    case advanced

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .dockItems: return String(localized: "Dock Items")
        case .widgets: return String(localized: "Widgets")
        case .weather: return String(localized: "Weather")
        case .notch: return String(localized: "Notch")
        case .notifications: return String(localized: "Notifications")
        case .edgeBars: return String(localized: "Edge Bars")
        case .appearance: return String(localized: "Appearance")
        case .tiling: return String(localized: "Tiling")
        case .windowManagement: return String(localized: "Window Management")
        case .launcher: return String(localized: "Launcher")
        case .commandBar: return String(localized: "Command Bar")
        case .controlCenter: return String(localized: "Control Center")
        case .shortcuts: return String(localized: "Shortcuts")
        case .advanced: return String(localized: "Advanced")
        case .tools: return String(localized: "Tools")
        case .radialDial: return String(localized: "Radial Dial")
        case .downloads: return String(localized: "Downloads")
        case .info: return String(localized: "Info")
        }
    }

    /// One-line page subtitle under the shell header. Whole literals:
    /// the localizer sees each key, and the header renders the resolved value verbatim.
    var subtitle: String {
        switch self {
        case .general: return String(localized: "Language, appearance, shortcuts, and the app itself.")
        case .appearance: return String(localized: "Themes, icons, and wallpaper.")
        case .dockItems: return String(localized: "Dock widgets: order, size, presets, and motion.")
        case .widgets: return String(localized: "Widget panes: layout, colors, and style.")
        case .weather: return String(localized: "Weather units, layout, and warnings.")
        case .notch: return String(localized: "The Dynamic Notch: skin, pages, size, and alerts.")
        case .notifications: return String(localized: "Battery, charging, peripherals, and banner placement.")
        case .edgeBars: return String(localized: "Side bars: preset, placement, widgets, and size.")
        case .tiling: return String(localized: "Auto-tiling, presets, gaps, and floating apps.")
        case .windowManagement: return String(localized: "Window chips and window behaviors.")
        case .launcher: return String(localized: "Search, results, and hidden apps.")
        case .commandBar: return String(localized: "Command hints and the command bar.")
        case .controlCenter: return String(localized: "Tiles, quick settings, and placement.")
        case .shortcuts: return String(localized: "Keyboard shortcuts, snap zones, and input.")
        case .radialDial: return String(localized: "The pie menu: actions, theme, and triggers.")
        case .downloads: return String(localized: "Torrents: speed, schedule, and quiet hours.")
        case .tools: return String(localized: "Clipboard, commands, snippets, and shelf.")
        case .info: return String(localized: "Version, updates, diagnostics, and permissions.")
        case .advanced: return String(localized: "Rarely touched switches that need extra powers.")
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .dockItems: return "square.grid.1x2"
        case .widgets: return "square.grid.2x2"
        case .weather: return "cloud.sun"
        case .notch: return "capsule.tophalf.filled"
        case .notifications: return "bell"
        case .edgeBars: return "sidebar.right"
        case .appearance: return "paintpalette"
        case .tiling: return "rectangle.split.2x2"
        case .windowManagement: return "macwindow"
        case .launcher: return "magnifyingglass"
        case .commandBar: return "terminal"
        case .controlCenter: return "switch.2"
        case .shortcuts: return "command"
        case .advanced: return "wrench.and.screwdriver"
        // The clipboard is the page's first tool; macOS 11+, checked against CoreGlyphs
        // name_availability alongside the rest of this set.
        case .tools: return "doc.on.clipboard"
        case .radialDial: return "circle.hexagongrid"
        case .downloads: return "arrow.down.circle"
        case .info: return "info.circle"
        }
    }

    /// The section's own hue (sRGB 0...1), used for its sidebar icon and, later, selection and the
    /// stage glow. Plain numbers: this file compiles into the test target, which has no SwiftUI.
    var hue: (red: Double, green: Double, blue: Double) {
        switch self {
        case .general: return (0.56, 0.56, 0.58)
        case .appearance: return (0.96, 0.33, 0.50)
        case .dockItems: return (0.72, 0.52, 0.20)
        case .widgets: return (0.58, 0.40, 0.93)
        case .weather: return (0.30, 0.72, 0.78)
        case .notch: return (0.30, 0.30, 0.34)
        case .notifications: return (0.96, 0.46, 0.24)
        case .edgeBars: return (0.10, 0.70, 0.66)
        case .tiling: return (0.20, 0.52, 0.98)
        case .windowManagement: return (0.25, 0.35, 0.65)
        case .launcher: return (0.38, 0.36, 0.90)
        case .commandBar: return (0.85, 0.35, 0.35)
        case .controlCenter: return (1.00, 0.55, 0.15)
        case .shortcuts: return (0.98, 0.72, 0.10)
        case .radialDial: return (0.92, 0.36, 0.78)
        case .downloads: return (0.12, 0.72, 0.88)
        case .tools: return (0.20, 0.78, 0.35)
        case .info: return (0.35, 0.68, 0.95)
        case .advanced: return (0.42, 0.46, 0.54)
        }
    }
}

/// controller → SwiftUI 的选中页桥。所选标签跨重启记住（侧栏改版 2026-10-18，与窗口位置同时开始持久化）。
@MainActor
final class SettingsTabState: ObservableObject {
    static let defaultsKey = "com.katikati.settings.tab"

    @Published var selected: SettingsTab {
        didSet { UserDefaults.standard.set(selected.rawValue, forKey: Self.defaultsKey) }
    }

    /// The sidebar query that opened this page; the shell scrolls to the first row matching it.
    @Published var findQuery = ""

    init() {
        selected = UserDefaults.standard.string(forKey: Self.defaultsKey).flatMap(SettingsTab.init(rawValue:)) ?? .general
    }
}
