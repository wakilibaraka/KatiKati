import CoreGraphics
import Foundation

public enum IslandPresentationKind: String, Equatable, Hashable, Sendable {
    case idle
    case compact
    case minimal
    case expanded
}

public enum IslandMotionMode: String, Equatable, Hashable, Sendable {
    case spring
    case reduced
    case instant
}

public enum IslandPressTarget: String, Equatable, Hashable, Sendable {
    case pill
    case bubble
}

public enum IslandPressStyle: String, Equatable, Hashable, Sendable {
    case swell
    case squish
}

public struct IslandSlotPair: Equatable, Sendable {
    public var leading: Double
    public var trailing: Double

    public init(leading: Double, trailing: Double) {
        self.leading = leading
        self.trailing = trailing
    }
}

public struct IslandSplitMeasure: Equatable, Sendable {
    public var attached: IslandSlotPair
    public var detached: IslandSlotPair

    public init(attached: IslandSlotPair, detached: IslandSlotPair) {
        self.attached = attached
        self.detached = detached
    }
}

public struct IslandContentMeasure: Equatable, Sendable {
    public var leading: Double
    public var trailing: Double
    public var attached: Double
    public var detached: Double
    public var split: IslandSplitMeasure?
    public var expandedHeight: Double

    public static let empty = IslandContentMeasure(
        leading: 0,
        trailing: 0,
        attached: 0,
        detached: 0,
        split: nil,
        expandedHeight: 0
    )

    public init(
        leading: Double = 0,
        trailing: Double = 0,
        attached: Double = 0,
        detached: Double = 0,
        split: IslandSplitMeasure? = nil,
        expandedHeight: Double = 0
    ) {
        self.leading = leading
        self.trailing = trailing
        self.attached = attached
        self.detached = detached
        self.split = split
        self.expandedHeight = expandedHeight
    }
}

public struct IslandShapeTarget: Equatable, Sendable {
    public var left: Double
    public var right: Double
    public var top: Double
    public var height: Double
    public var radius: Double
    public var bubbleLeft: Double
    public var bubbleRight: Double
    public var bubbleHeight: Double
}

public struct IslandSplitResult: Equatable, Sendable {
    public var left: Double
    public var right: Double
    public var bubbleLeft: Double
    public var bubbleRight: Double
}

public struct IslandBubbleTrailingSpec: Equatable, Sendable {
    public var width: Double
    public var fromRight: Double
    public var room: Double
}

public struct IslandNeckState: Equatable, Sendable {
    public var gap: Double
    public var power: Double
    public var tip: IslandNeckTip?
}

public struct IslandCornerTrail: Equatable, Sendable {
    public var above: Double
    public var below: Double
}

public final class IslandShapeAnimation {
    public let left: IslandAnimatedValue
    public let right: IslandAnimatedValue
    public let top: IslandAnimatedValue
    public let height: IslandAnimatedValue
    public let radius: IslandAnimatedValue
    public let leadRadius: IslandAnimatedValue
    public let bubbleLeft: IslandAnimatedValue
    public let bubbleRight: IslandAnimatedValue
    public let bubbleHeight: IslandAnimatedValue
    public let bubbleRise: IslandAnimatedValue
    public let lift: IslandAnimatedValue
    public let squish: IslandAnimatedValue
    public let bubbleSquish: IslandAnimatedValue
    public let widen: IslandAnimatedValue
    public let shadow: IslandAnimatedValue

    public var squishFactor: Double
    public var restHeight: Double
    public var neck: IslandNeckState?
    public var joinFrom: Double?
    public var cornerTrail: IslandCornerTrail?

    public init(target: IslandShapeTarget, metrics: IslandMetrics) {
        self.left = IslandAnimatedValue(target.left)
        self.right = IslandAnimatedValue(target.right)
        self.top = IslandAnimatedValue(target.top)
        self.height = IslandAnimatedValue(target.height)
        self.radius = IslandAnimatedValue(target.radius)
        self.leadRadius = IslandAnimatedValue(target.radius)
        self.bubbleLeft = IslandAnimatedValue(target.bubbleLeft)
        self.bubbleRight = IslandAnimatedValue(target.bubbleRight)
        self.bubbleHeight = IslandAnimatedValue(target.bubbleHeight)
        self.bubbleRise = IslandAnimatedValue(0)
        self.lift = IslandAnimatedValue(0)
        self.squish = IslandAnimatedValue(0, precision: 0.001)
        self.bubbleSquish = IslandAnimatedValue(0, precision: 0.001)
        self.widen = IslandAnimatedValue(0, precision: 0.001)
        self.shadow = IslandAnimatedValue(1, precision: 0.001)
        self.squishFactor = metrics.press.swell
        self.restHeight = metrics.expanded.minHeight
    }

    public func isAtRest(at t: Double) -> Bool {
        // Check every value so settled springs collapse to `.static`.
        let flags = [
            left.isAtRest(at: t),
            right.isAtRest(at: t),
            top.isAtRest(at: t),
            height.isAtRest(at: t),
            radius.isAtRest(at: t),
            leadRadius.isAtRest(at: t),
            bubbleLeft.isAtRest(at: t),
            bubbleRight.isAtRest(at: t),
            bubbleHeight.isAtRest(at: t),
            bubbleRise.isAtRest(at: t),
            lift.isAtRest(at: t),
            squish.isAtRest(at: t),
            bubbleSquish.isAtRest(at: t),
            widen.isAtRest(at: t),
            shadow.isAtRest(at: t),
        ]
        return flags.allSatisfy { $0 }
    }
}

public struct IslandBoxPose: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var radius: Double
    public var lead: Double

    public var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

public struct IslandBubblePose: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var span: Double
    public var scale: Double

    public var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

public struct IslandFrameGeometry {
    public let pill: IslandBoxPose
    public let drawn: IslandBoxPose
    public let bubble: IslandBubblePose
    public let pillPath: CGPath
    public let bubblePath: CGPath
    public let bridgePath: CGPath
    public let clipPath: CGPath
    public let outlinePath: CGPath
    public let bubbleClipPath: CGPath
    public let expansion: Double
    public let shadow: Double

