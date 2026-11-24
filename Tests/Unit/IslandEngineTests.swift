import CoreGraphics
import XCTest
@testable import KatiKati

final class IslandEngineTests: XCTestCase {
    func testSpringSolverClosedFormSettlesWithoutDrift() {
        let underdamped = IslandSpringConfig(response: 0.45, dampingFraction: 0.72)
        let s0 = solveIslandSpring(underdamped, x0: 100.0, v0: 0.0, t: 0.0)
        XCTAssertEqual(s0.x, 100.0, accuracy: 1e-9)
        XCTAssertEqual(s0.v, 0.0, accuracy: 1e-9)

        let mid = solveIslandSpring(underdamped, x0: 100.0, v0: 0.0, t: 0.15)
        XCTAssertLessThan(abs(mid.x), 100.0)
        let settled = solveIslandSpring(underdamped, x0: 100.0, v0: 0.0, t: 4.0)
        XCTAssertEqual(settled.x, 0.0, accuracy: 1e-3)
        XCTAssertEqual(settled.v, 0.0, accuracy: 1e-2)

        let critical = IslandSpringConfig(response: 0.4, dampingFraction: 1.0)
        let critMid = solveIslandSpring(critical, x0: 100.0, v0: 0.0, t: 0.25)
        XCTAssertGreaterThan(critMid.x, 0.0) // Critical damping never overshoots zero from v0 = 0.

        let overdamped = IslandSpringConfig(response: 0.4, dampingFraction: 1.4)
        let overMid = solveIslandSpring(overdamped, x0: 100.0, v0: 0.0, t: 0.3)
        XCTAssertGreaterThan(overMid.x, 0.0)
    }

    func testAnimatedValueMultiLegAndRestCollapse() {
        let value = IslandAnimatedValue(0)
        value.set(100, at: 0, transition: .spring(IslandSpringConfig(response: 0.4, dampingFraction: 1.0)))
        value.set(120, at: 0, transition: .spring(IslandSpringConfig(response: 0.3, dampingFraction: 1.0), delay: 0.2))

        XCTAssertEqual(value.target, 120)
        XCTAssertFalse(value.isAtRest(at: 0.1))
        XCTAssertGreaterThan(value.valueAt(0.1), 0)
        XCTAssertLessThan(value.valueAt(0.1), 100)
        XCTAssertTrue(value.isAtRest(at: 5.0))
        XCTAssertEqual(value.valueAt(5.0), 120.0, accuracy: 1e-6)
    }

    func testContinuousPathAndMetaballBridgeGeometry() {
        let pill = continuousRectCGPath(x: 10, y: 10, width: 200, height: 36.85, radius: 18.425, smoothing: 0.72)
        XCTAssertFalse(pill.isEmpty)
        let bounds = pill.boundingBox
        XCTAssertEqual(bounds.minX, 10, accuracy: 0.2)
        XCTAssertEqual(bounds.minY, 10, accuracy: 0.2)
        XCTAssertEqual(bounds.width, 200, accuracy: 0.4)
        XCTAssertEqual(bounds.height, 36.85, accuracy: 0.4)
        XCTAssertTrue(pill.contains(CGPoint(x: 110, y: 28)))

        let leftCap = IslandCircle(x: 100, y: 32, r: 18)
        let nearCap = IslandCircle(x: 138, y: 32, r: 18) // gap = 38 - 36 = 2 pt (< 5 pt)
        let connected = bridgeCGPath(leftCap, nearCap, options: IslandBridgeOptions(handleSize: 2.4, spread: 0.3, maxGap: 5.0))
        XCTAssertFalse(connected.isEmpty)
        XCTAssertTrue(connected.contains(CGPoint(x: 119, y: 32)))

        let farCap = IslandCircle(x: 145, y: 32, r: 18) // gap = 9 pt (>= 5 pt)
        let disconnected = bridgeCGPath(leftCap, farCap, options: IslandBridgeOptions(handleSize: 2.4, spread: 0.3, maxGap: 5.0))
        XCTAssertTrue(disconnected.isEmpty)
    }

    func testChoreographyAsymmetricBalanceAndSplitCollapse() {
        let metrics = IslandMetrics.reference
        let sides = IslandChoreography.compactSides(leading: 20, trailing: 60, metrics: metrics)
        XCTAssertGreaterThan(sides.leading, 20) // Enforces 0.7475 balance ratio
        XCTAssertEqual(sides.leading, sides.trailing * metrics.compact.balance, accuracy: 1e-6)

        let measure = IslandContentMeasure(
            leading: 20,
            trailing: 48,
            split: IslandSplitMeasure(
                attached: IslandSlotPair(leading: 18, trailing: 28),
                detached: IslandSlotPair(leading: 16, trailing: 14)
            ),
            expandedHeight: 110
        )
        let idle = IslandChoreography.shapeTarget(kind: .idle, measure: measure, screenWidth: metrics.screen.width, metrics: metrics)
        let expanded = IslandChoreography.shapeTarget(kind: .expanded, measure: measure, screenWidth: metrics.screen.width, metrics: metrics)
        let split = IslandChoreography.shapeTarget(kind: .minimal, measure: measure, screenWidth: metrics.screen.width, metrics: metrics)
        XCTAssertGreaterThan(split.bubbleHeight, 0)

        let anim = IslandShapeAnimation(target: expanded, metrics: metrics)
        let transition = IslandChoreography.shapeTransition(from: .expanded, to: .minimal, swap: false, swelling: false, alert: false)
        XCTAssertEqual(transition, .collapseSplit)

        IslandChoreography.retargetShape(
            anim,
            transition: transition,
            target: split,
            idle: idle,
            at: 0,
            motion: .default,
            mode: .spring
        )
        let midFrame = IslandChoreography.frameAt(anim, at: 0.28, stageWidth: metrics.screen.width, metrics: metrics)
        XCTAssertGreaterThan(midFrame.bubble.height, 0)
        XCTAssertFalse(anim.isAtRest(at: 0.28))
        XCTAssertTrue(anim.isAtRest(at: 5.0))
    }

