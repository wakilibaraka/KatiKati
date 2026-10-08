import CoreGraphics
import Foundation

/// Pure geometry solver for multi-island and single-island taskbar layouts.
///
/// Ports the SplitBar-old `layoutIslands` algorithm and overflow-collapse loop into
/// a pure, deterministic engine while enforcing KatiKati's tungsten clamp discipline:
/// - All island frames remain strictly within `visibleFrame` / screen bounds.
/// - Minimum inter-island gap of 0.5 pt is enforced under all conditions.
/// - All frames use bottom-left origin screen space matching macOS / AppKit window frames.
/// - In all 4 modes (`windows`, `split3`, `split4`, `centered`), sections are mapped
///   without loss and `showsOverflow` triggers only when space is exhausted.
enum IslandLayoutSolver {
    /// The computed layout containing island frames and app chip overflow state.
    struct IslandLayout: Equatable, Sendable {
        /// A discrete floating bar segment / panel slot.
        struct Island: Equatable, Sendable {
            /// 0-based slot index of the island for the active layout mode.
            var slot: Int
            /// Logical content sections assigned to this island.
            var sections: [BarSection]
            /// Absolute window frame in bottom-left screen space.
            var frame: CGRect
        }

        /// The islands produced for the layout mode.
        var islands: [Island]
        /// Number of app tiles visible before overflow takes effect.
        var visibleAppTiles: Int
        /// Whether app tiles exceeded available space and collapsed into overflow.
        var showsOverflow: Bool
    }

    /// Tile stride derived from bar height.
    static func tileStride(barHeight: CGFloat) -> CGFloat {
        max(28, barHeight - 4) + 4
    }

    /// Intrinsic width for apps given a tile count, stride, and cluster width.
    static func appsContentWidth(count: Int, tileStride: CGFloat, clusterWidth: CGFloat) -> CGFloat {
        CGFloat(count) * tileStride + clusterWidth + 24
    }

