import XCTest
@testable import KatiKati

final class WidgetDensityPolicyTests: XCTestCase {
    func testCompactDropsSparklinesAndCaptionsBeforeTruncatingNumbers() {
        let lowDock = WidgetDensityPolicy.resolve(dockHeight: 38, widgetSize: .large)
        XCTAssertEqual(lowDock.tier, .compact)
        XCTAssertFalse(lowDock.showsSparkline)
        XCTAssertFalse(lowDock.showsSecondaryCaption)
        XCTAssertFalse(lowDock.showsDeviceName)

        let smallWidget = WidgetDensityPolicy.resolve(dockHeight: 72, widgetSize: .small)
        XCTAssertEqual(smallWidget.tier, .compact)
        XCTAssertFalse(smallWidget.showsSparkline)
    }

    func testRegularAndSpaciousExposeProgressiveDetail() {
        let regularTight = WidgetDensityPolicy.resolve(dockHeight: 46, widgetSize: .medium)
        XCTAssertEqual(regularTight.tier, .regular)
        XCTAssertFalse(regularTight.showsSparkline)
        XCTAssertTrue(regularTight.showsSecondaryCaption)
        XCTAssertFalse(regularTight.showsDeviceName)

        let regularTall = WidgetDensityPolicy.resolve(dockHeight: 54, widgetSize: .medium)
        XCTAssertTrue(regularTall.showsSparkline)

        let spacious = WidgetDensityPolicy.resolve(dockHeight: 68, widgetSize: .large)
        XCTAssertEqual(spacious.tier, .spacious)
        XCTAssertTrue(spacious.showsSparkline)
        XCTAssertTrue(spacious.showsSecondaryCaption)
        XCTAssertTrue(spacious.showsDeviceName)
    }
}
