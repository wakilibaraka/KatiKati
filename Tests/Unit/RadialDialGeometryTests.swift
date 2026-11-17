import XCTest
import CoreGraphics
import SwiftUI
import AppKit
@testable import KatiKati

final class RadialDialGeometryTests: XCTestCase {

    private let center = CGPoint(x: 200, y: 200)
    private let innerRadius: CGFloat = 50
    private let outerRadius: CGFloat = 150

    func testCenterDeadzoneHitTest() {
        // Points inside innerRadius should always return .center
        let exactCenter = center
        XCTAssertEqual(
            RadialDialGeometry.hitTest(point: exactCenter, center: center, count: 8, innerRadius: innerRadius, outerRadius: outerRadius),
            .center
        )

        let nearCenter = CGPoint(x: 200 + 30, y: 200 + 30) // r = ~42.4 < 50
        XCTAssertEqual(
            RadialDialGeometry.hitTest(point: nearCenter, center: center, count: 8, innerRadius: innerRadius, outerRadius: outerRadius),
            .center
        )
    }

    func testOutsideBoundsHitTest() {
        // Beyond outerRadius + slop (150 + 40 = 190)
        let farPoint = CGPoint(x: 200 + 250, y: 200) // r = 250 > 190
        XCTAssertEqual(
            RadialDialGeometry.hitTest(point: farPoint, center: center, count: 8, innerRadius: innerRadius, outerRadius: outerRadius),
            .outside
        )
    }

    func testEightSectorCardinalDirections() {
        // Sector 0: North / Top (midAngle = -π/2)
        let north = CGPoint(x: 200, y: 100)
        XCTAssertEqual(
            RadialDialGeometry.hitTest(point: north, center: center, count: 8, innerRadius: innerRadius, outerRadius: outerRadius),
            .sector(0)
        )

        // Sector 1: North-East
        let northEast = CGPoint(x: 280, y: 120)
        XCTAssertEqual(
            RadialDialGeometry.hitTest(point: northEast, center: center, count: 8, innerRadius: innerRadius, outerRadius: outerRadius),
            .sector(1)
        )

        // Sector 2: East / Right
        let east = CGPoint(x: 300, y: 200)
        XCTAssertEqual(
            RadialDialGeometry.hitTest(point: east, center: center, count: 8, innerRadius: innerRadius, outerRadius: outerRadius),
            .sector(2)
        )

        // Sector 3: South-East
        let southEast = CGPoint(x: 280, y: 280)
        XCTAssertEqual(
            RadialDialGeometry.hitTest(point: southEast, center: center, count: 8, innerRadius: innerRadius, outerRadius: outerRadius),
            .sector(3)
        )

        // Sector 4: South / Bottom
        let south = CGPoint(x: 200, y: 300)
        XCTAssertEqual(
            RadialDialGeometry.hitTest(point: south, center: center, count: 8, innerRadius: innerRadius, outerRadius: outerRadius),
            .sector(4)
        )

        // Sector 5: South-West
        let southWest = CGPoint(x: 120, y: 280)
        XCTAssertEqual(
            RadialDialGeometry.hitTest(point: southWest, center: center, count: 8, innerRadius: innerRadius, outerRadius: outerRadius),
            .sector(5)
        )

        // Sector 6: West / Left
        let west = CGPoint(x: 100, y: 200)
        XCTAssertEqual(
            RadialDialGeometry.hitTest(point: west, center: center, count: 8, innerRadius: innerRadius, outerRadius: outerRadius),
            .sector(6)
        )

        // Sector 7: North-West
        let northWest = CGPoint(x: 120, y: 120)
        XCTAssertEqual(
            RadialDialGeometry.hitTest(point: northWest, center: center, count: 8, innerRadius: innerRadius, outerRadius: outerRadius),
            .sector(7)
        )
    }

    func testTenSectorMidAngleHits() {
        let sectors = RadialDialGeometry.sectors(count: 10, innerRadius: innerRadius, outerRadius: outerRadius)
        XCTAssertEqual(sectors.count, 10)

        for sector in sectors {
            let hitPoint = sector.centerPoint(in: center, atFraction: 0.5)
            let result = RadialDialGeometry.hitTest(
                point: hitPoint,
                center: center,
                count: 10,
                innerRadius: innerRadius,
                outerRadius: outerRadius
            )
            XCTAssertEqual(result, .sector(sector.index), "Sector \(sector.index) at angle \(sector.midAngle) should hit test to its own index")
        }
    }