    public func isGeometryEqual(to other: IslandFrameGeometry) -> Bool {
        pill == other.pill
            && drawn == other.drawn
            && bubble == other.bubble
            && expansion == other.expansion
            && shadow == other.shadow
    }
}

public enum IslandSurfacePublishPolicy {
    public static func shouldPublishFrame(current: IslandFrameGeometry, next: IslandFrameGeometry) -> Bool {
        !current.isGeometryEqual(to: next)
    }

    public static func shouldPublishDimMultiplier(
        current: Double,
        next: Double,
        tolerance: Double = 1e-4
    ) -> Bool {
        abs(current - next) > tolerance
    }
}

public enum IslandChoreography {
    public static func screenWidth(containerWidth: Double, metrics: IslandMetrics) -> Double {
        containerWidth > 0 ? min(containerWidth, metrics.screen.width) : metrics.screen.width
    }

    public static func expandedWidth(screenWidth: Double, metrics: IslandMetrics) -> Double {
        screenWidth - 2.0 * metrics.expanded.sideInset
    }

    public static func splitLayout(measure: IslandContentMeasure, metrics: IslandMetrics) -> IslandSplitResult? {
        guard let split = measure.split else { return nil }
        let s = metrics.split
        let sensor = metrics.compact.sensorWidth / 2.0
        func pairWidth(_ slots: IslandSlotPair, gap: Double) -> Double {
            slots.leading + slots.trailing + (slots.leading > 0 && slots.trailing > 0 ? gap : 0)
        }
        let attachedWidth = s.attached.outerPadding + pairWidth(split.attached, gap: s.attached.gap) + s.attached.innerPadding
        let bubbleWidth: Double
        if s.detached.width > 0 && split.detached.trailing > 0 {
            bubbleWidth = s.detached.width
        } else {
            bubbleWidth = max(
                metrics.minimal.detached.minWidth,
                s.detached.outerPadding
                    + pairWidth(split.detached, gap: s.detached.gap)
                    + (split.detached.trailing > 0 ? s.detached.trailingPadding : s.detached.outerPadding)
            )
        }
        let left = -(sensor + attachedWidth)
        let bubbleLeft = sensor + metrics.minimal.gap
        let bubbleRight = bubbleLeft + bubbleWidth
        if bubbleRight - left > s.maxSpan {
            return nil
        }
        return IslandSplitResult(left: left, right: sensor, bubbleLeft: bubbleLeft, bubbleRight: bubbleRight)
    }

    public static func bubbleTrailing(detached: IslandSlotPair, bubbleWidth: Double, metrics: IslandMetrics) -> IslandBubbleTrailingSpec {
        let d = metrics.split.detached
        if d.width <= 0 {
            return IslandBubbleTrailingSpec(
                width: detached.trailing,
                fromRight: d.trailingPadding + detached.trailing / 2.0,
                room: .infinity
            )
        }
        let start = d.outerPadding + detached.leading + d.slotGap
        let end = bubbleWidth - d.slotEnd
        let room = max(0.0, end - start)
        return IslandBubbleTrailingSpec(
            width: min(detached.trailing, room),
            fromRight: bubbleWidth - (start + end) / 2.0,
            room: room
        )
    }

    public static func compactSides(leading: Double, trailing: Double, metrics: IslandMetrics) -> (leading: Double, trailing: Double) {
        let c = metrics.compact
        func side(_ slot: Double, inner: Double) -> Double {
            slot > 0 ? inner + min(slot, c.maxSlotWidth) + c.edgePadding : 0
        }
        let leadExtent = side(leading, inner: c.innerPadding.leading)
        let trailExtent = side(trailing, inner: c.innerPadding.trailing)
        if leadExtent <= 0 || trailExtent <= 0 || c.balance <= 0 {
            return (leadExtent, trailExtent)
        }
        return (max(leadExtent, trailExtent * c.balance), max(trailExtent, leadExtent * c.balance))
    }

    public static func shapeTarget(
        kind: IslandPresentationKind,
        measure: IslandContentMeasure,
        screenWidth: Double,
        metrics: IslandMetrics
    ) -> IslandShapeTarget {
        let top = metrics.top
        switch kind {
        case .idle:
            let width = metrics.idle.width
            let height = metrics.idle.height
            return IslandShapeTarget(
                left: -width / 2.0,
                right: width / 2.0,
                top: top,
                height: height,
                radius: height / 2.0,
                bubbleLeft: width / 2.0 - height,
                bubbleRight: width / 2.0,
                bubbleHeight: 0
            )

        case .compact:
            let c = metrics.compact
            let sensor = c.sensorWidth / 2.0
            let sides = compactSides(leading: measure.leading, trailing: measure.trailing, metrics: metrics)
            let left = -min(sensor + sides.leading, c.maxWidth / 2.0)
            let right = min(sensor + sides.trailing, c.maxWidth / 2.0)
            return IslandShapeTarget(
                left: left,
                right: right,
                top: top,
                height: c.height,
                radius: c.height / 2.0,
                bubbleLeft: right - c.height,
                bubbleRight: right,
                bubbleHeight: 0
            )

        case .minimal:
            let m = metrics.minimal
            let sensor = metrics.compact.sensorWidth / 2.0
            if let split = splitLayout(measure: measure, metrics: metrics) {
                return IslandShapeTarget(
                    left: split.left,
                    right: split.right,
                    top: top,
                    height: m.height,
                    radius: m.height / 2.0,
                    bubbleLeft: split.bubbleLeft,
                    bubbleRight: split.bubbleRight,
                    bubbleHeight: m.height
                )
            }
            let left = measure.attached > 0 ? -(sensor + m.attached.innerPadding + measure.attached + m.attached.outerPadding) : -sensor
            let right = sensor
            let bubbleWidth = max(m.detached.minWidth, measure.detached + 2.0 * m.detached.padding)
            return IslandShapeTarget(
                left: left,
                right: right,
                top: top,
                height: m.height,
                radius: m.height / 2.0,
                bubbleLeft: right + m.gap,
                bubbleRight: right + m.gap + bubbleWidth,
                bubbleHeight: m.height
            )

        case .expanded:
            let e = metrics.expanded
            let half = expandedWidth(screenWidth: screenWidth, metrics: metrics) / 2.0
            let height = min(e.maxHeight, max(e.minHeight, measure.expandedHeight + e.padding.top + e.padding.bottom))
            return IslandShapeTarget(
                left: -half,
                right: half,
                top: e.top,
                height: height,
                radius: e.radius,
                bubbleLeft: half - metrics.compact.height,
                bubbleRight: half,
                bubbleHeight: 0
            )
        }
    }

