import Combine
import Foundation

/// 设置窗口的十四个标签页（Phase 12，2026-10：「布局」页拆散进通用/小组件/刘海/边栏/窗口管理/启动器/工具/快捷键；移除「授权」「反馈」）（2026-08-24 分页；「Dock 栏」页 2026-09-01
/// 整页搬进状态栏菜单，见 `Docs/27`）。标题复用原分区标题的
/// 本地化 key；图标全部 macOS 11 起可用（对照 CoreGlyphs name_availability 核过）。
/// 纯 Foundation/Combine——测试 target 也编译它，别引 AppKit。
enum SettingsTab: String, CaseIterable {
    case general
    case appearance
    case widgets
    case notch
    case edgeBars
    // Raw value stays "tiling": it is the toolbar item identifier.
    case windowManagement = "tiling"
    case launcher
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
        case .widgets: return String(localized: "Widgets")
        case .notch: return String(localized: "Notch")
        case .edgeBars: return String(localized: "Edge Bars")
        case .appearance: return String(localized: "Appearance")
        case .windowManagement: return String(localized: "Window Management")
        case .launcher: return String(localized: "Launcher")
        case .controlCenter: return String(localized: "Control Center")
        case .shortcuts: return String(localized: "Shortcuts")
        case .advanced: return String(localized: "Advanced")
        case .tools: return String(localized: "Tools")
        case .radialDial: return String(localized: "Radial Dial")
        case .downloads: return String(localized: "Downloads")
        case .info: return String(localized: "Info")
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .widgets: return "square.grid.2x2"
        case .notch: return "capsule.tophalf.filled"
        case .edgeBars: return "sidebar.right"
        case .appearance: return "paintpalette"
        case .windowManagement: return "rectangle.split.2x2"
        case .launcher: return "magnifyingglass"
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
        case .widgets: return (0.58, 0.40, 0.93)
        case .notch: return (0.30, 0.30, 0.34)
        case .edgeBars: return (0.10, 0.70, 0.66)
        case .windowManagement: return (0.20, 0.52, 0.98)
        case .launcher: return (0.38, 0.36, 0.90)
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

    init() {
        selected = UserDefaults.standard.string(forKey: Self.defaultsKey).flatMap(SettingsTab.init(rawValue:)) ?? .general
    }
}
