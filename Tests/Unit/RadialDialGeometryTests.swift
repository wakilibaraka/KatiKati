import XCTest
import CoreGraphics
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
}