    public static func shapeTransition(
        from: IslandPresentationKind,
        to: IslandPresentationKind,
        swap: Bool,
        swelling: Bool,
        alert: Bool
    ) -> IslandShapeTransition {
        if from == to { return .resize }
        if to == .expanded {
            if from == .idle { return .appearExpand }
            if from == .minimal || swap { return .swap }
            return swelling ? .pressExpand : .expand
        }
        if from == .expanded {
            if to == .minimal { return .collapseSplit }
            if to == .idle { return .dismiss }
            return alert ? .alertCollapse : .collapse
        }
        if to == .idle { return .dismiss }
        if from == .idle { return .appear }
        if to == .minimal { return .split }
        return .unsplit
    }

    public static func absorbsBubble(
        _ anim: IslandShapeAnimation,
        transition: IslandShapeTransition,
        targetBubbleHeight: Double,
        t0: Double
    ) -> Bool {
        anim.bubbleHeight.valueAt(t0) >= 0.5 && targetBubbleHeight == 0 && (transition == .unsplit || transition == .swap)
    }

    public static func retargetShape(
        _ anim: IslandShapeAnimation,
        transition kind: IslandShapeTransition,
        target: IslandShapeTarget,
        idle: IslandShapeTarget,
        at t0: Double,
        motion: IslandMotion,
        mode: IslandMotionMode
    ) {
        Core_retargetShape(anim, transition: kind, target: target, idle: idle, at: t0, motion: motion, mode: mode)
    }

    public static func leadJoin(
        _ anim: IslandShapeAnimation,
        joinAt: Double?,
        at t: Double,
        idleRight: Double,
        restLeft: Double,
        motion: IslandMotion,
        mode: IslandMotionMode
    ) {
        Core_leadJoin(anim, joinAt: joinAt, at: t, idleRight: idleRight, restLeft: restLeft, motion: motion, mode: mode)
    }

    public static func retargetPress(
        _ anim: IslandShapeAnimation,
        pressed: IslandPressTarget?,
        style: IslandPressStyle = .swell,
        at t: Double,
        motion: IslandMotion,
        metrics: IslandMetrics,
        mode: IslandMotionMode,
        idle: Bool = false
    ) {
        Core_retargetPress(anim, pressed: pressed, style: style, at: t, motion: motion, metrics: metrics, mode: mode, idle: idle)
    }

    public static func frameAt(
        _ shape: IslandShapeAnimation,
        at t: Double,
        stageWidth: Double,
        metrics: IslandMetrics
    ) -> IslandFrameGeometry {
        Core_frameAt(shape, at: t, stageWidth: stageWidth, metrics: metrics)
    }

    public static func followingClipCGPath(
        box: CGRect,
        radius: Double,
        restSize: CGSize,
        restRadius: Double,
        cap: Double,
        follow: Double
    ) -> CGPath {
        Core_followingClipCGPath(box: box, radius: radius, restSize: restSize, restRadius: restRadius, cap: cap, follow: follow)
    }
}

private func absorbsBubble(
    _ anim: IslandShapeAnimation,
    transition: IslandShapeTransition,
    targetBubbleHeight: Double,
    t0: Double
) -> Bool {
    anim.bubbleHeight.valueAt(t0) >= 0.5 && targetBubbleHeight == 0 && (transition == .unsplit || transition == .swap)
}

private func pillPose(_ shape: IslandShapeAnimation, at t: Double) -> (
    left: (value: Double, velocity: Double),
    right: (value: Double, velocity: Double),
    top: (value: Double, velocity: Double),
    height: (value: Double, velocity: Double)
) {
    let lVal = shape.left.valueAt(t), lVel = shape.left.velocityAt(t)
    let rVal = shape.right.valueAt(t), rVel = shape.right.velocityAt(t)
    let tVal = shape.top.valueAt(t), tVel = shape.top.velocityAt(t)
    let hVal = shape.height.valueAt(t), hVel = shape.height.velocityAt(t)
    let sqVal = shape.squish.valueAt(t), sqVel = shape.squish.velocityAt(t)
    let wVal = shape.widen.valueAt(t), wVel = shape.widen.velocityAt(t)

    let g = 1.0 + sqVal * shape.squishFactor
    let dg = sqVel * shape.squishFactor
    let cx = (lVal + rVal) / 2.0
    let dcx = (lVel + rVel) / 2.0
    let w = max(0.0, rVal - lVal)
    let dw = rVel - lVel
    let h = max(0.0, hVal)
    let half = (w * g + wVal) / 2.0
    let dHalf = (dw * g + w * dg + wVel) / 2.0

    return (
        left: (cx - half, dcx - dHalf),
        right: (cx + half, dcx + dHalf),
        top: (tVal - (h * (g - 1.0)) / 2.0, tVel - (hVel * (g - 1.0) + h * dg) / 2.0),
        height: (h * g, hVel * g + h * dg)
    )
}

