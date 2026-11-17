import CoreGraphics
import XCTest
@testable import KatiKati

final class IslandDisplayTopologyTests: XCTestCase {
    func testClassicNotchedMacBookTopology() {
        let topology = IslandDisplayTopology.resolve(
            screenWidth: 1728,
            screenHeight: 1117,
            safeAreaTop: 38,
            auxLeftWidth: 760,
            auxRightWidth: 760,
            menuBarHeight: 38,
            isBuiltinDisplay: true,
            isOLED: false,
            supportsMultiTouch: false
        )

        if case let .classicNotch(width, height, keepout) = topology.cutout {
            XCTAssertGreaterThan(width, 170)
            XCTAssertEqual(height, 38)
            XCTAssertEqual(keepout, 160)
        } else {
            XCTFail("Expected classicNotch topology, got \(topology.cutout)")
        }

        let metrics = topology.islandMetrics(nonNotchBehavior: .compactPill, touchEnabled: false)
        XCTAssertEqual(metrics.top, 0)
        XCTAssertEqual(metrics.expanded.top, 0)
        XCTAssertGreaterThan(metrics.compact.maxWidth, 350)
    }

    func testM5OLEDDynamicIslandTouchMacTopology() {
        let topology = IslandDisplayTopology.resolve(
            screenWidth: 1728,
            screenHeight: 1117,
            safeAreaTop: 46,
            auxLeftWidth: 798,
            auxRightWidth: 798,
            menuBarHeight: 46,
            isBuiltinDisplay: true,
            isOLED: true,
            supportsMultiTouch: true
        )

        XCTAssertTrue(topology.isOLED)
        XCTAssertTrue(topology.supportsMultiTouch)
        XCTAssertTrue(topology.isTouchOptimized(setting: .automatic))
        XCTAssertFalse(topology.isTouchOptimized(setting: .off))
        XCTAssertTrue(topology.isTouchOptimized(setting: .off, debugOverride: true))

        if case let .oledDynamicIsland(width, _, topMargin, _) = topology.cutout {
            XCTAssertLessThanOrEqual(width, 170)
            XCTAssertGreaterThan(topMargin, 4)
        } else {
            XCTFail("Expected oledDynamicIsland topology, got \(topology.cutout)")
        }

        let metrics = topology.islandMetrics(nonNotchBehavior: .compactPill, touchEnabled: true)
        XCTAssertGreaterThanOrEqual(metrics.compact.height, 40.0)
        XCTAssertEqual(metrics.keyline.alpha, 0.16, accuracy: 1e-6)
        XCTAssertNotNil(topology.cameraKeepoutRect(stageWidth: 500, metrics: metrics))
    }

    func testNonNotchExternalDisplayIdleBehaviors() {
        let topology = IslandDisplayTopology.resolve(
            screenWidth: 2560,
            screenHeight: 1440,
            safeAreaTop: 0,
            auxLeftWidth: nil,
            auxRightWidth: nil,
            menuBarHeight: 24,
            isBuiltinDisplay: false,
            isOLED: false,
            supportsMultiTouch: false
        )

        XCTAssertEqual(topology.cutout, .none)
        XCTAssertTrue(topology.adaptsAsFloatingBelowMenuBar(nonNotchBehavior: .compactPill))
        XCTAssertFalse(topology.adaptsAsFloatingBelowMenuBar(nonNotchBehavior: .autoHideAtRest))
        XCTAssertTrue(topology.hidesAtRest(activeCount: 0, nonNotchBehavior: .autoHideAtRest))
        XCTAssertFalse(topology.hidesAtRest(activeCount: 1, nonNotchBehavior: .autoHideAtRest))

        let wideMetrics = topology.islandMetrics(nonNotchBehavior: .wideBarAtRest, touchEnabled: false)
        let compactMetrics = topology.islandMetrics(nonNotchBehavior: .compactPill, touchEnabled: false)
        XCTAssertGreaterThan(wideMetrics.idle.width, compactMetrics.idle.width)
        XCTAssertEqual(compactMetrics.top, 8.0)
    }

    func testTouchHitPolicyAndRubberBanding() {
        let small = CGRect(x: 100, y: 100, width: 22, height: 22)
        let pointerRect = IslandTouchHitPolicy.interactiveHitRect(for: small, touchEnabled: false)
        XCTAssertEqual(pointerRect, small)

        let touchRect = IslandTouchHitPolicy.interactiveHitRect(for: small, touchEnabled: true)
        XCTAssertEqual(touchRect.width, 44.0)
        XCTAssertEqual(touchRect.height, 44.0)
        XCTAssertEqual(touchRect.midX, small.midX, accuracy: 1e-6)
        XCTAssertEqual(touchRect.midY, small.midY, accuracy: 1e-6)

        let pull = IslandTouchHitPolicy.rubberBandedOffset(64.0, dimension: 64.0, coefficient: 0.55)
        XCTAssertGreaterThan(pull, 0)
        XCTAssertLessThan(pull, 64.0)

        XCTAssertTrue(IslandTouchHitPolicy.shouldCommitPull(translationY: 24, velocityY: 0, isExpanded: false, touchEnabled: true))
        XCTAssertTrue(IslandTouchHitPolicy.shouldCommitPull(translationY: 10, velocityY: 320, isExpanded: false, touchEnabled: true))
        XCTAssertFalse(IslandTouchHitPolicy.shouldCommitPull(translationY: 10, velocityY: 40, isExpanded: false, touchEnabled: true))
        XCTAssertTrue(IslandTouchHitPolicy.shouldCommitPull(translationY: -12, velocityY: -300, isExpanded: true, touchEnabled: true))
    }

    func testDynamicIslandSkinPreviewGeometryBounds() {
        let open = NotchGeometry.openSize(for: .dynamicIsland)
        let previewOpen = NotchGeometry.previewSize(for: .dynamicIsland, expanded: true)
        let previewClosed = NotchGeometry.previewSize(for: .dynamicIsland, expanded: false)
        XCTAssertEqual(open.width, 480)
        XCTAssertEqual(previewOpen.width, 480)
        XCTAssertEqual(previewOpen.height, 180)
        XCTAssertEqual(previewClosed, CGSize(width: NotchDesignSpec.fallbackClosedWidth, height: NotchDesignSpec.fallbackClosedHeight))
    }
}
