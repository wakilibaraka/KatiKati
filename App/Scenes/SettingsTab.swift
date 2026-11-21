import Combine
import Foundation

/// 设置窗口的二十九个标签页（2026-11：Shortcuts 按输入设备拆成键盘快捷键 / 键盘 /
/// 按键浮层 / 鼠标 / 触控板手势五页，退出保护单独成页）。
/// 纯 Foundation/Combine——测试 target 也编译它，别引 AppKit。
enum SettingsTab: String, CaseIterable {
    case general
    case menuBar
    case appearance
    case dockItems
    case drawer
    case shelf
    case widgets
    case desktop
    case weather
    case notch
    case notifications
    case edgeBars
    case tiling
    case windowManagement
    case launcher
    case commandBar
    case controlCenter
    case shortcuts
    case keyboard
    case keyVisualizer
    case mouse
    case mouseGestures
    case quitApps
    case radialDial
    case aiTracking
    case downloads
    case clipboard
    case tools
    case advanced

    init?(rawValue: String) {
        switch rawValue {
        case "general": self = .general
        case "menuBar": self = .menuBar
        case "appearance": self = .appearance
        case "dockItems": self = .dockItems
        case "drawer": self = .drawer
        case "shelf", "drawerShelf": self = .shelf
        case "widgets": self = .widgets
        case "desktop": self = .desktop
        case "weather": self = .weather
        case "notch": self = .notch
        case "notifications": self = .notifications
        case "edgeBars": self = .edgeBars
        case "tiling": self = .tiling
        case "windowManagement": self = .windowManagement
        case "launcher": self = .launcher
        case "commandBar": self = .commandBar
        case "controlCenter": self = .controlCenter
        case "shortcuts": self = .shortcuts
        case "keyboard": self = .keyboard
        case "keyVisualizer": self = .keyVisualizer
        case "mouse": self = .mouse
        case "mouseGestures": self = .mouseGestures
        case "quitApps", "quit": self = .quitApps
        case "radialDial": self = .radialDial
        case "aiTracking": self = .aiTracking
        case "downloads": self = .downloads
        case "clipboard": self = .clipboard
        case "tools": self = .tools
        case "advanced": self = .advanced
        case "info": self = .general
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .menuBar: return String(localized: "Menu Bar")
        case .appearance: return String(localized: "Appearance")
        case .dockItems: return String(localized: "Dock Items")
        case .drawer: return String(localized: "Drawer")
        case .shelf: return String(localized: "Shelf")
        case .widgets: return String(localized: "Widgets")
        case .desktop: return String(localized: "Desktop")
        case .weather: return String(localized: "Weather")
        case .notch: return String(localized: "Notch")
        case .notifications: return String(localized: "Notifications")
        case .edgeBars: return String(localized: "Edge Bars")
        case .tiling: return String(localized: "Tiling")
        case .windowManagement: return String(localized: "Window Management")
        case .launcher: return String(localized: "Launcher")
        case .commandBar: return String(localized: "Command Bar")
        case .controlCenter: return String(localized: "Control Center")
        case .shortcuts: return String(localized: "Keyboard Shortcuts")
        case .keyboard: return String(localized: "Keyboard")
        case .keyVisualizer: return String(localized: "Key Visualizer")
        case .mouse: return String(localized: "Mouse")
        case .mouseGestures: return String(localized: "Trackpad Gestures")
        case .quitApps: return String(localized: "Quit & Close")
        case .radialDial: return String(localized: "Radial Dial")
        case .aiTracking: return String(localized: "AI Tracking")
        case .downloads: return String(localized: "Downloads")
        case .clipboard: return String(localized: "Clipboard")
        case .tools: return String(localized: "Tools")
        case .advanced: return String(localized: "Advanced")
        }
    }

