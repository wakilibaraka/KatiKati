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
        var widgetOrder: [BarSection] = BarSection.defaultOrder
        /// Phase 18h: which edge the strip sits on.
        var placement: StripPlacement = .bottom
        /// Representative app count: enough to show the apps island's weight, few enough
        /// that no reference mode overflows.
        var appCount: Int = 10
    }

    /// Capsule gap + width (`PanelLayoutMetrics.capsuleGap` + bar height).
    static func capsuleSpace(barHeight: CGFloat) -> CGFloat { 8 + barHeight }

    /// The drawer capsule beside the apps island, in the same unit space (`nil` without apps).
    /// Bottom-bar helper kept for callers holding only islands; `capsule(for:inputs:)` covers rails.
    static func capsule(beside islands: [Island], barHeight: CGFloat, screen: CGSize = referenceScreen) -> CGRect? {
        guard let apps = islands.first(where: { $0.sections.contains(.apps) })?.rect else { return nil }
        return CGRect(x: apps.maxX + 8 / screen.width, y: apps.minY,
                      width: barHeight / screen.width, height: apps.height)
    }

    /// 16:10 reference screen, the common MacBook aspect.
    static let referenceScreen = CGSize(width: 1440, height: 900)
    /// Menu-bar height on the reference screen: a rail starts below it (Phase 18h).
    static let referenceMenuBar: CGFloat = 25

    static func islands(for mode: BarLayoutMode,
                        inputs: Inputs = Inputs(),
                        screen: CGSize = referenceScreen) -> [Island] {
        solve(mode: mode, inputs: inputs, screen: screen).islands
    }

    /// The capsule for any placement (right of the apps island on the bottom, below it on a rail).
    static func capsule(for mode: BarLayoutMode, inputs: Inputs = Inputs(), screen: CGSize = referenceScreen) -> CGRect? {
        solve(mode: mode, inputs: inputs, screen: screen).capsule
    }

    /// One pipeline for islands and capsule: solve as a bottom strip (on a rail: as long as the screen
    /// is tall below the menu bar, with compact rail tiles), reserve the capsule in solver space, then
    /// map onto the placement's edge (`StripAxis.map`) and normalise to a top-left unit box.
    private static func solve(mode: BarLayoutMode, inputs: Inputs, screen: CGSize) -> (islands: [Island], capsule: CGRect?) {
        let placement = inputs.placement
        let screenRect = CGRect(origin: .zero, size: screen)
        let topInset = placement.isVertical ? referenceMenuBar : 0
        let length = StripAxis.mainLength(placement: placement, screen: screenRect, topInset: topInset)
        var widths = inputs.widgetWidths
        if placement.isVertical {
            widths = [:]
            for section in BarSection.allCases where section != .apps {
                widths[section] = section.railTileLength(barHeight: IslandChrome.nativeBarHeight)
            }
        }
        let stride = IslandLayoutSolver.tileStride(barHeight: inputs.barHeight)
        let layout = IslandLayoutSolver.layout(
            screenWidth: length,
            mode: mode,
            widgetOrder: inputs.widgetOrder,
            widgetWidths: widths,
            tileStride: stride,
            appCount: placement.isVertical ? min(inputs.appCount, 7) : inputs.appCount,
            weatherWidth: BarSection.weather.defaultWidgetWidth,
            clockWidth: BarSection.clock.defaultWidgetWidth,
            clusterWidth: inputs.barHeight,
            gap: inputs.gap,
            margin: inputs.margin,
            barHeight: inputs.barHeight,
            bottomMargin: inputs.bottomGap,
            centeredWidth: inputs.centeredWidth,
            // A rail card previews the rail's own ends (Phase 42), or the card and the bar disagree.
            contentInset: placement.isVertical ? IslandChrome.railContentInset : IslandChrome.contentInset
        )
        let capsuleSpace = Self.capsuleSpace(barHeight: inputs.barHeight)
        var capsule: CGRect?
        var frames: [(Island, CGRect)] = []
        for island in layout.islands {
            var f = island.frame
            if island.sections.contains(.apps) {
                // The drawer capsule rides at the apps island's end, as on the live bar
                // (`PanelGeometry.islandTargetFrame`): the plate gives up its slot (Phase 11b).
                if mode == .centered && !placement.isVertical {
                    // Centered keeps its width; bar + capsule are centred as one group.
                    f.origin.x -= capsuleSpace / 2
                } else {
                    f.size.width = max(f.width - capsuleSpace, f.height)
                }
                capsule = CGRect(x: f.maxX + 8, y: f.minY, width: inputs.barHeight, height: f.height)
            }
            frames.append((Island(slot: island.slot, sections: island.sections, rect: .zero), f))
        }
        func normalised(_ solved: CGRect) -> CGRect {
            let f = StripAxis.map(solved, placement: placement, screen: screenRect, topInset: topInset)
            // Solver space is bottom-left; flip to top-left for drawing.
            return CGRect(x: f.minX / screen.width, y: (screen.height - f.maxY) / screen.height,
                          width: f.width / screen.width, height: f.height / screen.height)
        }
        let islands = frames.map { pair -> Island in
            var island = pair.0
            island.rect = normalised(pair.1)
            return island
        }
        return (islands, capsule.map(normalised))
    }
}
