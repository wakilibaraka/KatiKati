import XCTest
@testable import KatiKati

final class WindowSnapTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 40, width: 1440, height: 800)

    func testHalvesAndQuartersTileTheVisibleArea() {
        let l = SnapPosition.leftHalf.frame(in: visible), r = SnapPosition.rightHalf.frame(in: visible)
        XCTAssertEqual(l.maxX, r.minX)
        XCTAssertEqual(l.union(r), visible)
        let quarters = [SnapPosition.topLeft, .topRight, .bottomLeft, .bottomRight].map { $0.frame(in: visible) }
        XCTAssertEqual(quarters.reduce(0) { $0 + $1.width * $1.height }, visible.width * visible.height)
        XCTAssertEqual(SnapPosition.topLeft.frame(in: visible).maxY, visible.maxY, "top zones hug the top")
    }

    func testThirdsAndMaximizeAndOffsetOrigin() {
        let thirds = [SnapPosition.leftThird, .centerThird, .rightThird].map { $0.frame(in: visible) }
        XCTAssertEqual(thirds.reduce(0) { $0 + $1.width }, visible.width, accuracy: 2)
        XCTAssertEqual(SnapPosition.maximize.frame(in: visible), visible)
        let second = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
        XCTAssertEqual(SnapPosition.rightHalf.frame(in: second).minX, 1440 + 960)
        XCTAssertEqual(SnapPosition.bottomHalf.frame(in: second).minY, -200)
    }

    func testAccessibilityOriginFlipsToTopLeft() {
        let cocoa = CGRect(x: 100, y: 40, width: 500, height: 400)   // bottom edge 40, top edge 440
        let p = SnapPosition.accessibilityOrigin(of: cocoa, primaryMaxY: 900)
        XCTAssertEqual(p, CGPoint(x: 100, y: 460))
    }

    func testEveryZoneStaysInsideTheUnitSquare() {
        for zone in SnapPosition.allCases {
            let u = zone.unit
            XCTAssertGreaterThanOrEqual(u.minX, 0); XCTAssertGreaterThanOrEqual(u.minY, 0)
            XCTAssertLessThanOrEqual(u.maxX, 1.000001); XCTAssertLessThanOrEqual(u.maxY, 1.000001)
        }
        XCTAssertEqual(SnapPosition.allCases.count, 15)
    }
}

/// 53d: opt-in per app, empty by default, and only the some-to-none transition quits.
final class QuitOnLastWindowPolicyTests: XCTestCase {
    func testEmptyListIsOffAndProtectedAppsAreNeverOurs() {
        XCTAssertFalse(QuitOnLastWindowPolicy.parse("").applies(to: "com.apple.TextEdit"))
        let policy = QuitOnLastWindowPolicy.parse("com.apple.TextEdit, com.apple.finder, com.katikati.app")
        XCTAssertTrue(policy.applies(to: "com.apple.TextEdit"))
        XCTAssertFalse(policy.applies(to: "com.apple.finder"))
        XCTAssertFalse(policy.applies(to: "com.katikati.app"))
        XCTAssertFalse(policy.applies(to: nil))
    }

    func testOnlySomeToNoneQuitsAndAnUnknownReadNeverDoes() {
        XCTAssertTrue(QuitOnLastWindowPolicy.shouldQuit(hadWindow: true, windowCount: 0))
        XCTAssertFalse(QuitOnLastWindowPolicy.shouldQuit(hadWindow: true, windowCount: 2))
        XCTAssertFalse(QuitOnLastWindowPolicy.shouldQuit(hadWindow: false, windowCount: 0),
                       "an app that never had a window (launch, background activation) is left alone")
        XCTAssertFalse(QuitOnLastWindowPolicy.shouldQuit(hadWindow: true, windowCount: nil),
                       "a failed AX read is unknown, never zero")
    }
}