    func testSectorGeometryContiguity() {
        let sectors = RadialDialGeometry.sectors(count: 6, innerRadius: 40, outerRadius: 160)
        XCTAssertEqual(sectors.count, 6)

        for i in 0..<sectors.count {
            let current = sectors[i]
            let next = sectors[(i + 1) % sectors.count]

            // Check sector span is ~2π/6 = π/3
            let span = current.endAngle - current.startAngle
            XCTAssertEqual(span, CGFloat.pi / 3, accuracy: 0.0001)

            // Current endAngle should equal next startAngle
            if i < sectors.count - 1 {
                XCTAssertEqual(current.endAngle, next.startAngle, accuracy: 0.0001)
            }
        }
    }

    func testOuterSlopTolerance() {
        // Point is 20 pt past outerRadius (150 + 20 = 170). Default slop is 40 (max 190).
        let justBeyondOuter = CGPoint(x: 200, y: 30) // dy = -170
        let hit = RadialDialGeometry.hitTest(
            point: justBeyondOuter,
            center: center,
            count: 8,
            innerRadius: innerRadius,
            outerRadius: outerRadius,
            outerSlop: 40
        )
        XCTAssertEqual(hit, .sector(0), "Flick gesture within outerSlop threshold should remain selected")

        // Point is 60 pt past outerRadius (150 + 60 = 210 > 190). Should be outside.
        let wayBeyondOuter = CGPoint(x: 200, y: -10) // dy = -210
        let miss = RadialDialGeometry.hitTest(
            point: wayBeyondOuter,
            center: center,
            count: 8,
            innerRadius: innerRadius,
            outerRadius: outerRadius,
            outerSlop: 40
        )
        XCTAssertEqual(miss, .outside)
    }

    func testDualRingHitTesting() {
        let metrics = RadialDialGeometry.DualRingMetrics()

        // 1. Center deadzone (< 45)
        let centerPoint = center
        XCTAssertEqual(RadialDialGeometry.hitTestDualRing(point: centerPoint, center: center, metrics: metrics), .center)

        let nearCenter = CGPoint(x: 200 + 20, y: 200) // r = 20 < 45
        XCTAssertEqual(RadialDialGeometry.hitTestDualRing(point: nearCenter, center: center, metrics: metrics), .center)

        // 2. Inner Ring (45 <= r <= 110, 8 segments)
        // Sector 0: North (r = 80, dy = -80)
        let innerNorth = CGPoint(x: 200, y: 120)
        XCTAssertEqual(RadialDialGeometry.hitTestDualRing(point: innerNorth, center: center, metrics: metrics), .inner(0))

        // Sector 2: East (r = 80, dx = 80)
        let innerEast = CGPoint(x: 280, y: 200)
        XCTAssertEqual(RadialDialGeometry.hitTestDualRing(point: innerEast, center: center, metrics: metrics), .inner(2))

        // 3. Outer Ring (110 < r <= 180 + 40 slop = 220, 6 segments)
        // Sector 0: North (r = 150, dy = -150)
        let outerNorth = CGPoint(x: 200, y: 50)
        XCTAssertEqual(RadialDialGeometry.hitTestDualRing(point: outerNorth, center: center, metrics: metrics), .outer(0))

        // Sector 3: South (r = 150, dy = 150)
        let outerSouth = CGPoint(x: 200, y: 350)
        XCTAssertEqual(RadialDialGeometry.hitTestDualRing(point: outerSouth, center: center, metrics: metrics), .outer(3))

        // 4. Outside (> 220)
        let farPoint = CGPoint(x: 200, y: 200 + 250) // r = 250 > 220
        XCTAssertEqual(RadialDialGeometry.hitTestDualRing(point: farPoint, center: center, metrics: metrics), .outside)
    }

    func testDualRingPresetComposition() {
        let preset = RadialDialPresets.dualRingPage()
        XCTAssertEqual(preset.inner.count, 8, "Inner ring has 8 snap sectors")
        XCTAssertEqual(preset.outer.count, 6, "Outer ring has 6 capture/utility sectors")
    }

    // MARK: - SLICE RD-1: Polar Hit-Testing & Breadcrumb Navigation

    func testResolveSliceFourSixEightConfigurations() {
        for count in [4, 6, 8] {
            let sectors = RadialDialGeometry.sectors(count: count, innerRadius: innerRadius, outerRadius: outerRadius)
            for sector in sectors {
                let pt = sector.centerPoint(in: center, atFraction: 0.5)
                let resolved = RadialDialGeometry.resolveSlice(
                    at: pt,
                    center: center,
                    innerRadius: innerRadius,
                    outerRadius: outerRadius,
                    totalSlices: count
                )
                XCTAssertEqual(resolved, sector.index, "Expected slice \(sector.index) for \(count)-slice ring")
            }
        }
    }

