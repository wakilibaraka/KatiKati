import Combine
import Foundation

/// 设置窗口的十个标签页（Phase 12，2026-10：「布局」页拆散进通用/小组件/刘海/边栏/窗口管理/启动器/工具/快捷键；移除「授权」「反馈」）（2026-08-24 分页；「Dock 栏」页 2026-09-01
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
    case shortcuts
    // Takes the slot the About page left (2026-10-15). The count stays ten and About's four rows
    // moved to General, where they are read — a page of four rows nobody visits was the wrong
    // trade (`Docs/SETTINGS.md` §3).
    case tools
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
        case .shortcuts: return String(localized: "Shortcuts")
        case .advanced: return String(localized: "Advanced")
        case .tools: return String(localized: "Tools")
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
        case .shortcuts: return "command"
        case .advanced: return "wrench.and.screwdriver"
        // The clipboard is the page's first tool; macOS 11+, checked against CoreGlyphs
        // name_availability alongside the rest of this set.
        case .tools: return "doc.on.clipboard"
        }
    }
}

/// controller → SwiftUI 的选中页桥。controller 持有唯一一份 = 会话内记住所选标签；
/// **不落 UserDefaults**（与「设置窗口不跨重启记位置」同一条规矩）。
/// 量高探针必须共享这同一个实例，否则量的是别的页。
@MainActor
final class SettingsTabState: ObservableObject {
    @Published var selected: SettingsTab = .general
}
