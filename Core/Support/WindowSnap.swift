import CoreGraphics
import Foundation

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
}

/// Outer screen-edge margin and inner split-edge gap applied when computing snapped window frames.
struct SnapGaps: Equatable, Sendable {
    static let outerKey = "com.katikati.snap.outerGap"
    static let innerKey = "com.katikati.snap.innerGap"
    static let range: ClosedRange<CGFloat> = 0...32
    static let zero = SnapGaps(outer: 0, inner: 0)

    let outer: CGFloat
    let inner: CGFloat

    init(outer: CGFloat = 0, inner: CGFloat = 0) {
        self.outer = min(max(outer, Self.range.lowerBound), Self.range.upperBound)
        self.inner = min(max(inner, Self.range.lowerBound), Self.range.upperBound)
    }

    static func current(defaults: UserDefaults = .standard) -> SnapGaps {
        SnapGaps(outer: CGFloat(defaults.double(forKey: outerKey)),
                 inner: CGFloat(defaults.double(forKey: innerKey)))
    }
}

extension SnapPosition {
    /// Target frame inside `visible` (Cocoa coordinates, bottom-left origin), whole points.
    func frame(in visible: CGRect, gaps: SnapGaps = .zero) -> CGRect {
        let u = unit
        if gaps == .zero {
            return CGRect(x: (visible.minX + u.minX * visible.width).rounded(),
                          y: (visible.minY + u.minY * visible.height).rounded(),
                          width: (u.width * visible.width).rounded(),
                          height: (u.height * visible.height).rounded())
        }
        let outer = min(gaps.outer, min(visible.width, visible.height) / 4)
        let padded = outer > 0 ? visible.insetBy(dx: outer, dy: outer) : visible
        var minX = padded.minX + u.minX * padded.width
        var maxX = padded.minX + u.maxX * padded.width
        var minY = padded.minY + u.minY * padded.height
        var maxY = padded.minY + u.maxY * padded.height
        if gaps.inner > 0 && self != .center && self != .maximize {
            let half = min(gaps.inner / 2, min(padded.width, padded.height) / 6)
            if u.minX > 0.001 { minX += half }
            if u.maxX < 0.999 { maxX -= half }
            if u.minY > 0.001 { minY += half }
            if u.maxY < 0.999 { maxY -= half }
        }
        let x = minX.rounded()
        let y = minY.rounded()
        return CGRect(x: x,
                      y: y,
                      width: max(0, maxX.rounded() - x),
                      height: max(0, maxY.rounded() - y))
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

    static func zones(in area: CGRect, layout: Layout = .edgesAndCorners, gaps: SnapGaps = .zero) -> [Zone] {
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
        return positions.map { Zone(position: $0, frame: previewFrame(for: $0, in: area, gaps: gaps)) }
    }

    static func previewFrame(for position: SnapPosition, in area: CGRect, gaps: SnapGaps = .zero) -> CGRect {
        position.frame(in: area, gaps: gaps)
    }

    /// Selects the drag-to-snap layout from modifier flags: holding Option (`⌥`) switches to horizontal thirds.
    static func dragLayout(optionDown: Bool) -> Layout {
        optionDown ? .thirds : .edgesAndCorners
    }

    /// Pointer-to-zone resolver for a display work area. Edge layouts require the pointer to be
    /// inside `edgeMargin`; thirds always resolve once inside the area; the center layout prefers
    /// `.center` and falls back to `.maximize` outside the center rect.
    static func resolve(at point: CGPoint,
                        in area: CGRect,
                        layout: Layout = .edgesAndCorners,
                        edgeMargin: CGFloat = 12,
                        gaps: SnapGaps = .zero) -> Zone? {
        guard area.width > 0, area.height > 0 else { return nil }
        switch layout {
        case .edgesAndCorners:
            guard let position = edgeZone(at: point, in: area, edgeMargin: edgeMargin) else { return nil }
            return Zone(position: position, frame: previewFrame(for: position, in: area, gaps: gaps))
        case .thirds:
            guard area.contains(point) else { return nil }
            let fraction = (point.x - area.minX) / area.width
            let position: SnapPosition = fraction < 1 / 3 ? .leftThird
                : fraction > 2 / 3 ? .rightThird : .centerThird
            return Zone(position: position, frame: previewFrame(for: position, in: area, gaps: gaps))
        case .centerAndMaximize:
            guard area.contains(point) else { return nil }
            let center = previewFrame(for: .center, in: area, gaps: gaps)
            let position: SnapPosition = center.contains(point) ? .center : .maximize
            return Zone(position: position, frame: previewFrame(for: position, in: area, gaps: gaps))
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

/// Pure state machine gating drag-to-snap so each press seeds AX window geometry at most once
/// and only arms edge-zone snapping after the focused window's origin actually moves (`>= 2 pt`).
struct SnapDragSession: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case seeding(pressID: UInt64, mouseDown: CGPoint)
        case seeded(pressID: UInt64, initialOrigin: CGPoint)
        case tracking(pressID: UInt64)
        case rejected(pressID: UInt64)
    }

    static let defaultMovementThreshold: CGFloat = 2
    static let seedHitSlop: CGFloat = 8

    private(set) var phase: Phase = .idle
    private var nextPressID: UInt64 = 0
    let movementThreshold: CGFloat

    init(movementThreshold: CGFloat = Self.defaultMovementThreshold) {
        self.movementThreshold = max(0.5, movementThreshold)
    }

    var isIdle: Bool { phase == .idle }

    var isTracking: Bool {
        if case .tracking = phase { return true }
        return false
    }

    var seededPressID: UInt64? {
        if case .seeded(let id, _) = phase { return id }
        return nil
    }

    /// Starts a new press on first drag sample and returns its `pressID` for a single background AX seed.
    @discardableResult
    mutating func beginPress(at mouse: CGPoint) -> UInt64 {
        nextPressID &+= 1
        let id = nextPressID
        phase = .seeding(pressID: id, mouseDown: mouse)
        return id
    }

    /// Applies the single focused-window seed for `pressID`, rejecting drags outside the window.
    mutating func applySeed(pressID: UInt64, windowFrameCocoa: CGRect?, windowOriginQuartz: CGPoint?) {
        guard case .seeding(let activeID, let mouseDown) = phase, activeID == pressID else { return }
        guard let frame = windowFrameCocoa,
              let origin = windowOriginQuartz,
              frame.insetBy(dx: -Self.seedHitSlop, dy: -Self.seedHitSlop).contains(mouseDown) else {
            phase = .rejected(pressID: pressID)
            return
        }
        phase = .seeded(pressID: pressID, initialOrigin: origin)
    }

    /// Observes a polled `AXPosition` while `.seeded`; returns `true` when the window moves enough to arm tracking.
    @discardableResult
    mutating func observeWindowOrigin(_ currentOrigin: CGPoint?, pressID: UInt64) -> Bool {
        guard case .seeded(let activeID, let initialOrigin) = phase, activeID == pressID else { return false }
        guard let currentOrigin else {
            phase = .rejected(pressID: pressID)
            return false
        }
        if hypot(currentOrigin.x - initialOrigin.x, currentOrigin.y - initialOrigin.y) >= movementThreshold {
            phase = .tracking(pressID: pressID)
            return true
        }
        return false
    }

    /// Completes the press on mouse-up, returning `activeZone` only if real window movement armed tracking.
    mutating func finishPress(activeZone: SnapZonePlanner.Zone?) -> SnapZonePlanner.Zone? {
        let armed = isTracking
        phase = .idle
        return armed ? activeZone : nil
    }

    mutating func reset() {
        phase = .idle
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
