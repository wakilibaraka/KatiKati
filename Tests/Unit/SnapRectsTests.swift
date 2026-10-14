import XCTest
@testable import KatiKati

/// Golden tests for `SnapRects.rect(for:in:)` (Phase 26a).
/// Canonical screen: 1440 × 900, visibleFrame y=40 (taskbar height 40 pt).
final class SnapRectsTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 40, width: 1440, height: 860)

    // MARK: - Halves

    func testLeftHalf() {
        let r = SnapRects.rect(for: .leftHalf, in: screen)
        XCTAssertEqual(r, CGRect(x: 0, y: 40, width: 720, height: 860))
    }

    func testRightHalf() {
        let r = SnapRects.rect(for: .rightHalf, in: screen)
        XCTAssertEqual(r, CGRect(x: 720, y: 40, width: 720, height: 860))
    }

    func testTopHalf() {
        let r = SnapRects.rect(for: .topHalf, in: screen)
        XCTAssertEqual(r, CGRect(x: 0, y: 470, width: 1440, height: 430))
    }

    func testBottomHalf() {
        let r = SnapRects.rect(for: .bottomHalf, in: screen)
        XCTAssertEqual(r, CGRect(x: 0, y: 40, width: 1440, height: 430))
    }

    // MARK: - Quarters

    func testTopLeft() {
        let r = SnapRects.rect(for: .topLeft, in: screen)
        XCTAssertEqual(r, CGRect(x: 0, y: 470, width: 720, height: 430))
    }

    func testTopRight() {
        let r = SnapRects.rect(for: .topRight, in: screen)
        XCTAssertEqual(r, CGRect(x: 720, y: 470, width: 720, height: 430))
    }

    func testBottomLeft() {
        let r = SnapRects.rect(for: .bottomLeft, in: screen)
        XCTAssertEqual(r, CGRect(x: 0, y: 40, width: 720, height: 430))
    }

    func testBottomRight() {
        let r = SnapRects.rect(for: .bottomRight, in: screen)
        XCTAssertEqual(r, CGRect(x: 720, y: 40, width: 720, height: 430))
    }

    // MARK: - Thirds

    func testLeftThird() {
        let r = SnapRects.rect(for: .leftThird, in: screen)
        XCTAssertEqual(r.minX, 0, accuracy: 1)
        XCTAssertEqual(r.width, 480, accuracy: 1)
    }

    func testCenterThird() {
        let r = SnapRects.rect(for: .centerThird, in: screen)
        XCTAssertEqual(r.minX, 480, accuracy: 1)
        XCTAssertEqual(r.width, 480, accuracy: 1)
    }

    func testRightThird() {
        let r = SnapRects.rect(for: .rightThird, in: screen)
        XCTAssertEqual(r.maxX, 1440, accuracy: 1)
        XCTAssertEqual(r.width, 480, accuracy: 1)
    }

    func testLeftTwoThirds() {
        let r = SnapRects.rect(for: .leftTwoThirds, in: screen)
        XCTAssertEqual(r.minX, 0, accuracy: 1)
        XCTAssertEqual(r.width, 960, accuracy: 1)
    }

    func testRightTwoThirds() {
        let r = SnapRects.rect(for: .rightTwoThirds, in: screen)
        XCTAssertEqual(r.maxX, 1440, accuracy: 1)
        XCTAssertEqual(r.width, 960, accuracy: 1)
    }

    // MARK: - Full

    func testCenter() {
        let r = SnapRects.rect(for: .center, in: screen)
        // unit: x=0.125, y=0.1, w=0.75, h=0.8 → inside screen
        XCTAssertGreaterThan(r.minX, screen.minX)
        XCTAssertGreaterThan(r.minY, screen.minY)
        XCTAssertLessThan(r.maxX, screen.maxX + 1)
        XCTAssertLessThan(r.maxY, screen.maxY + 1)
    }

    func testMaximize() {
        let r = SnapRects.rect(for: .maximize, in: screen)
        XCTAssertEqual(r, screen)
    }

    // MARK: - Invariants

    func testAllZonesStayInsideScreen() {
        for pos in SnapPosition.allCases {
            let r = SnapRects.rect(for: pos, in: screen)
            XCTAssertGreaterThanOrEqual(r.minX, screen.minX - 1, "\(pos)")
            XCTAssertGreaterThanOrEqual(r.minY, screen.minY - 1, "\(pos)")
            XCTAssertLessThanOrEqual(r.maxX, screen.maxX + 1, "\(pos)")
            XCTAssertLessThanOrEqual(r.maxY, screen.maxY + 1, "\(pos)")
        }
    }

    func testHalvesCoverEntireScreen() {
        let l = SnapRects.rect(for: .leftHalf, in: screen)
        let r = SnapRects.rect(for: .rightHalf, in: screen)
        XCTAssertEqual(l.union(r), screen)
    }

    func testQuartersCoverEntireScreen() {
        let area = [SnapPosition.topLeft, .topRight, .bottomLeft, .bottomRight]
            .map { SnapRects.rect(for: $0, in: screen) }
            .reduce(0) { $0 + $1.width * $1.height }
        XCTAssertEqual(area, screen.width * screen.height, accuracy: 4)
    }

    func testThreeTirdsWidthEqualsScreen() {
        let w = [SnapPosition.leftThird, .centerThird, .rightThird]
            .map { SnapRects.rect(for: $0, in: screen).width }
            .reduce(0, +)
        XCTAssertEqual(w, screen.width, accuracy: 3)
    }

    func testMultiDisplayOffsetScreen() {
        let second = CGRect(x: 1440, y: 0, width: 2560, height: 1440)
        let r = SnapRects.rect(for: .leftHalf, in: second)
        XCTAssertEqual(r.minX, 1440)
        XCTAssertEqual(r.width, 1280)
    }
}