    /// One-line page subtitle under the shell header. Whole literals:
    /// the localizer sees each key, and the header renders the resolved value verbatim.
    var subtitle: String {
        switch self {
        case .general: return String(localized: "Language, startup, permissions, and about.")
        case .menuBar: return String(localized: "System metrics, drive capacity, and status items.")
        case .appearance: return String(localized: "Themes, icons, and wallpaper.")
        case .dockItems: return String(localized: "Dock widgets: order, size, presets, and motion.")
        case .drawer: return String(localized: "Background-app capsule and edge placement.")
        case .shelf: return String(localized: "Floating card stack, shake-to-shelf, Notch File Tray, and space pinning.")
        case .widgets: return String(localized: "Widget panes: layout, colors, and style.")
        case .desktop: return String(localized: "Folder boxes, to-dos, notes, and glanceable widgets on your desktop.")
        case .weather: return String(localized: "Weather units, layout, and warnings.")
        case .notch: return String(localized: "The Dynamic Notch: skin, pages, size, and alerts.")
        case .notifications: return String(localized: "Battery, charging, peripherals, and banner placement.")
        case .edgeBars: return String(localized: "Side bars: preset, placement, widgets, and size.")
        case .tiling: return String(localized: "Auto-tiling, presets, gaps, and floating apps.")
        case .windowManagement: return String(localized: "Window chips and window behaviors.")
        case .launcher: return String(localized: "Search, results, and hidden apps.")
        case .commandBar: return String(localized: "Command hints and the command bar.")
        case .controlCenter: return String(localized: "Tiles, quick settings, and placement.")
        case .shortcuts: return String(localized: "Every key combination: features, snap zones, tiling, and hold timing.")
        case .keyboard: return String(localized: "Super/Hyper, Caps Lock, Finder keys, pause, and cleaning.")
        case .keyVisualizer: return String(localized: "The key overlay: what it shows, how it looks, and where it sits.")
        case .mouse: return String(localized: "Focus follows the pointer, scroll direction, and click feedback.")
        case .mouseGestures: return String(localized: "Multitouch swipes, pinches, taps, and the live visualizer.")
        case .quitApps: return String(localized: "Quit protection, quit-on-close, and idle apps.")
        case .radialDial: return String(localized: "The pie menu: actions, theme, and triggers.")
        case .aiTracking: return String(localized: "Claude Code hooks, tool approvals, token limits, and telemetry.")
        case .downloads: return String(localized: "Torrents: speed, schedule, and quiet hours.")
        case .clipboard: return String(localized: "History, privacy, storage, and the popup.")
        case .tools: return String(localized: "Commands, snippets, and the shortcut cheat sheet.")
        case .advanced: return String(localized: "Rarely touched switches that need extra powers.")
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .menuBar: return "menubar.rectangle"
        case .appearance: return "paintpalette"
        case .dockItems: return "square.grid.2x2"
        case .drawer: return "sidebar.squares.trailing"
        case .shelf: return "tray.and.arrow.down"
        case .widgets: return "square.grid.2x2"
        case .desktop: return "macwindow.on.rectangle"
        case .weather: return "cloud.sun"
        case .notch: return "capsule.tophalf.filled"
        case .notifications: return "bell"
        case .edgeBars: return "sidebar.right"
        case .tiling: return "rectangle.split.2x2"
        case .windowManagement: return "macwindow"
        case .launcher: return "magnifyingglass"
        case .commandBar: return "terminal"
        case .controlCenter: return "switch.2"
        case .shortcuts: return "command"
        case .keyboard: return "keyboard"
        case .keyVisualizer: return "captions.bubble"
        case .mouse: return "computermouse"
        case .mouseGestures: return "hand.draw"
        case .quitApps: return "power"
        case .radialDial: return "circle.hexagongrid"
        case .aiTracking: return "brain.head.profile"
        case .downloads: return "arrow.down.circle"
        case .clipboard: return "doc.on.clipboard"
        case .tools: return "hammer"
        case .advanced: return "wrench.and.screwdriver"
        }
    }

    /// The section's own hue (sRGB 0...1), used for its sidebar icon and selection.
    var hue: (red: Double, green: Double, blue: Double) {
        switch self {
        case .general: return (0.56, 0.56, 0.58)
        case .menuBar: return (0.15, 0.65, 0.95)
        case .appearance: return (0.96, 0.33, 0.50)
        case .dockItems: return (0.72, 0.52, 0.20)
        case .drawer: return (0.92, 0.48, 0.15)
        case .shelf: return (0.48, 0.36, 0.88)
        case .widgets: return (0.58, 0.40, 0.93)
        case .desktop: return (0.20, 0.60, 0.86)
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
        case .keyboard: return (0.30, 0.78, 0.48)
        case .keyVisualizer: return (0.62, 0.86, 0.34)
        case .mouse: return (0.44, 0.58, 0.72)
        case .mouseGestures: return (0.36, 0.62, 0.92)
        case .quitApps: return (0.80, 0.24, 0.36)
        case .radialDial: return (0.92, 0.36, 0.78)
        case .aiTracking: return (0.64, 0.28, 0.92)
        case .downloads: return (0.12, 0.72, 0.88)
        case .clipboard: return (0.95, 0.62, 0.20)
        case .tools: return (0.20, 0.78, 0.35)
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
