import CoreGraphics

/// Window zones for the Windows flyout (Phase 7A-P6). The unit rectangles follow the window snapper cited in NOTICE §9 (MIT):
/// fractions of a screen's visible area with a bottom-left origin.
enum SnapPosition: String, CaseIterable, Codable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case center, maximize

    var unit: CGRect {
        let t = 1.0 / 3
        switch self {
        case .leftHalf: return CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: return CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf: return CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .bottomHalf: return CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .topLeft: return CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .topRight: return CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .bottomLeft: return CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .bottomRight: return CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .leftThird: return CGRect(x: 0, y: 0, width: t, height: 1)
        case .centerThird: return CGRect(x: t, y: 0, width: t, height: 1)
        case .rightThird: return CGRect(x: 2 * t, y: 0, width: t, height: 1)
        case .leftTwoThirds: return CGRect(x: 0, y: 0, width: 2 * t, height: 1)
        case .rightTwoThirds: return CGRect(x: t, y: 0, width: 2 * t, height: 1)
        case .center: return CGRect(x: 0.125, y: 0.1, width: 0.75, height: 0.8)
        case .maximize: return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
    }

    /// Target frame inside `visible` (Cocoa coordinates, bottom-left origin), whole points.
    func frame(in visible: CGRect) -> CGRect {
        let u = unit
        return CGRect(x: (visible.minX + u.minX * visible.width).rounded(),
                      y: (visible.minY + u.minY * visible.height).rounded(),
                      width: (u.width * visible.width).rounded(),
                      height: (u.height * visible.height).rounded())
    }

    /// Cocoa frame → Accessibility coordinates (origin at the top-left of the primary screen).
    static func accessibilityOrigin(of cocoa: CGRect, primaryMaxY: CGFloat) -> CGPoint {
        CGPoint(x: cocoa.minX, y: primaryMaxY - cocoa.maxY)
    }
}

// MARK: - Window Management revamp — snap planning and green button policy

/// How the green traffic-light click should behave. The existing FullscreenIntentMonitor tap is
/// the only place an opt-in hook will consult this; the pure model stays UI-free.
enum GreenButtonBehavior: String, CaseIterable, Codable, Sendable, Identifiable {
    case nativeFullscreen
    case maximizeInCurrentSpace

    static let defaultValue: Self = .nativeFullscreen

    var id: String { rawValue }

    var usesNativeFullscreen: Bool { self == .nativeFullscreen }
}

/// Drag-snap ghost treatment. `.off` still snaps on release but draws no preview.
enum SnapPreviewStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case outline
    case filled
    case off

    var id: String { rawValue }

    var drawsPreview: Bool { self != .off }
}

/// Pure edge/corner hit testing and preview geometry for the drag-to-edge surface. It intentionally
/// only resolves edge/corner zones; center, maximize and thirds are exposed through `previewFrame`
/// and the named zone list so keyboard/radial surfaces reuse the same geometry.
enum SnapZonePlanner {
    enum Layout: String, CaseIterable, Codable, Sendable {
        case edgesAndCorners
        case thirds
        case centerAndMaximize
    }

    struct Zone: Equatable, Sendable {
        let position: SnapPosition
        let frame: CGRect
    }

    static func zones(in area: CGRect, layout: Layout = .edgesAndCorners) -> [Zone] {
        let positions: [SnapPosition]
        switch layout {
        case .edgesAndCorners:
            positions = [.leftHalf, .rightHalf, .topHalf, .bottomHalf,
                         .topLeft, .topRight, .bottomLeft, .bottomRight]
        case .thirds:
            positions = [.leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds]
        case .centerAndMaximize:
            positions = [.center, .maximize]
        }
        return positions.map { Zone(position: $0, frame: previewFrame(for: $0, in: area)) }
    }

    static func previewFrame(for position: SnapPosition, in area: CGRect) -> CGRect {
        position.frame(in: area)
    }

    /// Pointer-to-zone resolver for a display work area. Edge layouts require the pointer to be
    /// inside `edgeMargin`; thirds always resolve once inside the area; the center layout prefers
    /// `.center` and falls back to `.maximize` outside the center rect.
    static func resolve(at point: CGPoint,
                        in area: CGRect,
                        layout: Layout = .edgesAndCorners,
                        edgeMargin: CGFloat = 12) -> Zone? {
        guard area.width > 0, area.height > 0 else { return nil }
        switch layout {
        case .edgesAndCorners:
            guard let position = edgeZone(at: point, in: area, edgeMargin: edgeMargin) else { return nil }
            return Zone(position: position, frame: previewFrame(for: position, in: area))
        case .thirds:
            guard area.contains(point) else { return nil }
            let fraction = (point.x - area.minX) / area.width
            let position: SnapPosition = fraction < 1 / 3 ? .leftThird
                : fraction > 2 / 3 ? .rightThird : .centerThird
            return Zone(position: position, frame: previewFrame(for: position, in: area))
        case .centerAndMaximize:
            guard area.contains(point) else { return nil }
            let center = previewFrame(for: .center, in: area)
            let position: SnapPosition = center.contains(point) ? .center : .maximize
            return Zone(position: position, frame: previewFrame(for: position, in: area))
        }
    }

    /// Resolves a pointer to a half or quarter when it is inside `edgeMargin` of an edge. Returns
    /// nil in the middle so a normal drag never turns into an accidental snap.
    static func edgeZone(at point: CGPoint,
                         in area: CGRect,
                         edgeMargin: CGFloat = 12) -> SnapPosition? {
        guard area.width > 0, area.height > 0 else { return nil }
        let margin = max(0, edgeMargin)
        let bounds = area.insetBy(dx: -margin, dy: -margin)
        guard bounds.contains(point) else { return nil }

        let nearLeft = point.x <= area.minX + margin
        let nearRight = point.x >= area.maxX - margin
        let nearTop = point.y >= area.maxY - margin
        let nearBottom = point.y <= area.minY + margin

        if nearLeft {
            if nearTop { return .topLeft }
            if nearBottom { return .bottomLeft }
            return .leftHalf
        }
        if nearRight {
            if nearTop { return .topRight }
            if nearBottom { return .bottomRight }
            return .rightHalf
        }
        if nearTop { return .topHalf }
        if nearBottom { return .bottomHalf }
        return nil
    }
}

/// Which display a window moves to when a gesture asks for the next or previous one.
enum DisplayMove {
    /// `step` displays along the live order, wrapping both ways so a gesture can send a window back.
    /// A single display, or an index outside it, stays where it is rather than pointing at nothing.
    static func destination(from index: Int, count: Int, step: Int) -> Int {
        guard count > 0, index >= 0, index < count else { return index }
        return ((index + step) % count + count) % count
    }
}
