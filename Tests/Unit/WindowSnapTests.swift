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

/// 54a: a plain click keeps its old meaning; the modifiers are the only change.
final class DockClickPolicyTests: XCTestCase {
    func testModifierTable() {
        XCTAssertEqual(DockClickPolicy.action(optionDown: false, commandDown: false), .toggle)
        XCTAssertEqual(DockClickPolicy.action(optionDown: true, commandDown: false), .hide)
        XCTAssertEqual(DockClickPolicy.action(optionDown: false, commandDown: true), .minimize)
        XCTAssertEqual(DockClickPolicy.action(optionDown: true, commandDown: true), .toggle,
                       "both modifiers are not a third action")
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

/// 24c/53d/53i: the app-rules table Settings draws is a view of the three stored lists, never a fourth
/// store — what the page shows is what the key tap and the window observer read.
final class QuitAppRulesTests: XCTestCase {
    func testThreeListsBecomeOneSortedTable() {
        let rules = QuitAppRules.parse(
            skipHold: "com.apple.TextEdit, com.apple.Preview",
            ownQuitKey: "com.apple.ScreenSharing",
            quitOnClose: "com.apple.Notes"
        )
        XCTAssertEqual(rules.rows.map(\.bundleID),
                       ["com.apple.Notes", "com.apple.Preview", "com.apple.ScreenSharing", "com.apple.TextEdit"])
        XCTAssertEqual(rules.row("com.apple.TextEdit")?.skipHold, true)
        XCTAssertEqual(rules.row("com.apple.ScreenSharing")?.ownQuitKey, true)
        XCTAssertEqual(rules.row("com.apple.Notes")?.quitOnClose, true)
    }

    func testListsSurviveTheRoundTrip() {
        let rules = QuitAppRules.parse(skipHold: "com.b.Two, com.a.One",
                                       ownQuitKey: "com.apple.ScreenSharing",
                                       quitOnClose: "com.apple.Notes")
        XCTAssertEqual(rules.skipHoldList, "com.a.One, com.b.Two")
        XCTAssertEqual(rules.ownQuitKeyList, "com.apple.ScreenSharing")
        XCTAssertEqual(rules.quitOnCloseList, "com.apple.Notes")
        let again = QuitAppRules.parse(skipHold: rules.skipHoldList, ownQuitKey: rules.ownQuitKeyList,
                                       quitOnClose: rules.quitOnCloseList)
        XCTAssertEqual(again, rules, "a write followed by a read must come back identical")
    }

    func testWhitespaceSeparatedListsStillParse() {
        let rules = QuitAppRules.parse(skipHold: "com.a.One  com.a.Two,com.a.Three", ownQuitKey: "", quitOnClose: "")
        XCTAssertEqual(rules.rows.count, 3, "every one of these keys has been space- or comma-separated since 24c")
    }

    func testAnOverlapReadsTheWayTheKeyTapResolvesIt() {
        // KeyGuardService checks pass-through before the deny list, so an app in both keeps its own ⌘Q.
        // Showing both switches on would describe a hold that never happens.
        let rules = QuitAppRules.parse(skipHold: "com.apple.Safari", ownQuitKey: "com.apple.Safari", quitOnClose: "")
        XCTAssertEqual(rules.row("com.apple.Safari")?.ownQuitKey, true)
        XCTAssertEqual(rules.row("com.apple.Safari")?.skipHold, false)
        XCTAssertEqual(rules.skipHoldList, "")
    }

    func testSwitchingOneQuitKeyColumnOnClearsTheOther() {
        var rules = QuitAppRules.parse(skipHold: "com.apple.Safari", ownQuitKey: "", quitOnClose: "")
        rules.set(.ownQuitKey, for: "com.apple.Safari", to: true)
        XCTAssertEqual(rules.row("com.apple.Safari")?.skipHold, false)
        XCTAssertEqual(rules.ownQuitKeyList, "com.apple.Safari")
        rules.set(.skipHold, for: "com.apple.Safari", to: true)
        XCTAssertEqual(rules.row("com.apple.Safari")?.ownQuitKey, false)
        XCTAssertEqual(rules.ownQuitKeyList, "")
    }

    func testTurningTheLastColumnOffDropsTheRow() {
        var rules = QuitAppRules()
        rules.set(.quitOnClose, for: "com.apple.TextEdit", to: true)
        XCTAssertEqual(rules.rows.count, 1, "a column switched on adds the app")
        rules.set(.quitOnClose, for: "com.apple.TextEdit", to: false)
        XCTAssertTrue(rules.rows.isEmpty, "a row with every column off would name an app that does nothing")
        XCTAssertEqual(rules.quitOnCloseList, "")
    }

    func testProtectedAppsNeverEnterTheQuitOnCloseList() {
        XCTAssertFalse(QuitOnLastWindowPolicy.allowsQuitOnClose("com.apple.finder"))
        XCTAssertTrue(QuitOnLastWindowPolicy.allowsQuitOnClose("com.apple.TextEdit"))

        let rules = QuitAppRules.parse(skipHold: "", ownQuitKey: "",
                                       quitOnClose: "com.apple.finder, com.katikati.app, com.apple.TextEdit")
        XCTAssertNil(rules.row("com.apple.finder"), "the policy ignores it, so the table must not claim it quits")
        XCTAssertNil(rules.row("com.katikati.app"))
        XCTAssertEqual(rules.quitOnCloseList, "com.apple.TextEdit")

        var edited = QuitAppRules()
        edited.set(.quitOnClose, for: "com.apple.finder", to: true)
        XCTAssertNil(edited.row("com.apple.finder"), "a protected app cannot be switched into that column")
    }

    func testProtectedAppsCanStillUseTheQuitKeyColumns() {
        var rules = QuitAppRules.parse(skipHold: "com.apple.finder", ownQuitKey: "", quitOnClose: "")
        XCTAssertEqual(rules.row("com.apple.finder")?.skipHold, true)
        rules.set(.ownQuitKey, for: "com.apple.finder", to: true)
        XCTAssertEqual(rules.row("com.apple.finder")?.skipHold, false)
        XCTAssertEqual(rules.ownQuitKeyList, "com.apple.finder")
    }

    func testBundleIDPlausibility() {
        XCTAssertTrue(QuitAppRules.isPlausibleBundleID("com.apple.Safari"))
        XCTAssertTrue(QuitAppRules.isPlausibleBundleID("  org.mozilla.firefox "))
        XCTAssertFalse(QuitAppRules.isPlausibleBundleID(""))
        XCTAssertFalse(QuitAppRules.isPlausibleBundleID("Safari"), "an app name is not a bundle ID")
        XCTAssertFalse(QuitAppRules.isPlausibleBundleID("com.apple Saf ara"))
        XCTAssertFalse(QuitAppRules.isPlausibleBundleID("/Applications/Safari.app"))
        XCTAssertFalse(QuitAppRules.isPlausibleBundleID(".com.apple.Safari"))
        XCTAssertFalse(QuitAppRules.isPlausibleBundleID("com.apple.Safari."))
    }

    func testBlankIDsAreIgnored() {
        var rules = QuitAppRules()
        rules.set(.skipHold, for: "   ", to: true)
        XCTAssertTrue(rules.rows.isEmpty)
        rules.remove("com.apple.Safari")
        XCTAssertTrue(rules.rows.isEmpty, "removing an app that is not there is a no-op")
    }
}
