import Combine
import Foundation

/// 设置窗口的标签页（Phase 12 起目标十页，逐步到位）（Phase 6 加「布局」「外观」；2026-10 移除「授权」「反馈」）（2026-08-24 分页；「Dock 栏」页 2026-09-01
/// 整页搬进状态栏菜单，见 `Docs/27`）。标题复用原分区标题的
/// 本地化 key；图标全部 macOS 11 起可用（对照 CoreGlyphs name_availability 核过）。
/// 纯 Foundation/Combine——测试 target 也编译它，别引 AppKit。
enum SettingsTab: String, CaseIterable {
    case general
    case layout
    case widgets
    case edgeBars
    case appearance
    // Raw value stays "tiling": it is the toolbar item identifier.
    case windowManagement = "tiling"
    case advanced
    case about

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .layout: return String(localized: "Layout")
        case .widgets: return String(localized: "Widgets")
        case .edgeBars: return String(localized: "Edge Bars")
        case .appearance: return String(localized: "Appearance")
        case .windowManagement: return String(localized: "Window Management")
        case .advanced: return String(localized: "Advanced")
        case .about: return String(localized: "About")
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .layout: return "rectangle.split.3x1"
        case .widgets: return "square.grid.2x2"
        case .edgeBars: return "sidebar.right"
        case .appearance: return "paintpalette"
        case .windowManagement: return "rectangle.split.2x2"
        case .advanced: return "wrench.and.screwdriver"
        case .about: return "info.circle"
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