    func testResolveSliceDeadzoneAndOutsideRejection() {
        XCTAssertNil(RadialDialGeometry.resolveSlice(at: center, center: center, innerRadius: innerRadius, outerRadius: outerRadius, totalSlices: 8))
        XCTAssertNil(RadialDialGeometry.resolveSlice(at: CGPoint(x: center.x + 25, y: center.y - 25), center: center, innerRadius: innerRadius, outerRadius: outerRadius, totalSlices: 6))
        XCTAssertNil(RadialDialGeometry.resolveSlice(at: CGPoint(x: center.x, y: center.y - outerRadius - 5), center: center, innerRadius: innerRadius, outerRadius: outerRadius, totalSlices: 4))
        XCTAssertNil(RadialDialGeometry.resolveSlice(at: CGPoint(x: center.x, y: center.y - 90), center: center, innerRadius: innerRadius, outerRadius: outerRadius, totalSlices: 0))
    }

    func testBreadcrumbNavigationDrillDownAndBack() {
        let leaf = RadialSliceNode(id: "leaf", title: "Maximize", icon: .sfSymbol("arrow.up.left.and.arrow.down.right"), action: .snap(.maximize))
        let nested = RadialSliceNode(id: "nested", title: "Advanced", icon: .sfSymbol("gear"), children: [leaf])
        let parent = RadialSliceNode(id: "parent", title: "Window", icon: .sfSymbol("macwindow"), children: [nested])
        var nav = RadialDialNavigationState(rootTitle: "Main", rootNodes: [parent])

        XCTAssertFalse(nav.canGoBack)
        XCTAssertEqual(nav.breadcrumbs, ["Main"])
        XCTAssertEqual(nav.selectSlice(at: 5), .invalid)

        XCTAssertEqual(nav.selectSlice(at: 0), .enteredSubmenu(parent))
        XCTAssertTrue(nav.canGoBack)
        XCTAssertEqual(nav.breadcrumbs, ["Main", "Window"])

        XCTAssertEqual(nav.selectSlice(at: 0), .enteredSubmenu(nested))
        XCTAssertEqual(nav.depth, 2)
        XCTAssertEqual(nav.breadcrumbs, ["Main", "Window", "Advanced"])

        XCTAssertEqual(nav.selectSlice(at: 0), .executed(.snap(.maximize), leaf))
        XCTAssertTrue(nav.goBack())
        XCTAssertEqual(nav.currentTitle, "Window")
        nav.popToRoot()
        XCTAssertFalse(nav.canGoBack)
        XCTAssertFalse(nav.goBack())
    }

    func testRadialSliceNodeCodableAndConfigStore() {
        let nodes = RadialDialPresets.defaultRootNodes()
        XCTAssertEqual(nodes.count, 8)
        let suiteName = "RadialDialConfigStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        RadialDialConfigStore.saveNodes(nodes, defaults: defaults)
        let loaded = RadialDialConfigStore.loadNodes(defaults: defaults)
        XCTAssertEqual(loaded, nodes)

        RadialDialConfigStore.reset(defaults: defaults)
        XCTAssertEqual(RadialDialConfigStore.loadNodes(defaults: defaults), RadialDialPresets.defaultRootNodes())
    }

    @MainActor
    func testRadialDialSettingsPageFitsWithin1074ptClamp() {
        let suiteName = "RadialDialSettingsHeightTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppSettingsStore(defaults: defaults)
        let view = SettingsPane {
            SettingsLayoutPane(store: store, mode: .radialDial)
        }
        .frame(width: SettingsMetrics.windowWidth)

        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        let measuredHeight = host.fittingSize.height
        XCTAssertGreaterThan(measuredHeight, 200)
        XCTAssertLessThanOrEqual(measuredHeight, 1074, "Radial Dial Settings pane height (\(measuredHeight) pt) must stay <= 1074 pt")
    }

    func testRadialDialDefaultKeyboardShortcut() {
        let expected = ShortcutTrigger.key(ShortcutKey(keyCode: 15, modifiers: ShortcutKey.control | ShortcutKey.option))
        XCTAssertEqual(ShortcutAction.radialDial.defaultTrigger, expected)
        if case .key(let key) = ShortcutAction.radialDial.defaultTrigger {
            XCTAssertEqual(key.glyphs, "⌃⌥R")
        } else {
            XCTFail("Expected key trigger for radialDial")
        }
        let defaults = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultTrigger) })
        XCTAssertEqual(ShortcutValidator.check(expected, for: .radialDial, among: defaults), .ok)
    }
}
