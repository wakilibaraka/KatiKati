import CoreGraphics
import Foundation

enum DesktopScreenEdge: String, Codable, CaseIterable, Sendable {
    case left
    case right
    case top
    case bottom
}

enum DesktopCapsuleMode: Codable, Equatable, Sendable {
    case expanded
    case capsule
    case edgeDocked(edge: DesktopScreenEdge)

    private enum CodingKeys: String, CodingKey {
        case type, edge
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decodeIfPresent(String.self, forKey: .type) ?? "expanded"
        switch type {
        case "capsule":
            self = .capsule
        case "edgeDocked":
            let rawEdge = try c.decodeIfPresent(String.self, forKey: .edge) ?? DesktopScreenEdge.right.rawValue
            self = .edgeDocked(edge: DesktopScreenEdge(rawValue: rawEdge) ?? .right)
        default:
            self = .expanded
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .expanded:
            try c.encode("expanded", forKey: .type)
        case .capsule:
            try c.encode("capsule", forKey: .type)
        case .edgeDocked(let edge):
            try c.encode("edgeDocked", forKey: .type)
            try c.encode(edge.rawValue, forKey: .edge)
        }
    }
}

enum DesktopCapsuleLayout {
    static let standardCapsuleSize = CGSize(width: 150, height: 32)
    static let dockedEdgeThickness: CGFloat = 34
    static let dockedEdgePeekMargin: CGFloat = 4

    /// Calculates the compact pill frame when in floating capsule mode, anchored to the top-left of the expanded frame.
    static func capsuleFrame(for expandedFrame: CGRect, visibleFrame: CGRect, edgeMargin: CGFloat = 12) -> CGRect {
        let size = standardCapsuleSize
        var origin = CGPoint(x: expandedFrame.origin.x, y: expandedFrame.origin.y + expandedFrame.height - size.height)

        let minX = visibleFrame.minX + edgeMargin
        let maxX = visibleFrame.maxX - edgeMargin - size.width
        let minY = visibleFrame.minY + edgeMargin
        let maxY = visibleFrame.maxY - edgeMargin - size.height

        if maxX >= minX { origin.x = min(max(origin.x, minX), maxX) }
        if maxY >= minY { origin.y = min(max(origin.y, minY), maxY) }

        return CGRect(origin: origin, size: size)
    }

    /// Calculates the edge-docked pill frame flush or peeking along the target screen edge.
    static func dockedFrame(
        edge: DesktopScreenEdge,
        positionRatio: CGFloat,
        visibleFrame: CGRect
    ) -> CGRect {
        let ratio = min(max(positionRatio, 0.05), 0.95)
        switch edge {
        case .left:
            let width = standardCapsuleSize.width
            let height = standardCapsuleSize.height
            let y = visibleFrame.minY + (visibleFrame.height - height) * ratio
            return CGRect(x: visibleFrame.minX + dockedEdgePeekMargin, y: y, width: width, height: height)
        case .right:
            let width = standardCapsuleSize.width
            let height = standardCapsuleSize.height
            let x = visibleFrame.maxX - width - dockedEdgePeekMargin
            let y = visibleFrame.minY + (visibleFrame.height - height) * ratio
            return CGRect(x: x, y: y, width: width, height: height)
        case .top:
            let width = standardCapsuleSize.width
            let height = standardCapsuleSize.height
            let x = visibleFrame.minX + (visibleFrame.width - width) * ratio
            let y = visibleFrame.maxY - height - dockedEdgePeekMargin
            return CGRect(x: x, y: y, width: width, height: height)
        case .bottom:
            let width = standardCapsuleSize.width
            let height = standardCapsuleSize.height
            let x = visibleFrame.minX + (visibleFrame.width - width) * ratio
            let y = visibleFrame.minY + dockedEdgePeekMargin
            return CGRect(x: x, y: y, width: width, height: height)
        }
    }

    /// Determines the expanded placement when a capsule or edge-docked pill expands.
    static func expandedFrame(
        from capsuleFrame: CGRect,
        originalSize: CGSize,
        dockedEdge: DesktopScreenEdge?,
        visibleFrame: CGRect,
        edgeMargin: CGFloat = 12
    ) -> CGRect {
        let w = max(originalSize.width, 180)
        let h = max(originalSize.height, 120)

        var x: CGFloat
        var y: CGFloat

        if let edge = dockedEdge {
            switch edge {
            case .left:
                x = visibleFrame.minX + edgeMargin
                y = capsuleFrame.midY - h / 2
            case .right:
                x = visibleFrame.maxX - edgeMargin - w
                y = capsuleFrame.midY - h / 2
            case .top:
                x = capsuleFrame.midX - w / 2
                y = visibleFrame.maxY - edgeMargin - h
            case .bottom:
                x = capsuleFrame.midX - w / 2
                y = visibleFrame.minY + edgeMargin
            }
        } else {
            // Floating capsule expands downward-right from top-left, or clamps into visible bounds
            x = capsuleFrame.minX
            y = capsuleFrame.maxY - h
        }

        let minX = visibleFrame.minX + edgeMargin
        let maxX = visibleFrame.maxX - edgeMargin - w
        let minY = visibleFrame.minY + edgeMargin
        let maxY = visibleFrame.maxY - edgeMargin - h

        if maxX >= minX { x = min(max(x, minX), maxX) } else { x = minX }
        if maxY >= minY { y = min(max(y, minY), maxY) } else { y = minY }

        return CGRect(x: x, y: y, width: w, height: h)
    }
}

enum DesktopCapsuleHoverPolicy {
    /// Pure policy governing interaction-locked hover expansion.
    /// Returns true if the widget must stay expanded.
    static func shouldRemainExpanded(
        isHovered: Bool,
        activeLocks: Set<DesktopInteractionLock>
    ) -> Bool {
        if !activeLocks.isEmpty {
            // Held locks (e.g. text input, context menu, popover, drag) freeze the expanded state.
            return true
        }
        return isHovered
    }
}
