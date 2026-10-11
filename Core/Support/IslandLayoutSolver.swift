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
        widgetOrder: [BarSection] = [.weather, .apps, .media, .clock],
        widgetWidths: [BarSection: CGFloat] = [:],
        tileStride: CGFloat,
        appCount: Int,
        weatherWidth: CGFloat = 120,
        clockWidth: CGFloat = 160,
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
        let islandSections = BarSection.islands(for: mode, order: widgetOrder)

        func width(for section: BarSection) -> CGFloat {
            // Floor stored overrides at the section's intrinsic minimum, same
            // contract as `AppSettingsStore.setWidgetWidth` — legacy values
            // (e.g. clock = 40 from the old tile layout) starve the chip and
            // render a clipped pill while the island math stays in-bounds.
            if let custom = widgetWidths[section] { return max(custom, section.minimumWidgetWidth) }
            switch section {
            case .weather: return weatherWidth
            case .clock: return clockWidth
            case .media: return section.defaultWidgetWidth

            case .apps: return 0
            }
        }

        func fixedWidth(_ sections: [BarSection]) -> CGFloat? {
            if sections.contains(.apps) { return nil }
            var total: CGFloat = 0
            var count = 0
            for sec in sections {
                let w = width(for: sec)
                if w > 0 {
                    total += w
                    count += 1
                }
            }
            if count > 0 {
                total += CGFloat(count - 1) * 8 // 8 points gap inside an island group
            }
            return total
        }

        func appsWidth(_ count: Int) -> CGFloat {
            appsContentWidth(count: count, tileStride: tileStride, clusterWidth: clusterWidth)
        }

        switch mode {
        case .windows:
            // Single continuous full-width strip across the screen.
            let availableWidth = max(0, screenWidth - 2 * effectiveMargin)
            let allFixedSections = islandSections[0].filter { $0 != .apps }
            let fixedElements = fixedWidth(allFixedSections) ?? 0
            
            // Treat the dividers between fixed sections and apps
            let numberOfGaps = max(0, islandSections[0].count - 1)
            let totalInnerGap = CGFloat(numberOfGaps) * 8
            
            let availableForApps = max(0, availableWidth - (fixedElements + totalInnerGap))

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
            let allFixedSections = islandSections[0].filter { $0 != .apps }
            let fixedElements = fixedWidth(allFixedSections) ?? 0
            
            let numberOfGaps = max(0, islandSections[0].count - 1)
            let totalInnerGap = CGFloat(numberOfGaps) * 8
            
            let totalFixedSpace = fixedElements + totalInnerGap

            var visibleApps = appCount
            while visibleApps > 1, (appsWidth(visibleApps) + totalFixedSpace) > maxAllowedWidth {
                visibleApps -= 1
            }
            let overflow = visibleApps < appCount

            let intrinsic = appsWidth(visibleApps) + totalFixedSpace
            let finalWidth = min(maxAllowedWidth, max(min(centeredWidth, maxAllowedWidth), intrinsic))
            let x = screenOriginX + (screenWidth - finalWidth) / 2

            let frame = CGRect(x: x, y: y, width: finalWidth, height: barHeight)
            let island = IslandLayout.Island(slot: 0, sections: islandSections[0], frame: frame)
            return IslandLayout(islands: [island], visibleAppTiles: visibleApps, showsOverflow: overflow)

        case .split3, .split4:
            var frames = [CGRect](repeating: .zero, count: islandSections.count)
            let appsIndex = islandSections.firstIndex(where: { $0.contains(.apps) }) ?? 0

            // Position leading islands from left to right.
            var leftEdge = screenOriginX + effectiveMargin
            for index in 0..<appsIndex {
                let sections = islandSections[index]
                let width = fixedWidth(sections) ?? 0
                frames[index] = CGRect(x: leftEdge, y: y, width: width, height: barHeight)
                leftEdge += width + effectiveGap
            }

            // Position trailing islands from right to left.
            var rightEdge = screenOriginX + screenWidth - effectiveMargin
            for index in stride(from: islandSections.count - 1, through: appsIndex + 1, by: -1) {
                let sections = islandSections[index]
                let width = fixedWidth(sections) ?? 0
                rightEdge -= width
                frames[index] = CGRect(x: rightEdge, y: y, width: width, height: barHeight)
                rightEdge -= effectiveGap
            }

            var visibleApps = appCount
            var overflow = false

            if appsIndex < islandSections.count {
                let leftReserved = leftEdge - screenOriginX
                let rightReserved = (screenOriginX + screenWidth - effectiveMargin) - rightEdge
                // The Apps island stays strictly centered, but we must make sure it doesn't collide
                // with leftReserved or rightReserved.
                let maxAllowedHalfWidth = (screenWidth / 2) - max(leftReserved, rightReserved) - effectiveGap
                let maxAllowedWidth = max(0, maxAllowedHalfWidth * 2)

                while visibleApps > 1, appsWidth(visibleApps) > maxAllowedWidth {
                    visibleApps -= 1
                }
                overflow = visibleApps < appCount

                let available = screenWidth - leftReserved - rightReserved
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