private func bubblePose(_ shape: IslandShapeAnimation, at t: Double) -> (
    left: (value: Double, velocity: Double),
    right: (value: Double, velocity: Double),
    height: (value: Double, velocity: Double)
) {
    let blVal = shape.bubbleLeft.valueAt(t), blVel = shape.bubbleLeft.velocityAt(t)
    let brVal = shape.bubbleRight.valueAt(t), brVel = shape.bubbleRight.velocityAt(t)
    let bhVal = shape.bubbleHeight.valueAt(t), bhVel = shape.bubbleHeight.velocityAt(t)
    let sqVal = shape.bubbleSquish.valueAt(t), sqVel = shape.bubbleSquish.velocityAt(t)

    let g = 1.0 + sqVal * shape.squishFactor
    let dg = sqVel * shape.squishFactor
    let cx = (blVal + brVal) / 2.0
    let dcx = (blVel + brVel) / 2.0
    let w = max(0.0, brVal - blVal)
    let dw = brVel - blVel

    return (
        left: (cx - (w * g) / 2.0, dcx - (dw * g + w * dg) / 2.0),
        right: (cx + (w * g) / 2.0, dcx + (dw * g + w * dg) / 2.0),
        height: (bhVal * g, bhVel * g + bhVal * dg)
    )
}

private func appearEdges(_ motion: IslandMotion, width: Double) -> IslandSpringConfig {
    let base = motion.shape[.appear] ?? IslandSpringConfig(response: 0.483, dampingFraction: 0.62)
    guard let wide = motion.appearWide, wide.to > wide.from else { return base }
    let k = min(1.0, max(0.0, (width - wide.from) / (wide.to - wide.from)))
    if k == 0 { return base }
    return IslandSpringConfig(
        response: base.response + (wide.spring.response - base.response) * k,
        dampingFraction: base.dampingFraction + (wide.spring.dampingFraction - base.dampingFraction) * k
    )
}

private func leanOf(_ legs: IslandTailLegs, travel: Double) -> Double {
    let sign = legs.lean.by == 0 ? 0.0 : (legs.lean.by * travel >= 0 ? (legs.lean.by < 0 ? -1.0 : 1.0) : -1.0)
    let product = legs.lean.by * travel
    let signed = product >= 0 ? 1.0 : -1.0
    _ = sign
    return (legs.lean.by == 0 ? 0.0 : signed) * min(abs(legs.lean.by * travel), legs.lean.max)
}

private func queueTail(_ value: IslandAnimatedValue, to: Double, lean: Double, legs: IslandTailLegs, t0: Double) {
    if legs.lean.by != 0 && legs.lean.at > 0 {
        value.set(to + lean, at: t0, transition: .spring(legs.lean.spring, delay: legs.lean.at))
    }
    if legs.settle.at > 0 {
        value.set(to, at: t0, transition: .spring(legs.settle.spring, delay: legs.settle.at))
    }
}

