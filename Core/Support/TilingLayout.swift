import CoreGraphics
import Foundation

/// Available auto-tiling layout presets (Phase 26b).
enum TilingLayoutPreset: String, CaseIterable, Sendable, Codable {
    /// Binary Space Partitioning: recursive alternating splits.
    case bsp
    /// Master-Stack: primary window on the left, stack on the right.
    case mainStack
    /// Monocle: every window occupies the full work area.
    case monocle
    /// Grid: windows fill rows of near-equal cells.
    case grid
    /// Spiral (dwindle): each window takes half of the space left, alternating direction.
    case spiral
    /// Columns: equal-width full-height slices.
    case columns
    /// Rows: equal-height full-width slices.
    case rows
    /// Centered Main: primary window in the middle, the rest split to either side.
    case centeredMain

    var localizedTitleKey: String {
        switch self {
        case .bsp: return "BSP"
        case .mainStack: return "Main + Stack"
        case .monocle: return "Monocle"
        case .grid: return "Grid"
        case .spiral: return "Spiral"
        case .columns: return "Columns"
        case .rows: return "Rows"
        case .centeredMain: return "Centered Main"
        }
    }
}

/// Geometry solver for auto-tiling presets (Phase 26b).
enum TilingLayout {
    /// Resolves target frames for all windows in `tree` according to `preset`.
    /// Cocoa coordinates (bottom-left origin).
    static func resolve(
        tree: TilingTree,
        preset: TilingLayoutPreset,
        workArea: CGRect,
        gaps: TilingGaps = .default
    ) -> [WindowID: CGRect] {
        guard !tree.isEmpty else { return [:] }

        switch preset {
        case .bsp:
            return tree.resolveTiles(in: workArea, gaps: gaps)

        case .mainStack:
            return resolveMainStack(tree: tree, workArea: workArea, gaps: gaps)

        case .monocle:
            return resolveMonocle(tree: tree, workArea: workArea, gaps: gaps)

        case .grid, .spiral, .columns, .rows, .centeredMain:
            return resolveSliced(tree: tree, preset: preset, workArea: workArea, gaps: gaps)
        }
    }

    // MARK: - Main + Stack Preset

    private static func resolveMainStack(
        tree: TilingTree,
        workArea: CGRect,
        gaps: TilingGaps
    ) -> [WindowID: CGRect] {
        let windows = tree.allWindowIDs
        guard !windows.isEmpty else { return [:] }

        let outer = gaps.outer
        let contentArea = CGRect(
            x: workArea.minX + outer,
            y: workArea.minY + outer,
            width: max(0, workArea.width - 2 * outer),
            height: max(0, workArea.height - 2 * outer)
        )

        // Single window fills the content area
        if windows.count == 1 {
            return [windows[0]: pixelAligned(contentArea)]
        }

        var result: [WindowID: CGRect] = [:]
        let inner = gaps.inner
        let mainRatio: CGFloat = 0.55

        let availableWidth = max(0, contentArea.width - inner)
        let mainWidth = (availableWidth * mainRatio).rounded()
        let stackWidth = max(0, availableWidth - mainWidth)

        // Main window (left side)
        let mainRect = CGRect(
            x: contentArea.minX,
            y: contentArea.minY,
            width: mainWidth,
            height: contentArea.height
        )
        result[windows[0]] = pixelAligned(mainRect)

        // Stack windows (right side, divided vertically)
        let stackCount = windows.count - 1
        let totalInnerGaps = CGFloat(stackCount - 1) * inner
        let availableHeight = max(0, contentArea.height - totalInnerGaps)
        let eachHeight = (availableHeight / CGFloat(stackCount)).rounded()

        let stackX = contentArea.minX + mainWidth + inner
        var currentY = contentArea.minY

        // Traverse stack windows bottom-to-top so top window lands at maxY
        for i in (1...stackCount).reversed() {
            let winID = windows[i]
            let isLast = (i == 1) // topmost window gets any remainder
            let height = isLast ? (contentArea.maxY - currentY) : eachHeight

            let tileRect = CGRect(
                x: stackX,
                y: currentY,
                width: stackWidth,
                height: max(1, height)
            )
            result[winID] = pixelAligned(tileRect)
            currentY += height + inner
        }

        return result
    }

