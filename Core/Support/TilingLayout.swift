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

    var localizedTitleKey: String {
        switch self {
        case .bsp: return "BSP"
        case .mainStack: return "Main + Stack"
        case .monocle: return "Monocle"
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

    private static func pixelAligned(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX.rounded(),
            y: rect.minY.rounded(),
            width: max(1, rect.width.rounded()),
            height: max(1, rect.height.rounded())
        )
    }
}
