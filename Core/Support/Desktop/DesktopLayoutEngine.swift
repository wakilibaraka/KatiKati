import CoreGraphics
import Foundation

enum DesktopResizeHandle: CaseIterable, Sendable {
    case top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight

    var adjustsMinX: Bool { self == .left || self == .topLeft || self == .bottomLeft }
    var adjustsMaxX: Bool { self == .right || self == .topRight || self == .bottomRight }
    var adjustsMinY: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }
    var adjustsMaxY: Bool { self == .top || self == .topLeft || self == .topRight }
}

struct DesktopSnapResult: Equatable, Sendable {
    let frame: CGRect
    let snappedX: CGFloat?
    let snappedY: CGFloat?
}

/// Pure geometry engine for desktop widgets in AppKit screen coordinates (+X right, +Y up).
enum DesktopLayoutEngine {
    static func insetBounds(for visibleFrame: CGRect, edgeMargin: CGFloat) -> CGRect {
        let margin = max(0, edgeMargin)
        let maxXMargin = max(0, (visibleFrame.width - DesktopWidgetItem.minimumSize.width) / 2)
        let maxYMargin = max(0, (visibleFrame.height - DesktopWidgetItem.minimumSize.height) / 2)
        return visibleFrame.insetBy(dx: min(margin, maxXMargin), dy: min(margin, maxYMargin))
    }