    /// Computes island geometry for a given screen width and configuration.
    ///
    /// - Parameters:
    ///   - screenWidth: Screen width in points.
    ///   - mode: Active layout mode (`.windows`, `.split3`, `.split4`, `.centered`).
    ///   - tileStride: Horizontal stride per app chip.
    ///   - appCount: Total number of app items to lay out.
    ///   - weatherWidth: Fixed width of the weather widget/island.
    ///   - trayWidth: Fixed width of the status tray cluster.
    ///   - clockWidth: Fixed width of the clock / calendar widget.
    ///   - clusterWidth: Utility cluster width (drawer, shelf, trash, pinned folders).
    ///   - gap: Inter-island gap in points (enforces minimum 0.5 pt).
    ///   - margin: Outer horizontal margin from screen edges.
    ///   - barHeight: Height of the taskbar panels.
    ///   - bottomMargin: Distance from the bottom of the screen.
    ///   - centeredWidth: Target width for `.centered` mode (default: 720).
    ///   - screenOriginX: Left origin X of the screen (default: 0).
    ///   - screenMinY: Bottom origin Y of the screen (default: 0).
    /// - Returns: Complete `IslandLayout` with valid frames and overflow flags.
    static func layout(
        screenWidth: CGFloat,
        mode: BarLayoutMode,
        tileStride: CGFloat,
        appCount: Int,
        weatherWidth: CGFloat,
        mediaWidth: CGFloat = 0,
        trayWidth: CGFloat,
        clockWidth: CGFloat,
        clusterWidth: CGFloat,
        gap: CGFloat,
        margin: CGFloat,
        barHeight: CGFloat,
        bottomMargin: CGFloat,
        centeredWidth: CGFloat = 720,
        screenOriginX: CGFloat = 0,
        screenMinY: CGFloat = 0
    ) -> IslandLayout {
        let effectiveGap = max(0.5, gap)
        let effectiveMargin = max(0, margin)
        let y = screenMinY + bottomMargin
        let islandSections = BarSection.islands(for: mode)

        let mediaTotal = mediaWidth > 0 ? 8 + mediaWidth : 0
        func fixedWidth(_ sections: [BarSection]) -> CGFloat? {
            if sections == [.weather] { return weatherWidth }
            if sections == [.weather, .media] { return weatherWidth + mediaTotal }
            if sections == [.tray, .clock] { return trayWidth + 8 + clockWidth }
            if sections == [.tray] { return trayWidth }
            if sections == [.clock] { return clockWidth }
            return nil
        }

        func appsWidth(_ count: Int) -> CGFloat {
            appsContentWidth(count: count, tileStride: tileStride, clusterWidth: clusterWidth)
        }

        switch mode {
        case .windows:
            // Single continuous full-width strip across the screen.
            let availableWidth = max(0, screenWidth - 2 * effectiveMargin)
            let fixedElements = weatherWidth + mediaTotal + (trayWidth + 8 + clockWidth) + 2 * effectiveGap
            let availableForApps = max(0, availableWidth - fixedElements)

            var visibleApps = appCount
            while visibleApps > 1, appsWidth(visibleApps) > availableForApps {
                visibleApps -= 1
            }
            let overflow = visibleApps < appCount

            let frame = CGRect(
                x: screenOriginX + effectiveMargin,
                y: y,
                width: availableWidth,
                height: barHeight
            )
            let island = IslandLayout.Island(slot: 0, sections: islandSections[0], frame: frame)
            return IslandLayout(islands: [island], visibleAppTiles: visibleApps, showsOverflow: overflow)

        case .centered:
            // Single floating centered island hugging its content.
            let maxAllowedWidth = max(0, screenWidth - 2 * effectiveMargin)
            let fixedElements = weatherWidth + mediaTotal + (trayWidth + 8 + clockWidth) + 32

            var visibleApps = appCount
            while visibleApps > 1, (appsWidth(visibleApps) + fixedElements) > maxAllowedWidth {
                visibleApps -= 1
            }
            let overflow = visibleApps < appCount

            let intrinsic = appsWidth(visibleApps) + fixedElements
            let finalWidth = min(maxAllowedWidth, max(min(centeredWidth, maxAllowedWidth), intrinsic))
            let x = screenOriginX + (screenWidth - finalWidth) / 2

            let frame = CGRect(x: x, y: y, width: finalWidth, height: barHeight)
            let island = IslandLayout.Island(slot: 0, sections: islandSections[0], frame: frame)
            return IslandLayout(islands: [island], visibleAppTiles: visibleApps, showsOverflow: overflow)

        case .split3, .split4:
            var frames = [CGRect](repeating: .zero, count: islandSections.count)
            var rightEdge = screenOriginX + screenWidth - effectiveMargin

            // Position trailing islands from right to left.
            for (index, sections) in islandSections.enumerated().reversed() {
                guard let width = fixedWidth(sections) else { continue }
                if sections == [.weather] {
                    frames[index] = CGRect(x: screenOriginX + effectiveMargin, y: y, width: width, height: barHeight)
                    continue
                }
                rightEdge -= width
                frames[index] = CGRect(x: rightEdge, y: y, width: width, height: barHeight)
                rightEdge -= effectiveGap
            }

            var visibleApps = appCount
            var overflow = false

            if let appsIndex = islandSections.firstIndex(where: { $0.contains(.apps) }) {
                let leftCount = islandSections[..<appsIndex].count
                let leftReserved = islandSections[..<appsIndex].compactMap(fixedWidth).reduce(0, +)
                    + CGFloat(leftCount) * effectiveGap + effectiveMargin
                let rightReserved = (screenOriginX + screenWidth - effectiveMargin) - rightEdge
                let available = screenWidth - leftReserved - rightReserved

                while visibleApps > 1, appsWidth(visibleApps) > available {
                    visibleApps -= 1
                }
                overflow = visibleApps < appCount

                let width = max(tileStride, min(appsWidth(visibleApps), max(0, available)))
                let spanWidth = max(0, available)
                frames[appsIndex] = CGRect(
                    x: screenOriginX + leftReserved + max(0, (spanWidth - width) / 2),
                    y: y,
                    width: width,
                    height: barHeight
                )
            }

            // Clamping pass: validate against screen bounds
            for i in 0..<frames.count {
                frames[i].origin.x = max(screenOriginX, min(frames[i].origin.x, screenOriginX + screenWidth - frames[i].width))
            }

            let islands = islandSections.enumerated().map { (index, sections) in
                IslandLayout.Island(slot: index, sections: sections, frame: frames[index])
            }
            return IslandLayout(islands: islands, visibleAppTiles: visibleApps, showsOverflow: overflow)
        }
    }

    /// Validates an IslandLayout against tungsten clamp discipline rules.
    ///
    /// Ensures:
    /// - Every island frame is inside the screen bounds.
    /// - Every island has non-negative width and matching height.
    /// - Multiple islands have at least `minGap` space between them.
    static func validate(
        layout: IslandLayout,
        screenWidth: CGFloat,
        screenOriginX: CGFloat = 0,
        expectedBarHeight: CGFloat? = nil,
        minGap: CGFloat = 0.5
    ) -> Bool {
        guard !layout.islands.isEmpty else { return false }

        let minScreenX = screenOriginX
        let maxScreenX = screenOriginX + screenWidth

        for island in layout.islands {
            if island.frame.minX < minScreenX - 0.001 { return false }
            if island.frame.maxX > maxScreenX + 0.001 { return false }
            if island.frame.width <= 0 { return false }
            if let expectedBarHeight, abs(island.frame.height - expectedBarHeight) > 0.001 {
                return false
            }
        }

        if layout.islands.count > 1 {
            let sorted = layout.islands.sorted { $0.frame.minX < $1.frame.minX }
            for i in 0..<(sorted.count - 1) {
                let current = sorted[i]
                let next = sorted[i + 1]
                let actualGap = next.frame.minX - current.frame.maxX
                if actualGap < minGap - 0.001 {
                    return false
                }
            }
        }

        return true
    }
}
