import XCTest

final class NotchEdgeStyleTests: XCTestCase {
    func testSharpHasNoRadiiOrFlaresInEitherState() {
        for expanded in [true, false] {
            let m = NotchEdgeStyle.mask(sharp: true, expanded: expanded, hasHardwareNotch: true)
            XCTAssertEqual(m.top, 0)
            XCTAssertEqual(m.bottom, 0)
            XCTAssertFalse(m.flares)
        }
    }

    func testCurvedKeepsTheDesignRadiiAndFlaresOnlyOnAHardwareNotch() {
        let open = NotchEdgeStyle.mask(sharp: false, expanded: true, hasHardwareNotch: true)
        XCTAssertEqual(open.top, NotchDesignSpec.openCornerRadii.topFlaring)
        XCTAssertEqual(open.bottom, NotchDesignSpec.openCornerRadii.bottomSquircle)
        XCTAssertTrue(open.flares)
        let closed = NotchEdgeStyle.mask(sharp: false, expanded: false, hasHardwareNotch: false)
        XCTAssertEqual(closed.bottom, NotchDesignSpec.closedCornerRadii.bottomSquircle)
        XCTAssertFalse(closed.flares)
    }
}