    static func clamp(
        _ frame: CGRect,
        in visibleFrame: CGRect,
        edgeMargin: CGFloat,
        minSize: CGSize = DesktopWidgetItem.minimumSize
    ) -> CGRect {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else { return frame }
        let bounds = insetBounds(for: visibleFrame, edgeMargin: edgeMargin)
        let width = min(max(frame.width, minSize.width), max(minSize.width, bounds.width))
        let height = min(max(frame.height, minSize.height), max(minSize.height, bounds.height))
        let x = min(max(frame.minX, bounds.minX), max(bounds.minX, bounds.maxX - width))
        let y = min(max(frame.minY, bounds.minY), max(bounds.minY, bounds.maxY - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func snapMove(
        candidate: CGRect,
        others: [CGRect],
        visibleFrame: CGRect,
        gap: CGFloat,
        edgeMargin: CGFloat,
        threshold: CGFloat = 10
    ) -> DesktopSnapResult {
        let clamped = clamp(candidate, in: visibleFrame, edgeMargin: edgeMargin)
        let bounds = insetBounds(for: visibleFrame, edgeMargin: edgeMargin)
        let gap = max(0, gap)

        var xTargets: [(originX: CGFloat, guide: CGFloat)] = [
            (bounds.minX, bounds.minX),
            (bounds.maxX - clamped.width, bounds.maxX)
        ]
        var yTargets: [(originY: CGFloat, guide: CGFloat)] = [
            (bounds.minY, bounds.minY),
            (bounds.maxY - clamped.height, bounds.maxY)
        ]

        for other in others {
            xTargets.append((other.minX, other.minX))
            xTargets.append((other.maxX - clamped.width, other.maxX))
            xTargets.append((other.maxX + gap, other.maxX + gap))
            xTargets.append((other.minX - gap - clamped.width, other.minX - gap))

            yTargets.append((other.minY, other.minY))
            yTargets.append((other.maxY - clamped.height, other.maxY))
            yTargets.append((other.maxY + gap, other.maxY + gap))
            yTargets.append((other.minY - gap - clamped.height, other.minY - gap))
        }

        let bestX = closestSnap(current: clamped.minX, targets: xTargets, threshold: threshold)
        let bestY = closestSnap(current: clamped.minY, targets: yTargets, threshold: threshold)

        let moved = CGRect(
            x: bestX?.value ?? clamped.minX,
            y: bestY?.value ?? clamped.minY,
            width: clamped.width,
            height: clamped.height
        )
        let finalFrame = clamp(moved, in: visibleFrame, edgeMargin: edgeMargin)
        return DesktopSnapResult(
            frame: finalFrame,
            snappedX: bestX != nil ? bestX?.guide : nil,
            snappedY: bestY != nil ? bestY?.guide : nil
        )
    }

    static func snapResize(
        origin: CGRect,
        handle: DesktopResizeHandle,
        delta: CGSize,
        others: [CGRect],
        visibleFrame: CGRect,
        gap: CGFloat,
        edgeMargin: CGFloat,
        minSize: CGSize = DesktopWidgetItem.minimumSize,
        threshold: CGFloat = 10
    ) -> DesktopSnapResult {
        let bounds = insetBounds(for: visibleFrame, edgeMargin: edgeMargin)
        let gap = max(0, gap)
        var minX = origin.minX
        var maxX = origin.maxX
        var minY = origin.minY
        var maxY = origin.maxY
        var snappedX: CGFloat?
        var snappedY: CGFloat?

        if handle.adjustsMinX {
            let raw = min(origin.minX + delta.width, maxX - minSize.width)
            let targets = horizontalEdgeTargets(bounds: bounds, others: others, gap: gap, isMinEdge: true)
            if let snap = closestEdge(current: raw, targets: targets, threshold: threshold),
               maxX - snap >= minSize.width, snap >= bounds.minX {
                minX = snap
                snappedX = snap
            } else {
                minX = max(bounds.minX, min(raw, maxX - minSize.width))
            }
        } else if handle.adjustsMaxX {
            let raw = max(origin.maxX + delta.width, minX + minSize.width)
            let targets = horizontalEdgeTargets(bounds: bounds, others: others, gap: gap, isMinEdge: false)
            if let snap = closestEdge(current: raw, targets: targets, threshold: threshold),
               snap - minX >= minSize.width, snap <= bounds.maxX {
                maxX = snap
                snappedX = snap
            } else {
                maxX = min(bounds.maxX, max(raw, minX + minSize.width))
            }
        }

        if handle.adjustsMinY {
            let raw = min(origin.minY + delta.height, maxY - minSize.height)
            let targets = verticalEdgeTargets(bounds: bounds, others: others, gap: gap, isMinEdge: true)
            if let snap = closestEdge(current: raw, targets: targets, threshold: threshold),
               maxY - snap >= minSize.height, snap >= bounds.minY {
                minY = snap
                snappedY = snap
            } else {
                minY = max(bounds.minY, min(raw, maxY - minSize.height))
            }
        } else if handle.adjustsMaxY {
            let raw = max(origin.maxY + delta.height, minY + minSize.height)
            let targets = verticalEdgeTargets(bounds: bounds, others: others, gap: gap, isMinEdge: false)
            if let snap = closestEdge(current: raw, targets: targets, threshold: threshold),
               snap - minY >= minSize.height, snap <= bounds.maxY {
                maxY = snap
                snappedY = snap
            } else {
                maxY = min(bounds.maxY, max(raw, minY + minSize.height))
            }
        }

        let resized = CGRect(x: minX, y: minY, width: max(minSize.width, maxX - minX), height: max(minSize.height, maxY - minY))
        return DesktopSnapResult(
            frame: clamp(resized, in: visibleFrame, edgeMargin: edgeMargin, minSize: minSize),
            snappedX: snappedX,
            snappedY: snappedY
        )
    }

    /// Moves all widgets in `frames` by a shared `delta`, clamped as one bounding union inside `visibleFrame`.
    static func boundedGroupMove(
        frames: [UUID: CGRect],
        delta: CGSize,
        visibleFrame: CGRect,
        edgeMargin: CGFloat
    ) -> [UUID: CGRect] {
        guard !frames.isEmpty, visibleFrame.width > 0, visibleFrame.height > 0 else { return frames }
        let bounds = insetBounds(for: visibleFrame, edgeMargin: edgeMargin)
        var union = CGRect.null
        for rect in frames.values { union = union.union(rect) }

        let minDX = bounds.minX - union.minX
        let maxDX = bounds.maxX - union.maxX
        let dx = minDX <= maxDX ? min(max(delta.width, minDX), maxDX) : 0

        let minDY = bounds.minY - union.minY
        let maxDY = bounds.maxY - union.maxY
        let dy = minDY <= maxDY ? min(max(delta.height, minDY), maxDY) : 0

        return frames.mapValues { $0.offsetBy(dx: dx, dy: dy) }
    }

    static func normalize(_ frame: CGRect, in visibleFrame: CGRect) -> NormalizedWidgetRect {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else {
            return NormalizedWidgetRect(x: 0.1, y: 0.1, width: 0.2, height: 0.25)
        }
        return NormalizedWidgetRect(
            x: (frame.minX - visibleFrame.minX) / visibleFrame.width,
            y: (frame.minY - visibleFrame.minY) / visibleFrame.height,
            width: frame.width / visibleFrame.width,
            height: frame.height / visibleFrame.height
        )
    }

    static func denormalize(
        _ norm: NormalizedWidgetRect,
        in visibleFrame: CGRect,
        edgeMargin: CGFloat,
        minSize: CGSize = DesktopWidgetItem.minimumSize
    ) -> CGRect {
        let raw = CGRect(
            x: visibleFrame.minX + norm.x * visibleFrame.width,
            y: visibleFrame.minY + norm.y * visibleFrame.height,
            width: norm.width * visibleFrame.width,
            height: norm.height * visibleFrame.height
        )
        return clamp(raw, in: visibleFrame, edgeMargin: edgeMargin, minSize: minSize)
    }

    static func resolveDisplay(
        for item: DesktopWidgetItem,
        table: WindowDisplayAttribution.Table
    ) -> WindowDisplayAttribution.Display? {
        if !item.followMainDisplay, let uuid = item.displayUUID,
           let matched = table.displays.first(where: { $0.uuid == uuid }) {
            return matched
        }
        if let primary = table.primaryUUID,
           let matched = table.displays.first(where: { $0.uuid == primary }) {
            return matched
        }
        return table.displays.first
    }

    /// Picks a non-overlapping cascade slot starting near top-right of `visibleFrame`.
    static func initialPlacement(
        existing: [CGRect],
        size: CGSize = DesktopWidgetItem.defaultFolderSize,
        visibleFrame: CGRect,
        gap: CGFloat,
        edgeMargin: CGFloat
    ) -> CGRect {
        let bounds = insetBounds(for: visibleFrame, edgeMargin: edgeMargin)
        let step = max(24, gap + 20)
        for index in 0..<12 {
            let offset = CGFloat(index) * step
            let candidate = CGRect(
                x: bounds.maxX - size.width - offset,
                y: bounds.maxY - size.height - offset,
                width: size.width,
                height: size.height
            )
            let clamped = clamp(candidate, in: visibleFrame, edgeMargin: edgeMargin)
            if !existing.contains(where: { $0.intersects(clamped) }) {
                return clamped
            }
        }
        return clamp(
            CGRect(x: bounds.minX, y: bounds.maxY - size.height, width: size.width, height: size.height),
            in: visibleFrame,
            edgeMargin: edgeMargin
        )
    }

    private static func closestSnap(
        current: CGFloat,
        targets: [(CGFloat, CGFloat)],
        threshold: CGFloat
    ) -> (value: CGFloat, guide: CGFloat)? {
        var best: (value: CGFloat, guide: CGFloat, distance: CGFloat)?
        for (value, guide) in targets {
            let d = abs(current - value)
            guard d <= threshold else { continue }
            if best == nil || d < best!.distance { best = (value, guide, d) }
        }
        return best.map { ($0.value, $0.guide) }
    }

    private static func closestEdge(current: CGFloat, targets: [CGFloat], threshold: CGFloat) -> CGFloat? {
        var bestValue: CGFloat?
        var bestDistance = threshold + 1
        for target in targets {
            let d = abs(current - target)
            if d <= threshold && d < bestDistance {
                bestDistance = d
                bestValue = target
            }
        }
        return bestValue
    }

    private static func horizontalEdgeTargets(
        bounds: CGRect, others: [CGRect], gap: CGFloat, isMinEdge: Bool
    ) -> [CGFloat] {
        var list = [isMinEdge ? bounds.minX : bounds.maxX]
        for o in others {
            list.append(contentsOf: isMinEdge ? [o.minX, o.maxX + gap] : [o.maxX, o.minX - gap])
        }
        return list
    }

    private static func verticalEdgeTargets(
        bounds: CGRect, others: [CGRect], gap: CGFloat, isMinEdge: Bool
    ) -> [CGFloat] {
        var list = [isMinEdge ? bounds.minY : bounds.maxY]
        for o in others {
            list.append(contentsOf: isMinEdge ? [o.minY, o.maxY + gap] : [o.maxY, o.minY - gap])
        }
        return list
    }
}