private func Core_retargetShape(
    _ anim: IslandShapeAnimation,
    transition kind: IslandShapeTransition,
    target: IslandShapeTarget,
    idle: IslandShapeTarget,
    at t0: Double,
    motion: IslandMotion,
    mode: IslandMotionMode
) {
    if target.height > anim.restHeight {
        anim.restHeight = target.height
    }

    let opening = target.height > idle.height + 1.0 && anim.height.valueAt(t0) < idle.height + 0.05 * (target.height - idle.height)
    if mode == .spring && opening {
        anim.shadow.set(0, at: t0, transition: .instant)
        let ramp = kind == .pressExpand ? motion.shadowRampPress : motion.shadowRamp
        anim.shadow.set(1, at: t0, transition: .spring(ramp))
    } else {
        anim.shadow.set(1, at: t0, transition: .instant)
    }

    if mode != .spring {
        let go: IslandTransition = mode == .instant ? .instant : .tween(duration: motion.reducedDuration)
        anim.left.set(target.left, at: t0, transition: go)
        anim.right.set(target.right, at: t0, transition: go)
        anim.top.set(target.top, at: t0, transition: go)
        anim.height.set(target.height, at: t0, transition: go)
        anim.radius.set(target.radius, at: t0, transition: go)
        anim.bubbleLeft.set(target.bubbleLeft, at: t0, transition: go)
        anim.bubbleRight.set(target.bubbleRight, at: t0, transition: go)
        anim.bubbleHeight.set(target.bubbleHeight, at: t0, transition: go)
        anim.leadRadius.set(target.radius, at: t0, transition: go)
        anim.lift.set(0, at: t0, transition: go)
        anim.bubbleRise.set(0, at: t0, transition: .instant)
        anim.squish.set(0, at: t0, transition: go)
        anim.bubbleSquish.set(0, at: t0, transition: go)
        anim.widen.set(0, at: t0, transition: go)
        return
    }

    anim.neck = nil
    let defaultSpring = IslandSpringConfig(response: 0.5, dampingFraction: 0.82)
    let edges = kind == .appear ? appearEdges(motion, width: target.right - target.left) : (motion.shape[kind] ?? defaultSpring)
    let bubbleShown = anim.bubbleHeight.valueAt(t0) >= 0.5
    let absorbing = absorbsBubble(anim, transition: kind, targetBubbleHeight: target.bubbleHeight, t0: t0)
    if !absorbing {
        anim.joinFrom = nil
    }

    let baseVia = motion.viaIdle[kind] ?? 0
    let via = absorbing ? (kind == .swap ? (motion.bubble.absorbExpand ?? (motion.viaIdle[.unsplit] ?? 0)) : (motion.viaIdle[.unsplit] ?? 0)) : baseVia
    let turnShift = via - baseVia
    let baseBody = motion.body[kind] ?? IslandDelayedSpring(response: 0.5, dampingFraction: 0.82, delay: 0)
    let body = IslandDelayedSpring(
        response: baseBody.response,
        dampingFraction: baseBody.dampingFraction,
        delay: max(0.0, baseBody.delay + (baseBody.delay > 0 ? turnShift : 0))
    )
    let second = kind == .collapse ? motion.retarget.collapse : kind == .alertCollapse ? motion.retarget.alertCollapse : edges

    typealias StartTuple = (value: Double, velocity: Double)
    var startLeft: StartTuple?
    var startRight: StartTuple?
    var startTop: StartTuple?
    var startHeight: StartTuple?
    var startRadius: StartTuple?
    var startLeadRadius: StartTuple?

    let squishVal = anim.squish.valueAt(t0)
    func isMoving(_ val: IslandAnimatedValue) -> Bool {
        abs(val.valueAt(t0)) > 1e-4 || abs(val.velocityAt(t0)) > 1e-3
    }
    if isMoving(anim.squish) || isMoving(anim.widen) {
        let pose = pillPose(anim, at: t0)
        let g = 1.0 + squishVal * anim.squishFactor
        startLeft = pose.left
        startRight = pose.right
        startTop = pose.top
        startHeight = pose.height
        startRadius = (anim.radius.valueAt(t0) * g, anim.radius.velocityAt(t0) * g)
        startLeadRadius = (anim.leadRadius.valueAt(t0) * g, anim.leadRadius.velocityAt(t0) * g)
        anim.squish.set(0, at: t0, transition: .instant)
        anim.widen.set(0, at: t0, transition: .instant)
    }

    var bubbleStartLeft: StartTuple?
    var bubbleStartRight: StartTuple?
    var bubbleStartHeight: StartTuple?
    let bubbleSquishVal = anim.bubbleSquish.valueAt(t0)
    if abs(bubbleSquishVal) > 1e-4 || abs(anim.bubbleSquish.velocityAt(t0)) > 1e-3 {
        let bPose = bubblePose(anim, at: t0)
        bubbleStartLeft = bPose.left
        bubbleStartRight = bPose.right
        bubbleStartHeight = bPose.height
        anim.bubbleSquish.set(0, at: t0, transition: .instant)
    }

    if bubbleShown && target.bubbleHeight == 0 && !absorbing {
        let bRight = anim.bubbleRight.valueAt(t0)
        if bRight > anim.right.valueAt(t0) {
            startRight = (bRight, anim.bubbleRight.velocityAt(t0))
        }
        anim.bubbleHeight.set(0, at: t0, transition: .instant)
    }

    func moveEdge(_ value: IslandAnimatedValue, to: Double, idleTo: Double, from: StartTuple?) {
        if via > 0 {
            value.set(idleTo, at: t0, transition: .spring(edges), from: from)
            value.set(to, at: t0, transition: .spring(second, delay: via))
        } else {
            value.set(to, at: t0, transition: .spring(edges), from: from)
        }
    }

    if kind == .collapseSplit && target.bubbleHeight > 0 {
        let spread = motion.bubble.collapseSplitSpread
        let cVia = motion.bubble.collapseSplitVia
        let kickedStart: StartTuple?
        if let startLeft {
            kickedStart = startLeft
        } else if let kick = spread.kick, kick != 0 {
            let fromVal = anim.left.valueAt(t0)
            kickedStart = (fromVal, kick * ((target.left - spread.left) - fromVal))
        } else {
            kickedStart = nil
        }
        anim.left.set(target.left - spread.left, at: t0, transition: .spring(edges), from: kickedStart)
        anim.left.set(target.left, at: t0, transition: .spring(spread.spring, delay: spread.at))

        anim.right.set(target.bubbleRight - cVia.dip, at: t0, transition: .spring(cVia.down), from: startRight)
        if spread.right != 0 {
            let peel = spread.rightPeel
            if peel.at < spread.rightSettle.at {
                anim.right.set(target.right + peel.to, at: t0, transition: .spring(peel.spring, delay: peel.at))
            }
            anim.right.set(target.right + spread.right, at: t0, transition: .spring(spread.rightSettle.spring, delay: spread.rightSettle.at))
            anim.right.set(target.right, at: t0, transition: .spring(spread.rightBack.spring, delay: spread.rightBack.at))
        } else {
            anim.right.set(target.right, at: t0, transition: .spring(edges, delay: cVia.at))
        }

        let tip = spread.neckTip.map { IslandNeckTip(length: $0.length, reach: $0.reach, until: t0 + $0.until) }
        anim.neck = IslandNeckState(gap: spread.neckGap, power: spread.neckPower, tip: tip)
    } else {
        moveEdge(anim.left, to: target.left, idleTo: idle.left, from: startLeft)
        moveEdge(anim.right, to: target.right, idleTo: idle.right, from: startRight)
    }

    anim.height.set(target.height, at: t0, transition: .spring(body.spring, delay: body.delay), from: startHeight)

    let absorbCorner = absorbing && kind == .swap ? motion.bubble.absorbExpandCorner : nil
    let corner = absorbCorner ?? (motion.corner[kind] ?? body)
    let cornerDelay = absorbCorner != nil
        ? max(0.0, via + (absorbCorner?.delay ?? 0))
        : (corner.delay > 0 ? max(0.0, corner.delay + turnShift) : 0.0)
    anim.radius.set(target.radius, at: t0, transition: .spring(corner.spring, delay: cornerDelay), from: startRadius)

    let lead = absorbCorner == nil ? motion.cornerLead[kind] : nil
    let leadDelay = lead.map { $0.delay > 0 ? max(0.0, $0.delay + turnShift) : 0.0 } ?? cornerDelay
    anim.leadRadius.set(target.radius, at: t0, transition: .spring(lead?.spring ?? corner.spring, delay: leadDelay), from: startLeadRadius)
    if let trailing = lead?.trailing {
        anim.cornerTrail = IslandCornerTrail(above: trailing.above, below: trailing.below)
    }

    if (kind == .collapse || kind == .alertCollapse) && via > 0 {
        anim.top.set(target.top - motion.collapseLift, at: t0, transition: .spring(body.spring), from: startTop)
        anim.top.set(target.top, at: t0, transition: .spring(second, delay: via))
    } else {
        anim.top.set(target.top, at: t0, transition: .spring(body.spring, delay: body.delay), from: startTop)
    }

    let tail = motion.tail[kind] ?? .none
    let ownEdges = kind == .collapseSplit && target.bubbleHeight > 0
    let width0 = (startRight?.value ?? anim.right.valueAt(t0)) - (startLeft?.value ?? anim.left.valueAt(t0))
    let height0 = startHeight?.value ?? anim.height.valueAt(t0)
    let top0 = startTop?.value ?? anim.top.valueAt(t0)
    if !ownEdges {
        let widthLean = leanOf(tail.width, travel: (target.right - target.left) - width0)
        queueTail(anim.left, to: target.left, lean: -widthLean / 2.0, legs: tail.width, t0: t0)
        queueTail(anim.right, to: target.right, lean: widthLean / 2.0, legs: tail.width, t0: t0)
    }
    queueTail(anim.height, to: target.height, lean: leanOf(tail.height, travel: target.height - height0), legs: tail.height, t0: t0)
    queueTail(anim.top, to: target.top, lean: leanOf(tail.top, travel: target.top - top0), legs: tail.top, t0: t0)

    if kind == .collapseSplit && target.bubbleHeight > 0 {
        let lift = motion.bubble.collapseSplitLift
        anim.lift.set(lift.by, at: t0, transition: .spring(lift.spring))
        anim.lift.set(0, at: t0, transition: .spring(lift.back.spring, delay: lift.back.at))
    } else {
        anim.lift.set(0, at: t0, transition: .spring(body.spring))
    }

    if !(kind == .collapseSplit && target.bubbleHeight > 0 && !bubbleShown) && anim.bubbleRise.target != 0 {
        anim.bubbleRise.set(0, at: t0, transition: .instant)
    }

    if target.bubbleHeight > 0 && !bubbleShown {
        let bSpring = kind == .collapseSplit ? motion.bubble.collapseSplit : motion.bubble.split
        let h = target.bubbleHeight
        anim.bubbleHeight.set(h, at: t0, transition: .instant)
        anim.bubbleLeft.set(target.right - h, at: t0, transition: .instant)
        anim.bubbleRight.set(startRight?.value ?? anim.right.valueAt(t0), at: t0, transition: .instant)
        if kind == .collapseSplit {
            let cVia = motion.bubble.collapseSplitVia
            anim.bubbleRight.set(target.bubbleRight - cVia.dip, at: t0, transition: .spring(cVia.down))
            anim.bubbleRight.set(target.bubbleRight, at: t0, transition: .spring(cVia.spring, delay: cVia.at))

            let rise = motion.bubble.collapseSplitRise
            anim.bubbleRise.set(0, at: t0, transition: .instant)
            anim.bubbleRise.set(1, at: t0, transition: .spring(rise.spring, delay: rise.delay))

            let fromInset = motion.bubble.collapseSplitSpread.bubbleFrom
            anim.bubbleLeft.set(target.bubbleLeft - fromInset, at: t0, transition: .instant)
            if fromInset != 0 {
                anim.bubbleLeft.set(target.bubbleLeft, at: t0, transition: .spring(bSpring.spring, delay: bSpring.delay))
            }
        } else {
            moveEdge(anim.bubbleRight, to: target.bubbleRight, idleTo: idle.right, from: nil)
            anim.bubbleLeft.set(target.bubbleLeft, at: t0, transition: .spring(bSpring.spring, delay: bSpring.delay))
        }
    } else if target.bubbleHeight > 0 {
        anim.bubbleLeft.set(target.bubbleLeft, at: t0, transition: .spring(edges))
        anim.bubbleRight.set(target.bubbleRight, at: t0, transition: .spring(edges))
        anim.bubbleHeight.set(target.bubbleHeight, at: t0, transition: .spring(edges))
    } else if absorbing {
        let rest = anim.bubbleHeight.valueAt(t0)
        if let bh = bubbleStartHeight?.value {
            anim.bubbleHeight.set(bh, at: t0, transition: .instant)
            anim.bubbleHeight.set(rest, at: t0, transition: .spring(motion.bubble.unsplit))
        }
        anim.bubbleLeft.set(idle.right - rest, at: t0, transition: .spring(motion.bubble.unsplit), from: bubbleStartLeft)
        anim.bubbleRight.set(idle.right, at: t0, transition: .spring(motion.bubble.unsplitSlide), from: bubbleStartRight)
        let absorbAt = (kind == .unsplit || via <= 0) ? motion.bubble.unsplitAbsorb : via
        anim.bubbleHeight.set(0, at: t0, transition: .tween(duration: 0, delay: absorbAt))
    } else {
        anim.bubbleLeft.set(target.bubbleLeft, at: t0, transition: .instant)
        anim.bubbleRight.set(target.bubbleRight, at: t0, transition: .instant)
        anim.bubbleHeight.set(0, at: t0, transition: .instant)
    }
}