    func testStorePrioritySplitGroupHandoffAndLongPress() {
        let clock = ManualIslandClock(initialMs: 0)
        let store = IslandStore(clock: clock)

        var pressedMusic = 0
        store.start(IslandActivitySpec(
            id: "music",
            label: "Now Playing",
            priority: 1,
            onPress: { pressedMusic += 1 }
        ))
        XCTAssertEqual(store.presentation, .compact)

        store.start(IslandActivitySpec(
            id: "timer",
            label: "Timer",
            priority: 2
        ))
        XCTAssertEqual(store.presentation, .minimal)
        XCTAssertEqual(store.scene.primary?.id, "timer")
        XCTAssertEqual(store.scene.detached?.id, "music")

        // Tap detached bubble quickly (< decide) invokes onPress without expanding.
        store.press(.bubble)
        clock.advance(byMs: 50)
        store.release()
        XCTAssertEqual(pressedMusic, 1)
        XCTAssertEqual(store.presentation, .minimal)

        // Long-press detached bubble decides join then expands at longPressBubble (0.224s).
        store.press(.bubble)
        clock.advance(byMs: 110)
        XCTAssertNotNil(store.snapshot.joiningAtMs)
        clock.advance(byMs: 130)
        XCTAssertEqual(store.presentation, .expanded)
        XCTAssertEqual(store.snapshot.expanded?.id, "music")

        store.collapse()
        XCTAssertEqual(store.presentation, .minimal)

        // Group turn-taking + alert auto-return.
        store.reset()
        store.start(IslandActivitySpec(id: "g1", label: "First", group: "eta"))
        store.start(IslandActivitySpec(id: "g2", label: "Second", group: "eta"))
        XCTAssertEqual(store.presentation, .compact)
        XCTAssertEqual(store.scene.primary?.id, "g1")

        store.update("g2", IslandActivityUpdate(alert: true))
        XCTAssertEqual(store.snapshot.handoff, "eta")
        clock.advance(byMs: 1500)
        XCTAssertEqual(store.presentation, .expanded)
        XCTAssertEqual(store.snapshot.expanded?.id, "g2")

        clock.advance(byMs: 4700)
        XCTAssertEqual(store.presentation, .compact)
        XCTAssertEqual(store.scene.primary?.id, "g2")
    }

    func testKeylineLumaAndAlphaTable() {
        XCTAssertEqual(islandColourLuma("#000000")!, 0.0, accuracy: 1e-6)
        XCTAssertEqual(islandColourLuma("#ffffff")!, 1.0, accuracy: 1e-6)
        XCTAssertNil(islandColourLuma("linear-gradient(#000, #fff)"))

        let metrics = IslandMetrics.reference
        XCTAssertEqual(islandKeylineAlphaFor(luma: 0.02, metrics: metrics), 0.16, accuracy: 1e-6)
        XCTAssertEqual(islandKeylineAlphaFor(luma: 0.25, metrics: metrics), 0.0, accuracy: 1e-6)
        let midAlpha = islandKeylineAlphaFor(luma: 0.0706, metrics: metrics)
        XCTAssertEqual(midAlpha, 0.16 * 0.328, accuracy: 1e-4)

        XCTAssertEqual(
            islandKeylineDimMultiplier(elapsedSeconds: 0.5, motion: IslandMotion.default.keyline),
            IslandMotion.default.keyline.dip,
            accuracy: 1e-6
        )
        XCTAssertEqual(
            islandKeylineDimMultiplier(elapsedSeconds: 1.2, motion: IslandMotion.default.keyline),
            1.0,
            accuracy: 1e-6
        )
    }

    func testSurfacePublishPolicyDeduplicatesIdenticalFramesAndTinyDimDeltas() {
        let metrics = IslandMetrics.reference
        let target = IslandChoreography.shapeTarget(
            kind: .idle,
            measure: .empty,
            screenWidth: 520,
            metrics: metrics
        )
        let anim = IslandShapeAnimation(target: target, metrics: metrics)
        let f1 = IslandChoreography.frameAt(anim, at: 10.0, stageWidth: 520, metrics: metrics)
        let f2 = IslandChoreography.frameAt(anim, at: 10.1, stageWidth: 520, metrics: metrics)
        XCTAssertFalse(IslandSurfacePublishPolicy.shouldPublishFrame(current: f1, next: f2))

        XCTAssertFalse(IslandSurfacePublishPolicy.shouldPublishDimMultiplier(current: 1.0, next: 1.00001))
        XCTAssertTrue(IslandSurfacePublishPolicy.shouldPublishDimMultiplier(current: 1.0, next: 0.995))
    }
}
