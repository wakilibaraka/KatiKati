import CoreGraphics

// Settings redesign, Phase 1 — what the free-resizing Settings window shows at a given size.
//
// The window has no fixed layout: the sidebar shrinks to icons, the live preview ("stage") moves or
// hides, and cards gain columns as the window changes size. One pure function decides all of it so
// the shell only reads the answer and the breakpoints are unit-tested.
//
// Dual-compiled: pure numbers, no AppKit/SwiftUI.

enum SettingsStagePreference: String, CaseIterable {
    case top, side, off
}

struct SettingsLayoutClass: Equatable {
    enum Sidebar: Equatable { case full, icons }
    enum Stage: Equatable { case top, side, hidden }

    /// Below this window width the sidebar shows icons only.
    static let sidebarCollapseWidth: CGFloat = 860
    /// Below this window height the stage is hidden whatever the user chose.
    static let stageMinWindowHeight: CGFloat = 480
    /// A stage on the side needs this much window width.
    static let sideStageMinWindowWidth: CGFloat = 720
    /// One control column needs about this much room.
    static let columnWidth: CGFloat = 360
    static let maxColumns = 3

    let sidebar: Sidebar
    let stage: Stage
    /// Columns of cards the page content area holds.
    let columns: Int

    static func resolve(
        windowWidth: CGFloat,
        windowHeight: CGFloat,
        sidebarForcedIcons: Bool,
        stagePreference: SettingsStagePreference
    ) -> SettingsLayoutClass {
        let sidebar: Sidebar = (sidebarForcedIcons || windowWidth < sidebarCollapseWidth) ? .icons : .full
        let sidebarWidth = sidebar == .full ? SettingsMetrics.sidebarWidth : SettingsMetrics.sidebarCollapsedWidth

        var stage: Stage
        switch stagePreference {
        case .top: stage = .top
        case .side: stage = .side
        case .off: stage = .hidden
        }
        if windowHeight < stageMinWindowHeight { stage = .hidden }
        if stage == .side && windowWidth < sideStageMinWindowWidth { stage = .hidden }

        let content = max(0, windowWidth - sidebarWidth - 2 * SettingsMetrics.paneMargin)
        let columns = min(maxColumns, max(1, Int(content / columnWidth)))
        return SettingsLayoutClass(sidebar: sidebar, stage: stage, columns: columns)
    }
}