private func Core_leadJoin(
    _ anim: IslandShapeAnimation,
    joinAt: Double?,
    at t: Double,
    idleRight: Double,
    restLeft: Double,
    motion: IslandMotion,
    mode: IslandMotionMode
) {
    guard mode == .spring, let lead = motion.bubble.joinLead, lead > 0 else { return }
    if anim.bubbleHeight.target == 0 { return }
    let unsplit = motion.bubble.unsplit
    guard let joinAt else {
        guard anim.joinFrom != nil else { return }
        anim.joinFrom = nil
        anim.bubbleLeft.set(restLeft, at: t, transition: .spring(unsplit))
        return
    }
    let from = max(t, joinAt - lead)
    anim.joinFrom = from
    anim.bubbleLeft.set(idleRight - anim.bubbleHeight.target, at: t, transition: .spring(unsplit, delay: from - t))
}

private func Core_retargetPress(
    _ anim: IslandShapeAnimation,
    pressed: IslandPressTarget?,
    style: IslandPressStyle = .swell,
    at t: Double,
    motion: IslandMotion,
    metrics: IslandMetrics,
    mode: IslandMotionMode,
    idle: Bool = false
) {
    if pressed != nil {
        anim.squishFactor = style == .swell ? metrics.press.swell : metrics.press.squish
    }
    if pressed == .bubble {
        anim.neck = IslandNeckState(gap: 0.01, power: 1.5, tip: nil)
    }
    func go(_ spring: IslandSpringConfig) -> IslandTransition {
        switch mode {
        case .instant: return .instant
        case .reduced: return .tween(duration: motion.reducedDuration)
        case .spring: return .spring(spring)
        }
    }

    let down = style == .swell ? motion.press.swell : motion.press.down
    let idleRelease = (style == .swell && idle) ? motion.press.idleRelease : nil
    let up = idleRelease?.spring ?? (style == .swell ? motion.press.release : motion.press.up)
    let bubbleDown = style == .swell ? (motion.press.bubbleSwell ?? down) : down
    let bubbleTo = (style == .swell && anim.squishFactor > 0)
        ? (metrics.press.bubbleSwell ?? metrics.press.swell) / anim.squishFactor
        : 1.0

    for (part, value) in [(IslandPressTarget.pill, anim.squish), (IslandPressTarget.bubble, anim.bubbleSquish)] {
        let on = pressed == part
        if !on && value.target == 0 && value.isAtRest(at: t) {
            continue
        }
        let isBubble = part == .bubble
        let carryFrom: (Double, Double)?
        if !on, let idleRelease, mode == .spring {
            carryFrom = (value.valueAt(t), value.velocityAt(t) * idleRelease.carry)
        } else {
            carryFrom = nil
        }
        value.set(
            on ? (isBubble ? bubbleTo : 1.0) : 0.0,
            at: t,
            transition: go(on ? (isBubble ? bubbleDown : down) : up),
            from: carryFrom
        )

        if !on, !isBubble, idleRelease != nil, let widen = motion.press.idleWiden, mode == .spring {
            anim.widen.set(widen.by, at: t, transition: .spring(widen.rise))
            anim.widen.set(0, at: t, transition: .spring(widen.fall, delay: widen.hold))
        }
    }
}

