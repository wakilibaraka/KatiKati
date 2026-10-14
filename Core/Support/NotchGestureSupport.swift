import Foundation

// Phase 33c — NotchGestureSupport: One decision per physical scroll sequence.
// Adapted from vorssaint-utils to enable mouse scroll down to expand, scroll up to collapse,
// flick momentum coasting, and horizontal swipe page transitions or track skipping. Dual-compiled.

enum NotchGestureAction: Equatable, Sendable {
    case open
    case close
    case nextTrack
    case previousTrack
    case nextPage
    case previousPage
}

struct NotchGestureSupport: Sendable {
    enum HorizontalMode: Sendable {
        case pageNavigation
        case trackSkip
    }

    private enum Axis: Sendable { case horizontal, vertical }
    private struct Origin: Sendable {
        let vertical: Bool
        let horizontal: Bool
        let expanded: Bool
    }

    private var origin: Origin?
    private var axis: Axis?
    private var pendingX: Double = 0.0
    private var pendingY: Double = 0.0
    private var distance: Double = 0.0
    private var fired: Bool = false
    private var coasting: Bool = false
    private var lastTimestamp: TimeInterval?

    static let verticalThreshold: Double = 16.0
    static let horizontalThreshold: Double = 40.0

    static func movement(_ delta: Double, precise: Bool, inverted: Bool) -> Double {
        guard delta.isFinite else { return 0 }
        return delta * (inverted ? 1 : -1) * (precise ? 1 : 24)
    }

    static func allowsVertical(expanded: Bool, inHeader: Bool, control: Bool, scroll: Bool) -> Bool {
        !control && (!expanded || inHeader || !scroll)
    }

    mutating func handle(
        x: Double,
        y: Double,
        timestamp: TimeInterval,
        began: Bool,
        ended: Bool,
        momentum: Bool,
        precise: Bool,
        hasPhase: Bool,
        allowVertical: Bool,
        allowHorizontal: Bool,
        expanded: Bool,
        horizontalMode: HorizontalMode = .pageNavigation
    ) -> NotchGestureAction? {
        guard timestamp.isFinite, x.isFinite, y.isFinite else { self = Self(); return nil }

        // A quick flick lifts the fingers before the swipe has travelled far enough.
        // Its momentum can finish the opening or closing it began.
        let transition = coasting && !momentum && !hasPhase && precise
            && lastTimestamp.map({ timestamp >= $0 && timestamp - $0 <= 0.35 }) == true
        if momentum || transition {
            guard coasting, !fired, let origin, let last = lastTimestamp,
                  timestamp >= last, timestamp - last <= 0.35, abs(y) >= abs(x) * 1.5 else {
                self = Self()
                return nil
            }
            lastTimestamp = timestamp
            distance += y
            return verticalAction(expanded: origin.expanded)
        }
        if ended {
            coasting = origin != nil && axis == .vertical && !fired
            if coasting { lastTimestamp = timestamp } else { self = Self() }
            return nil
        }
        if coasting { self = Self() }
        if hasPhase {
            if began {
                self = Self()
                origin = Origin(vertical: allowVertical, horizontal: allowHorizontal, expanded: expanded)
            }
            guard origin != nil else { return nil }
            if lastTimestamp.map({ timestamp < $0 }) == true { self = Self(); return nil }
        } else if origin != nil || began || lastTimestamp.map({ timestamp < $0 || timestamp - $0 > 0.35 }) == true {
            self = Self()
        }
        lastTimestamp = timestamp
        guard !fired else { return nil }

        let allowVert = origin?.vertical ?? allowVertical
        let allowHoriz = origin?.horizontal ?? allowHorizontal
        let isExp = origin?.expanded ?? expanded

        if axis == nil {
            pendingX += x
            pendingY += y
            if precise, allowHoriz, abs(pendingX) >= 4, abs(pendingX) >= abs(pendingY) * 1.5 {
                axis = .horizontal
                distance = pendingX
            } else if allowVert, abs(pendingY) >= 4, abs(pendingY) >= abs(pendingX) * 1.5 {
                axis = .vertical
                distance = pendingY
            } else {
                return nil
            }
        } else {
            distance += axis == .horizontal ? x : y
        }

        switch axis {
        case .horizontal where allowHoriz:
            guard abs(distance) >= Self.horizontalThreshold else { return nil }
            fired = true
            if horizontalMode == .trackSkip {
                return distance < 0 ? .nextTrack : .previousTrack
            } else {
                return distance < 0 ? .nextPage : .previousPage
            }
        case .vertical where allowVert:
            return verticalAction(expanded: isExp)
        default:
            return nil
        }
    }

    private mutating func verticalAction(expanded: Bool) -> NotchGestureAction? {
        guard abs(distance) >= Self.verticalThreshold else { return nil }
        fired = true
        if distance > 0, !expanded { return .open }
        if distance < 0, expanded { return .close }
        return nil
    }
}
