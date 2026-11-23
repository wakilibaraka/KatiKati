import XCTest
@testable import KatiKati

final class AppMembershipMenuPlanTests: XCTestCase {

    func testStripPlainAppShowsKeepAndUncheckedMessaging() {
        let defaultItems = AppMembershipMenuPlan.items(surface: .strip, isFinder: false, isKept: false, isMessaging: false)
        XCTAssertEqual(defaultItems, [.keep(isChecked: false)])

        let advancedItems = AppMembershipMenuPlan.items(
            surface: .strip, isFinder: false, isKept: false, isMessaging: false, showPinAsAppIcon: true
        )
        XCTAssertEqual(advancedItems, [.keep(isChecked: false), .messaging(isChecked: false)])
    }

    func testStripMessagingAppShowsKeepAndCheckedMessaging() {
        let items = AppMembershipMenuPlan.items(surface: .strip, isFinder: false, isKept: true, isMessaging: true)
        XCTAssertEqual(items, [.keep(isChecked: true), .messaging(isChecked: true)])
    }

    func testDrawerPlainAppShowsOnlyKeep() {
        let items = AppMembershipMenuPlan.items(surface: .drawer, isFinder: false, isKept: false, isMessaging: false)
        XCTAssertEqual(items, [.keep(isChecked: false)])
    }

    func testDrawerMessagingAppShowsKeepAndCheckedMessaging() {
        let items = AppMembershipMenuPlan.items(surface: .drawer, isFinder: false, isKept: true, isMessaging: true)
        XCTAssertEqual(items, [.keep(isChecked: true), .messaging(isChecked: true)])
    }

    /// 2026-08-20：访达纳入统一保留勾选，但消息项仍然不给（两个面都是）。
    func testFinderShowsOnlyKeep() {
        XCTAssertEqual(
            AppMembershipMenuPlan.items(surface: .strip, isFinder: true, isKept: true, isMessaging: false),
            [.keep(isChecked: true)]
        )
        XCTAssertEqual(
            AppMembershipMenuPlan.items(surface: .drawer, isFinder: true, isKept: false, isMessaging: false),
            [.keep(isChecked: false)]
        )
    }

    func testKeepCheckStateReflectsKept() {
        let unchecked = AppMembershipMenuPlan.items(surface: .strip, isFinder: false, isKept: false, isMessaging: false)
        XCTAssertEqual(unchecked.first, .keep(isChecked: false))
        let checked = AppMembershipMenuPlan.items(surface: .strip, isFinder: false, isKept: true, isMessaging: false)
        XCTAssertEqual(checked.first, .keep(isChecked: true))
    }

    func testKeepAlwaysPrecedesMessagingCommand() {
        let items = AppMembershipMenuPlan.items(surface: .strip, isFinder: false, isKept: false, isMessaging: true)
        XCTAssertEqual(items.first, .keep(isChecked: false))
        XCTAssertEqual(items.last, .messaging(isChecked: true))
    }

    func testMessagingCheckStateReflectsMembership() {
        XCTAssertEqual(
            AppMembershipMenuPlan.items(surface: .strip, isFinder: false, isKept: false, isMessaging: false, showPinAsAppIcon: false),
            [.keep(isChecked: false)]
        )
        XCTAssertEqual(
            AppMembershipMenuPlan.items(surface: .strip, isFinder: false, isKept: false, isMessaging: false, showPinAsAppIcon: true).last,
            .messaging(isChecked: false)
        )
        XCTAssertEqual(
            AppMembershipMenuPlan.items(surface: .strip, isFinder: false, isKept: false, isMessaging: true).last,
            .messaging(isChecked: true)
        )
    }
}