private func unitSmoothstep(_ x: Double) -> Double {
    let c = min(1.0, max(0.0, x))
    return c * c * (3.0 - 2.0 * c)
}

private func Core_frameAt(
    _ shape: IslandShapeAnimation,
    at t: Double,
    stageWidth: Double,
    metrics: IslandMetrics
) -> IslandFrameGeometry {
    let pose = pillPose(shape, at: t)
    let width = max(0.0, pose.right.value - pose.left.value)
    let h = max(0.0, pose.height.value)
    let x = stageWidth / 2.0 + pose.left.value
    let y = pose.top.value - shape.lift.valueAt(t)
    let g = 1.0 + shape.squish.valueAt(t) * shape.squishFactor
    let lead = max(0.0, min(shape.leadRadius.valueAt(t) * g, h / 2.0, width / 2.0))
    let own = max(0.0, min(shape.radius.valueAt(t) * g, h / 2.0, width / 2.0))
    let radius: Double
    if let trail = shape.cornerTrail, lead != own {
        let share = unitSmoothstep((h - trail.below) / max(1e-6, trail.above - trail.below))
        radius = own + (lead - own) * share
    } else {
        radius = own
    }

    let capsuleHeight = metrics.compact.height
    let expansion = min(1.0, max(0.0, (h / max(1e-4, g) - capsuleHeight) / max(1.0, shape.restHeight - capsuleHeight)))

    let baseBH = max(0.0, shape.bubbleHeight.valueAt(t))
    let baseBL = stageWidth / 2.0 + shape.bubbleLeft.valueAt(t)
    let baseBW = max(baseBH, stageWidth / 2.0 + shape.bubbleRight.valueAt(t) - baseBL)
    let rise = min(1.0, max(0.0, shape.bubbleRise.valueAt(t)))
    let baseBY = shape.top.valueAt(t) + ((shape.height.valueAt(t) - baseBH) / 2.0) * (1.0 - rise)

    let gb = 1.0 + shape.bubbleSquish.valueAt(t) * shape.squishFactor
    let bh = baseBH * gb
    let bw = baseBW * gb
    let bl = baseBL - (baseBW * (gb - 1.0)) / 2.0
    let by = baseBY - (baseBH * (gb - 1.0)) / 2.0

    let e = metrics.expanded
    let pull = e.shadow.pull
    let k = pull.opacity > 0 ? (expansion * e.shadow.opacity) / pull.opacity : 0
    let dx = pull.side * k
    let dy = pull.top * k
    let dw = max(0.0, width - 2.0 * dx)
    let dh = max(0.0, h - (pull.top + pull.bottom) * k)
    let smoothing = metrics.corner.smoothing

    func superCorner(_ r: Double) -> IslandCornerShape {
        IslandCornerShape(
            rx: min(width / 2.0, r * (1.0 + (e.cornerAspect - 1.0) * expansion)),
            ry: r,
            exponent: 2.0 + (e.cornerExponent - 2.0) * expansion
        )
    }

    let pillPath: CGPath
    if smoothing > 0 {
        pillPath = continuousRectCGPath(
            x: x + dx,
            y: y + dy,
            width: dw,
            height: dh,
            radius: min(radius, dh / 2.0, dw / 2.0),
            smoothing: smoothing,
            leading: min(lead, dh / 2.0, dw / 2.0)
        )
    } else {
        pillPath = roundedRectCGPath(
            x: x + dx,
            y: y + dy,
            width: dw,
            height: dh,
            corner: superCorner(radius),
            leading: lead == radius ? nil : superCorner(lead)
        )
    }

    let showBubble = bh >= 0.5
    let activeNeck = (shape.joinFrom.map { t >= $0 } ?? false) ? nil : shape.neck
    let bubblePath = showBubble ? capsuleCGPath(x: bl, y: by, width: bw, height: bh, smoothing: smoothing) : CGMutablePath()

    let bridgeOut = CGMutablePath()
    let capsules = showBubble && h <= metrics.minimal.height * 1.25
    if capsules {
        let pillCap = IslandCircle(x: x + width - h / 2.0, y: y + h / 2.0, r: h / 2.0)
        let bubbleCap = IslandCircle(x: bl + bh / 2.0, y: by + bh / 2.0, r: bh / 2.0)
        let maxGap = activeNeck?.gap ?? metrics.bridge.maxGap
        let power = activeNeck?.power ?? 1.5
        let joined = bridgeCGPath(
            pillCap,
            bubbleCap,
            options: IslandBridgeOptions(handleSize: metrics.bridge.handleSize, spread: metrics.bridge.spread, maxGap: maxGap, power: power)
        )
        if !joined.isEmpty {
            bridgeOut.addPath(joined)
        } else if let tip = activeNeck?.tip, t < tip.until, tip.reach > 0 {
            let gap = hypot(bubbleCap.x - pillCap.x, bubbleCap.y - pillCap.y) - pillCap.r - bubbleCap.r
            let length = tip.length * min(1.0, max(0.0, 1.0 - (gap - maxGap) / tip.reach))
            if gap >= 0 && length > 0 {
                bridgeOut.addPath(cuspCGPath(pillCap, toward: CGPoint(x: bubbleCap.x, y: bubbleCap.y), length: length))
                bridgeOut.addPath(cuspCGPath(bubbleCap, toward: CGPoint(x: pillCap.x, y: pillCap.y), length: length))
            }
        }
    }

    let clipRadius = metrics.contentClip.radius
    let chamfer = metrics.contentClip.chamfer
    func clipOf(cx: Double, cy: Double, cw: Double, ch: Double, r: Double, cap: Double, rl: Double? = nil) -> CGPath {
        let leadR = rl ?? r
        if chamfer > 0 && cap == clipRadius {
            return chamferCGPath(x: cx, y: cy, width: cw, height: ch, leg: r * chamfer)
        }
        let inset = max(0.0, r - cap)
        let rc = min(r, cap)
        if leadR == r {
            return roundedRectCGPath(
                x: cx + inset,
                y: cy + inset,
                width: max(0.0, cw - 2.0 * inset),
                height: max(0.0, ch - 2.0 * inset),
                corner: IslandCornerShape(rx: rc, ry: rc, exponent: 2.0)
            )
        }
        let insetL = max(0.0, leadR - cap)
        let v = min(inset, insetL)
        let rcl = min(leadR, cap)
        return roundedRectCGPath(
            x: cx + insetL,
            y: cy + v,
            width: max(0.0, cw - inset - insetL),
            height: max(0.0, ch - 2.0 * v),
            corner: IslandCornerShape(rx: rc, ry: rc, exponent: 2.0),
            leading: IslandCornerShape(rx: rcl, ry: rcl, exponent: 2.0)
        )
    }

    let bubbleClipPath: CGPath = showBubble ? clipOf(cx: bl, cy: by, cw: bw, ch: bh, r: bh / 2.0, cap: clipRadius) : CGMutablePath()
    let clipMutable = CGMutablePath()
    clipMutable.addPath(clipOf(cx: x, cy: y, cw: width, ch: h, r: radius, cap: clipRadius, rl: lead))
    if !bubbleClipPath.isEmpty {
        clipMutable.addPath(bubbleClipPath)
    }

    let outlineMutable = CGMutablePath()
    outlineMutable.addPath(clipOf(cx: x, cy: y, cw: width, ch: h, r: radius, cap: .infinity, rl: lead))
    if showBubble {
        outlineMutable.addPath(clipOf(cx: bl, cy: by, cw: bw, ch: bh, r: bh / 2.0, cap: .infinity))
    }

    return IslandFrameGeometry(
        pill: IslandBoxPose(x: x, y: y, width: width, height: h, radius: radius, lead: lead),
        drawn: IslandBoxPose(
            x: x + dx,
            y: y + dy,
            width: dw,
            height: dh,
            radius: min(radius, dh / 2.0, dw / 2.0),
            lead: min(lead, dh / 2.0, dw / 2.0)
        ),
        bubble: IslandBubblePose(
            x: bl,
            y: by,
            width: showBubble ? bw : 0,
            height: bh,
            span: bw,
            scale: gb
        ),
        pillPath: pillPath,
        bubblePath: bubblePath,
        bridgePath: bridgeOut,
        clipPath: clipMutable,
        outlinePath: outlineMutable,
        bubbleClipPath: bubbleClipPath,
        expansion: expansion,
        shadow: min(expansion, max(0.0, shape.shadow.valueAt(t)))
    )
}

