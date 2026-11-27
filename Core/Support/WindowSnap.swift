import CoreGraphics
import Foundation

/// Window zones for the Windows flyout (Phase 7A-P6). The unit rectangles follow the window snapper cited in NOTICE §9 (MIT):
/// fractions of a screen's visible area with a bottom-left origin.
enum SnapPosition: String, CaseIterable, Codable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case center, maximize
    /// AT-7: a readable focus window — half the width, 70% of the height, centred. `center` is the
    /// wider "comfortable" size; this is the one for writing beside a reference.
    case focus

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
        case .focus: return CGRect(x: 0.25, y: 0.15, width: 0.5, height: 0.7)
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
    /// MD-2: how long the pointer must rest on a seam edge before that edge may resolve a snap.
    /// Crossing to the other display never stops there, so the preview never fires.
    static let seamDwell: TimeInterval = 0.45

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
                        gaps: SnapGaps = .zero,
                        suppressed: Set<ScreenEdge> = []) -> Zone? {
        guard area.width > 0, area.height > 0 else { return nil }
        switch layout {
        case .edgesAndCorners:
            guard let position = edgeZone(at: point, in: area, edgeMargin: edgeMargin, suppressed: suppressed) else { return nil }
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
    /// nil in the middle so a normal drag never turns into an accidental snap. A `suppressed` edge
    /// (a seam to another display) never resolves; its corners fall back to the other axis.
    static func edgeZone(at point: CGPoint,
                         in area: CGRect,
                         edgeMargin: CGFloat = 12,
                         suppressed: Set<ScreenEdge> = []) -> SnapPosition? {
        guard area.width > 0, area.height > 0 else { return nil }
        let margin = max(0, edgeMargin)
        let bounds = area.insetBy(dx: -margin, dy: -margin)
        guard bounds.contains(point) else { return nil }

        let nearLeft = point.x <= area.minX + margin && !suppressed.contains(.left)
        let nearRight = point.x >= area.maxX - margin && !suppressed.contains(.right)
        let nearTop = point.y >= area.maxY - margin && !suppressed.contains(.top)
        let nearBottom = point.y <= area.minY + margin && !suppressed.contains(.bottom)

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

/// MD-4: maps a window between two work areas while keeping its place and proportions. A different
/// resolution is the point: a half-width window stays half-width, a window hugging the left edge
/// stays against the left edge.
enum WindowThrow {
    /// Both rectangles in the same coordinate space (Quartz in the snapper, Cocoa in tests).
    static func relativeFrame(from frame: CGRect, source: CGRect, destination: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0, destination.width > 0, destination.height > 0 else { return frame }
        let width = min(frame.width, destination.width)
        let height = min(frame.height, destination.height)
        let x = destination.minX + (frame.minX - source.minX) / source.width * destination.width
        let y = destination.minY + (frame.minY - source.minY) / source.height * destination.height
        let maxX = max(destination.minX, destination.maxX - width)
        let maxY = max(destination.minY, destination.maxY - height)
        return CGRect(x: min(max(x, destination.minX), maxX),
                      y: min(max(y, destination.minY), maxY),
                      width: width, height: height)
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

// MARK: - SN-1: snApp layout catalog

/// One card in the snApp picker: the shapes it draws inside a unit square, and the zone each shape
/// snaps to. A card is a *drawing* first: the ⅔ pair is drawn as two halves so the eye reads the split,
/// while each half applies the wider real frame its zone names.
struct SnapLayoutPreset: Identifiable, Equatable, Sendable {
    struct Area: Equatable, Sendable {
        /// What the shape snaps the window to when clicked.
        let zone: SnapPosition
        /// Where the shape is drawn, in the card's unit square (bottom-left origin).
        let unit: CGRect
        /// Optional label drawn inside the shape, e.g. "⅔".
        let label: String?

        init(zone: SnapPosition, unit: CGRect? = nil, label: String? = nil) {
            self.zone = zone
            self.unit = unit ?? zone.unit
            self.label = label
        }
    }

    /// Stable id, so the picker can remember the last-used card and tests can name one.
    let id: String
    let areas: [Area]

    var zones: [SnapPosition] { areas.map(\.zone) }
}

/// AT-7: where the picker appears. The panel used to always hang off the pointer, which is wrong on a
/// 4K display where the pointer is often at an edge and the grid lands off screen.
enum SnapPanelPlacement: String, CaseIterable, Codable, Sendable, Identifiable {
    case followPointer, screenCentre, belowNotch, belowMenuBar, fullScreen

    static let defaultsKey = "com.katikati.snapPicker.placement"

    var id: String { rawValue }

    /// `String(localized:)` rather than a bare key: the call sites draw these through
    /// `Text(verbatim:)`, so localizing here also keeps the key visible to the localization scan.
    var localizedTitleKey: String {
        switch self {
        case .followPointer: return String(localized: "Follow Pointer")
        case .screenCentre: return String(localized: "Screen Centre")
        case .belowNotch: return String(localized: "Below Notch")
        case .belowMenuBar: return String(localized: "Below Menu Bar")
        case .fullScreen: return String(localized: "Full-Screen Overlay")
        }
    }

    static func current(_ defaults: UserDefaults = .standard) -> SnapPanelPlacement {
        defaults.string(forKey: defaultsKey).flatMap(SnapPanelPlacement.init(rawValue:)) ?? .followPointer
    }
}

/// How large the picker's cards are. Density changes the card and padding, never the keyboard model.
enum SnapGridDensity: String, CaseIterable, Codable, Sendable, Identifiable {
    case compact, regular, large

    static let defaultsKey = "com.katikati.snapPicker.density"

    var id: String { rawValue }

    var cardSize: CGSize {
        switch self {
        case .compact: return CGSize(width: 78, height: 56)
        case .regular: return CGSize(width: 94, height: 66)
        case .large: return CGSize(width: 118, height: 82)
        }
    }

    var spacing: CGFloat {
        switch self {
        case .compact: return 8
        case .regular: return 10
        case .large: return 14
        }
    }

    var padding: CGFloat {
        switch self {
        case .compact: return 10
        case .regular: return 12
        case .large: return 16
        }
    }

    /// Eight cards, two rows: four columns at every density.
    var columns: Int { 4 }

    var localizedTitleKey: String {
        switch self {
        case .compact: return String(localized: "Compact")
        case .regular: return String(localized: "Regular")
        case .large: return String(localized: "Large")
        }
    }

    static func current(_ defaults: UserDefaults = .standard) -> SnapGridDensity {
        defaults.string(forKey: defaultsKey).flatMap(SnapGridDensity.init(rawValue:)) ?? .regular
    }
}

/// Pure anchor math for the picker panel. `screenFrame` is Cocoa (bottom-left origin), `visibleFrame`
/// already excludes the Dock and menu bar. `notchInset` is `safeAreaInsets.top` (0 on a notchless
/// display) and `menuBarHeight` is the difference between the screen and its visible frame.
enum SnapPanelGeometry {
    static func frame(
        placement: SnapPanelPlacement,
        panelSize: CGSize,
        pointer: CGPoint,
        screenFrame: CGRect,
        visibleFrame: CGRect,
        anchor: CGRect?,
        notchInset: CGFloat,
        menuBarHeight: CGFloat
    ) -> CGRect {
        let visible = visibleFrame.isEmpty ? screenFrame : visibleFrame
        if placement == .fullScreen {
            return visible.insetBy(dx: 24, dy: 24)
        }

        let origin: CGPoint
        switch placement {
        case .fullScreen:
            origin = CGPoint(x: visible.minX + 24, y: visible.minY + 24)
        case .screenCentre:
            origin = CGPoint(x: visible.midX - panelSize.width / 2,
                             y: visible.midY - panelSize.height / 2)
        case .belowNotch, .belowMenuBar:
            let topInset = placement == .belowNotch ? max(notchInset, menuBarHeight) : menuBarHeight
            let top = screenFrame.maxY - max(0, topInset) - 8
            origin = CGPoint(x: screenFrame.midX - panelSize.width / 2,
                             y: top - panelSize.height)
        case .followPointer:
            var point: CGPoint
            if let anchor, !anchor.isEmpty {
                point = CGPoint(x: anchor.midX - panelSize.width / 2, y: anchor.minY - panelSize.height - 10)
                if point.y < visible.minY + 8 { point.y = anchor.maxY + 10 }
            } else {
                point = CGPoint(x: pointer.x - panelSize.width / 2, y: pointer.y - panelSize.height - 14)
                if point.y < visible.minY + 8 { point.y = pointer.y + 14 }
            }
            origin = point
        }
        return clamped(CGRect(origin: origin, size: panelSize), in: visible)
    }

    static func clamped(_ frame: CGRect, in visible: CGRect) -> CGRect {
        var f = frame
        f.origin.x = min(max(f.minX, visible.minX + 8), max(visible.minX + 8, visible.maxX - f.width - 8))
        f.origin.y = min(max(f.minY, visible.minY + 8), max(visible.minY + 8, visible.maxY - f.height - 8))
        return f
    }
}

/// AT-7: the three named target sizes a card can offer. `center` is the comfortable 75% window and
/// `focus` the narrower 50% one; `full` is the work-area fill.
enum SnapSizePreset: String, CaseIterable, Codable, Sendable {
    case full, comfortable, focus

    var position: SnapPosition {
        switch self {
        case .full: return .maximize
        case .comfortable: return .center
        case .focus: return .focus
        }
    }

    var localizedTitleKey: String {
        switch self {
        case .full: return String(localized: "Full Screen")
        case .comfortable: return String(localized: "Comfortable")
        case .focus: return String(localized: "Focus")
        }
    }
}

/// The pure half of snApp: which cards exist, what they draw, and what a click inside one means. Nothing
/// here touches a window, a screen or the pointer, so the picker's geometry is testable and the panel
/// only has to draw `areas` and hand back `zone`.
enum SnapLayoutCatalog {
    /// Two rows of four: splits first, then the three named sizes and a vertical pair.
    static let presets: [SnapLayoutPreset] = [
        SnapLayoutPreset(id: "halves", areas: [
            SnapLayoutPreset.Area(zone: .leftHalf),
            SnapLayoutPreset.Area(zone: .rightHalf),
        ]),
        SnapLayoutPreset(id: "quarters", areas: [
            SnapLayoutPreset.Area(zone: .topLeft),
            SnapLayoutPreset.Area(zone: .topRight),
            SnapLayoutPreset.Area(zone: .bottomLeft),
            SnapLayoutPreset.Area(zone: .bottomRight),
        ]),
        SnapLayoutPreset(id: "thirds", areas: [
            SnapLayoutPreset.Area(zone: .leftThird),
            SnapLayoutPreset.Area(zone: .centerThird),
            SnapLayoutPreset.Area(zone: .rightThird),
        ]),
        SnapLayoutPreset(id: "twoThirds", areas: [
            SnapLayoutPreset.Area(zone: .leftTwoThirds,
                                  unit: CGRect(x: 0, y: 0, width: 0.5, height: 1), label: "⅔"),
            SnapLayoutPreset.Area(zone: .rightTwoThirds,
                                  unit: CGRect(x: 0.5, y: 0, width: 0.5, height: 1), label: "⅔"),
        ]),
        SnapLayoutPreset(id: "vertical", areas: [
            SnapLayoutPreset.Area(zone: .topHalf),
            SnapLayoutPreset.Area(zone: .bottomHalf),
        ]),
        SnapLayoutPreset(id: "comfortable", areas: [
            SnapLayoutPreset.Area(zone: .center),
        ]),
        SnapLayoutPreset(id: "focus", areas: [
            SnapLayoutPreset.Area(zone: .focus),
        ]),
        SnapLayoutPreset(id: "maximize", areas: [
            SnapLayoutPreset.Area(zone: .maximize),
        ]),
    ]

    /// The caption under a card. Drawn from the first shape's zone, except the shaped cards where
    /// the pair is the point.
    static func titleKey(for preset: SnapLayoutPreset) -> String {
        switch preset.id {
        case "halves": return String(localized: "Halves")
        case "quarters": return String(localized: "Quarters")
        case "thirds": return String(localized: "Thirds")
        case "twoThirds": return String(localized: "Two Thirds")
        case "vertical": return String(localized: "Top Half")
        case "comfortable": return String(localized: "Comfortable")
        case "focus": return String(localized: "Focus")
        case "maximize": return String(localized: "Full Screen")
        default: return String(localized: "Halves")
        }
    }

    static func preset(id: String) -> SnapLayoutPreset? {
        presets.first { $0.id == id }
    }

    /// The shape under a unit-square point. A point in a gap belongs to no shape, so the panel can treat
    /// a click there as "dismiss" instead of guessing.
    static func area(at point: CGPoint, in preset: SnapLayoutPreset) -> SnapLayoutPreset.Area? {
        preset.areas.first { $0.unit.contains(point) }
    }
}

// MARK: - SN-3: shake gate

/// The gate in front of the shake recognition. The app layer feeds samples only while `SnapDragMonitor`
/// reports a tracking *window* drag, which is what keeps text selection, scrollbar drags and file drags
/// (Shake to shelf) away from it entirely. This type adds the two rules a bare `ShakeDetector` cannot
/// know: a press must be open, and one press opens the picker at most once. The detector keeps its own
/// 1.5 s cooldown across presses, so two quick drags cannot double-open either.
struct SnapShakeGate {
    private var detector: ShakeDetector
    private var openPress: UInt64?
    private var firedForPress = false

    init(detector: ShakeDetector = ShakeDetector()) {
        self.detector = detector
    }

    /// A dragging press started. Strokes are not cleared: the detector's window ages them out, and its
    /// cooldown must survive the press boundary, so two back-to-back shakes still coalesce into one.
    mutating func beginPress(_ id: UInt64) {
        openPress = id
        firedForPress = false
    }

    /// Feed one pointer x while the drag is tracking. Returns `true` on the sample that should open the
    /// picker; every later sample of the same press returns `false`.
    mutating func add(x: Double, at t: TimeInterval) -> Bool {
        guard openPress != nil, !firedForPress else { return false }
        guard detector.add(x: x, at: t) else { return false }
        firedForPress = true
        return true
    }

    /// The drag ended, whether or not it opened the picker.
    mutating func endPress() {
        openPress = nil
        firedForPress = false
    }
}

/// SN-4: pure coordinate and Mach-timebase math for `WindowInspectorController`.
enum WindowInspectorMath {
    static func cocoaFrame(fromQuartz quartz: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: quartz.minX,
               y: primaryMaxY - quartz.maxY,
               width: quartz.width,
               height: quartz.height)
    }

    static func cpuPercent(
        previous: (pid: Int32, wall: TimeInterval, ticks: UInt64)?,
        current: (pid: Int32, wall: TimeInterval, ticks: UInt64),
        timebaseNumer: UInt32,
        timebaseDenom: UInt32
    ) -> Double {
        guard let previous,
              previous.pid == current.pid,
              current.wall > previous.wall,
              current.ticks >= previous.ticks,
              timebaseDenom > 0 else { return 0 }
        let deltaNanoseconds = Double(current.ticks - previous.ticks) * Double(timebaseNumer) / Double(timebaseDenom)
        let wallNanoseconds = (current.wall - previous.wall) * 1_000_000_000
        return max(0, (deltaNanoseconds / wallNanoseconds) * 100)
    }
}
