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
        widgetOrder: [BarSection] = BarSection.canonicalOrder,
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
            case .media, .launcher, .widgets: return section.defaultWidgetWidth

            case .apps: return 0
            }
        }

        func sectionsWidth(_ sections: [BarSection]) -> (total: CGFloat, count: Int) {
            let widths = sections.filter { $0 != .apps }.map(width(for:)).filter { $0 > 0 }
            return (widths.reduce(0, +), widths.count)
        }

        // Single-island modes: the older 8 pt inner-gap estimate (Phase 11b reworks these).
        func fixedWidth(_ sections: [BarSection]) -> CGFloat? {
            if sections.contains(.apps) { return nil }
            let (total, count) = sectionsWidth(sections)
            return count > 0 ? total + CGFloat(count - 1) * 8 : total
        }

        let chromeScale = IslandChrome.scale(barHeight: barHeight)

        // Split modes: the width the strip really draws — content insets + dividers (Phase 11a).
        func fixedIslandWidth(_ sections: [BarSection]) -> CGFloat {
            let (total, count) = sectionsWidth(sections)
            return IslandChrome.fixedIslandWidth(contentWidth: total, sectionCount: count, scale: chromeScale)
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

        case .split3, .split4, .split5:
            var frames = [CGRect](repeating: .zero, count: islandSections.count)
            let appsIndex = islandSections.firstIndex(where: { $0.contains(.apps) }) ?? 0
            let hasApps = islandSections.indices.contains(appsIndex) && islandSections[appsIndex].contains(.apps)

            // Overlap resolution (Phase 11a): the fixed islands plus the smallest apps island
            // must fit the span. First collapse the gaps to their minimum, then shrink the fixed
            // islands proportionally (their content scrolls inside). Islands never overlap.
            var fixedWidths = islandSections.map { $0.contains(.apps) ? 0 : fixedIslandWidth($0) }
            let span = max(0, screenWidth - 2 * effectiveMargin)
            let gapCount = CGFloat(max(0, islandSections.count - 1))
            let minApps = hasApps ? min(appsWidth(1), span) : 0
            var islandGap = effectiveGap
            func required() -> CGFloat { fixedWidths.reduce(0, +) + gapCount * islandGap + minApps }
            if required() > span { islandGap = 0.5 }
            let fixedTotal = fixedWidths.reduce(0, +)
            if required() > span, fixedTotal > 0 {
                let shrink = max(0, (span - minApps - gapCount * islandGap) / fixedTotal)
                fixedWidths = fixedWidths.map { $0 * shrink }
            }

            // Position leading islands from left to right.
            var leftEdge = screenOriginX + effectiveMargin
            for index in 0..<appsIndex {
                let width = fixedWidths[index]
                frames[index] = CGRect(x: leftEdge, y: y, width: width, height: barHeight)
                leftEdge += width + islandGap
            }

            // Position trailing islands from right to left.
            var rightEdge = screenOriginX + screenWidth - effectiveMargin
            for index in stride(from: islandSections.count - 1, through: appsIndex + 1, by: -1) {
                let width = fixedWidths[index]
                rightEdge -= width
                frames[index] = CGRect(x: rightEdge, y: y, width: width, height: barHeight)
                rightEdge -= islandGap
            }

            var visibleApps = appCount
            var overflow = false

            if hasApps {
                // The apps island stays screen-centred while it fits; with lopsided widget groups
                // it slides toward the roomier side instead of dropping tiles early.
                let available = max(0, rightEdge - leftEdge)
                while visibleApps > 1, appsWidth(visibleApps) > available {
                    visibleApps -= 1
                }
                overflow = visibleApps < appCount

                let width = min(appsWidth(visibleApps), available)
                let centredX = screenOriginX + (screenWidth - width) / 2
                let x = min(max(centredX, leftEdge), rightEdge - width)
                frames[appsIndex] = CGRect(x: x, y: y, width: width, height: barHeight)
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

/// Chrome `DockStripView` draws around and between a fixed island's sections: the horizontal
/// content inset at both ends and a divider gap between neighbouring sections, both scaled with
/// the bar height. The solver sizes fixed islands with it so a frame never clips its own content
/// (Phase 11a: split islands were 8 pt-gap estimates, ~45 pt narrower than what the strip drew).
enum IslandChrome {
    /// `DockStripView.Style.chipContentInset` at native scale.
    static let contentInset: CGFloat = 20
    /// Divider gap between sections inside one island (`StripContextMenuZone.dividerGapWidth`).
    static let dividerGap: CGFloat = StripContextMenuZone.dividerGapWidth
    /// The bar height `dockScale` is measured against (`DockPanelHeight.native`).
    static let nativeBarHeight: CGFloat = 54

    static func scale(barHeight: CGFloat) -> CGFloat {
        barHeight / nativeBarHeight
    }

    static func fixedIslandWidth(contentWidth: CGFloat, sectionCount: Int, scale: CGFloat) -> CGFloat {
        guard sectionCount > 0 else { return 0 }
        return contentWidth + 2 * contentInset * scale + CGFloat(sectionCount - 1) * dividerGap * scale
    }

    /// Chrome + island gaps a mode spends besides the widget widths themselves; feeds the widget
    /// auto-degrade budget so L→M→S kicks in before islands would collide.
    static func overhead(mode: BarLayoutMode, order: [BarSection], gap: CGFloat, scale: CGFloat) -> CGFloat {
        let islands = BarSection.islands(for: mode, order: order)
        var total = CGFloat(max(0, islands.count - 1)) * max(0.5, gap)
        for sections in islands {
            let widgets = sections.filter { $0 != .apps }.count
            if sections.contains(.apps) {
                total += CGFloat(widgets) * dividerGap * scale
            } else if widgets > 0 {
                total += fixedIslandWidth(contentWidth: 0, sectionCount: widgets, scale: scale)
            }
        }
        return total
    }
}