private func Core_followingClipCGPath(
    box: CGRect,
    radius: Double,
    restSize: CGSize,
    restRadius: Double,
    cap: Double,
    follow: Double
) -> CGPath {
    let sx = restSize.width > 0.5 ? Double(box.width / restSize.width) : 1.0
    let sy = restSize.height > 0.5 ? Double(box.height / restSize.height) : 1.0
    let liveInset = max(0.0, radius - cap)
    let liveR = min(radius, cap)
    let still = abs(sx - 1.0) < 1e-9 && abs(sy - 1.0) < 1e-9 && abs(radius - restRadius) < 1e-9
    if follow <= 0 || still {
        return roundedRectCGPath(
            x: Double(box.minX) + liveInset,
            y: Double(box.minY) + liveInset,
            width: max(0.0, Double(box.width) - 2.0 * liveInset),
            height: max(0.0, Double(box.height) - 2.0 * liveInset),
            corner: IslandCornerShape(rx: liveR, ry: liveR, exponent: 2.0)
        )
    }
    let restInset = max(0.0, restRadius - cap)
    let restR = min(restRadius, cap)
    func mix(_ a: Double, _ b: Double) -> Double {
        follow >= 1.0 ? b : a + (b - a) * follow
    }
    let ix = mix(liveInset, restInset * sx)
    let iy = mix(liveInset, restInset * sy)
    return roundedRectCGPath(
        x: Double(box.minX) + ix,
        y: Double(box.minY) + iy,
        width: max(0.0, Double(box.width) - 2.0 * ix),
        height: max(0.0, Double(box.height) - 2.0 * iy),
        corner: IslandCornerShape(rx: max(0.0, mix(liveR, restR * sx)), ry: max(0.0, mix(liveR, restR * sy)), exponent: 2.0)
    )
}
