import CoreGraphics
import Foundation

/// Mode-picker thumbnails (Phase 6 Layout tab + welcome step), drawn from the real
/// `IslandLayoutSolver` output so a preview can never disagree with the bar it promises.
///
/// Pure: a synthetic reference screen goes through the solver with the user's live
/// widths / gap / margin / centered width / bottom gap / bar height, and the island
/// frames come back normalised to a unit box with a **top-left** origin (SwiftUI
/// drawing space). Callers multiply by their own canvas size.
enum LayoutThumbnailModel {
    struct Island: Equatable {
        var slot: Int
        var sections: [BarSection]
        /// 0...1 in both axes, origin top-left.
        var rect: CGRect
    }

    struct Inputs: Equatable {
        var barHeight: CGFloat = DockPanelHeight.native.points
        var gap: CGFloat = 10
        var margin: CGFloat = 12
        var centeredWidth: CGFloat = 720
        var bottomGap: CGFloat = PanelLayoutMetrics.floatingBottomGap
        var widgetWidths: [BarSection: CGFloat] = [:]
        /// Visible widget order (hidden widgets dropped) — the preview follows Settings › Widgets.
        var widgetOrder: [BarSection] = BarSection.canonicalOrder
        /// Representative app count: enough to show the apps island's weight, few enough
        /// that no reference mode overflows.
        var appCount: Int = 10
    }

    /// Capsule gap + width (`PanelLayoutMetrics.capsuleGap` + bar height).
    static func capsuleSpace(barHeight: CGFloat) -> CGFloat { 8 + barHeight }

    /// The drawer capsule beside the apps island, in the same unit space (`nil` without apps).
    static func capsule(beside islands: [Island], barHeight: CGFloat, screen: CGSize = referenceScreen) -> CGRect? {
        guard let apps = islands.first(where: { $0.sections.contains(.apps) })?.rect else { return nil }
        return CGRect(x: apps.maxX + 8 / screen.width, y: apps.minY,
                      width: barHeight / screen.width, height: apps.height)
    }

    /// 16:10 reference screen, the common MacBook aspect.
    static let referenceScreen = CGSize(width: 1440, height: 900)

    static func islands(for mode: BarLayoutMode,
                        inputs: Inputs = Inputs(),
                        screen: CGSize = referenceScreen) -> [Island] {
        let stride = IslandLayoutSolver.tileStride(barHeight: inputs.barHeight)
        let layout = IslandLayoutSolver.layout(
            screenWidth: screen.width,
            mode: mode,
            widgetOrder: inputs.widgetOrder,
            widgetWidths: inputs.widgetWidths,
            tileStride: stride,
            appCount: inputs.appCount,
            weatherWidth: BarSection.weather.defaultWidgetWidth,
            clockWidth: BarSection.clock.defaultWidgetWidth,
            clusterWidth: inputs.barHeight,
            gap: inputs.gap,
            margin: inputs.margin,
            barHeight: inputs.barHeight,
            bottomMargin: inputs.bottomGap,
            centeredWidth: inputs.centeredWidth
        )
        return layout.islands.map { island in
            var f = island.frame
            if island.sections.contains(.apps) {
                // The drawer capsule rides at the apps island's end, as on the live bar
                // (`PanelGeometry.islandTargetFrame`): the plate gives up its slot (Phase 11b).
                let capsuleSpace = Self.capsuleSpace(barHeight: inputs.barHeight)
                if mode == .centered {
                    // Centered keeps its width; bar + capsule are centred as one group.
                    f.origin.x -= capsuleSpace / 2
                } else {
                    f.size.width = max(f.width - capsuleSpace, f.height)
                }
            }
            // Solver space is bottom-left; flip to top-left for drawing.
            let rect = CGRect(
                x: f.minX / screen.width,
                y: (screen.height - f.maxY) / screen.height,
                width: f.width / screen.width,
                height: f.height / screen.height
            )
            return Island(slot: island.slot, sections: island.sections, rect: rect)
        }
    }
}