    // MARK: - Monocle Preset

    private static func resolveMonocle(
        tree: TilingTree,
        workArea: CGRect,
        gaps: TilingGaps
    ) -> [WindowID: CGRect] {
        let outer = gaps.outer
        let contentArea = pixelAligned(CGRect(
            x: workArea.minX + outer,
            y: workArea.minY + outer,
            width: max(0, workArea.width - 2 * outer),
            height: max(0, workArea.height - 2 * outer)
        ))

        var result: [WindowID: CGRect] = [:]
        for id in tree.allWindowIDs {
            result[id] = contentArea
        }
        return result
    }

    // MARK: - Grid / Spiral / Columns / Rows / Centered Main

    private static func resolveSliced(
        tree: TilingTree,
        preset: TilingLayoutPreset,
        workArea: CGRect,
        gaps: TilingGaps
    ) -> [WindowID: CGRect] {
        let windows = tree.allWindowIDs
        let outer = gaps.outer
        let inner = gaps.inner
        let area = CGRect(
            x: workArea.minX + outer, y: workArea.minY + outer,
            width: max(0, workArea.width - 2 * outer), height: max(0, workArea.height - 2 * outer)
        )
        let n = windows.count
        var frames: [CGRect] = []

        switch preset {
        case .columns:
            frames = split(area, count: n, horizontal: true, gap: inner)
        case .rows:
            frames = split(area, count: n, horizontal: false, gap: inner)
        case .grid:
            let cols = Int(ceil(Double(n).squareRoot()))
            let rowCount = Int(ceil(Double(n) / Double(cols)))
            for (r, row) in split(area, count: rowCount, horizontal: false, gap: inner).enumerated() {
                frames += split(row, count: min(cols, n - r * cols), horizontal: true, gap: inner)
            }
        case .spiral:
            var rest = area
            for i in 0..<n {
                if i == n - 1 { frames.append(rest); break }
                let parts = split(rest, count: 2, horizontal: i % 2 == 0, gap: inner)
                frames.append(parts[0])
                rest = parts[1]
            }
        case .centeredMain:
            if n <= 2 {
                frames = split(area, count: n, horizontal: true, gap: inner)
                break
            }
            // Main in the middle (half the width); others alternate right, left.
            let sideW = max(0, (area.width - area.width * 0.5 - 2 * inner) / 2)
            let mainW = max(0, area.width - 2 * sideW - 2 * inner)
            let rightCount = n / 2, leftCount = n - 1 - rightCount
            let left = CGRect(x: area.minX, y: area.minY, width: sideW, height: area.height)
            let mid = CGRect(x: left.maxX + inner, y: area.minY, width: mainW, height: area.height)
            let right = CGRect(x: mid.maxX + inner, y: area.minY, width: sideW, height: area.height)
            let rights = split(right, count: rightCount, horizontal: false, gap: inner)
            let lefts = split(left, count: leftCount, horizontal: false, gap: inner)
            frames = [mid]
            for i in 0..<(n - 1) { frames.append(i % 2 == 0 ? rights[i / 2] : lefts[i / 2]) }
        default:
            break
        }

        var result: [WindowID: CGRect] = [:]
        for (id, frame) in zip(windows, frames) { result[id] = pixelAligned(frame) }
        return result
    }

    /// Splits `rect` into `count` equal slices: left→right, or top→bottom (Cocoa: top has the highest y).
    private static func split(_ rect: CGRect, count: Int, horizontal: Bool, gap: CGFloat) -> [CGRect] {
        guard count > 0 else { return [] }
        let total = horizontal ? rect.width : rect.height
        let each = max(0, total - gap * CGFloat(count - 1)) / CGFloat(count)
        return (0..<count).map { i in
            let offset = CGFloat(i) * (each + gap)
            return horizontal
                ? CGRect(x: rect.minX + offset, y: rect.minY, width: each, height: rect.height)
                : CGRect(x: rect.minX, y: rect.maxY - offset - each, width: rect.width, height: each)
        }
    }

    private static func pixelAligned(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX.rounded(),
            y: rect.minY.rounded(),
            width: max(1, rect.width.rounded()),
            height: max(1, rect.height.rounded())
        )
    }
}
