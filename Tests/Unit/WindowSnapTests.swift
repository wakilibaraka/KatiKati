import Foundation
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

    func testSnapZonePlannerResolvesEdgesAndCornersOnly() {
        let area = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let margin: CGFloat = 20
        XCTAssertEqual(SnapZonePlanner.edgeZone(at: CGPoint(x: 5, y: 400), in: area, edgeMargin: margin), .leftHalf)
        XCTAssertEqual(SnapZonePlanner.edgeZone(at: CGPoint(x: 995, y: 400), in: area, edgeMargin: margin), .rightHalf)
        XCTAssertEqual(SnapZonePlanner.edgeZone(at: CGPoint(x: 500, y: 795), in: area, edgeMargin: margin), .topHalf)
        XCTAssertEqual(SnapZonePlanner.edgeZone(at: CGPoint(x: 500, y: 5), in: area, edgeMargin: margin), .bottomHalf)
        XCTAssertEqual(SnapZonePlanner.edgeZone(at: CGPoint(x: 5, y: 795), in: area, edgeMargin: margin), .topLeft)
        XCTAssertEqual(SnapZonePlanner.edgeZone(at: CGPoint(x: 995, y: 795), in: area, edgeMargin: margin), .topRight)
        XCTAssertEqual(SnapZonePlanner.edgeZone(at: CGPoint(x: 5, y: 5), in: area, edgeMargin: margin), .bottomLeft)
        XCTAssertEqual(SnapZonePlanner.edgeZone(at: CGPoint(x: 995, y: 5), in: area, edgeMargin: margin), .bottomRight)
        XCTAssertNil(SnapZonePlanner.edgeZone(at: CGPoint(x: 500, y: 400), in: area, edgeMargin: margin))
        XCTAssertNil(SnapZonePlanner.edgeZone(at: CGPoint(x: 40, y: 400), in: area, edgeMargin: margin))
        XCTAssertNil(SnapZonePlanner.edgeZone(at: .zero, in: .zero))
    }

    func testSnapZonePlannerExposesThirdsCenterAndMaximizePreviews() {
        let area = CGRect(x: 100, y: 50, width: 900, height: 600)
        XCTAssertEqual(SnapZonePlanner.zones(in: area, layout: .edgesAndCorners).count, 8)
        XCTAssertEqual(SnapZonePlanner.zones(in: area, layout: .thirds).count, 5)
        XCTAssertEqual(SnapZonePlanner.zones(in: area, layout: .centerAndMaximize).count, 2)
        for zone in SnapZonePlanner.zones(in: area, layout: .thirds) {
            XCTAssertTrue(area.contains(zone.frame))
            XCTAssertEqual(zone.frame, zone.position.frame(in: area))
        }
        XCTAssertEqual(SnapZonePlanner.previewFrame(for: .maximize, in: area), area)
        XCTAssertEqual(SnapZonePlanner.previewFrame(for: .center, in: area), SnapPosition.center.frame(in: area))
    }

    func testGreenButtonBehaviorDefaultsAndRoundTrip() throws {
        XCTAssertEqual(GreenButtonBehavior.allCases.count, 2)
        XCTAssertEqual(GreenButtonBehavior.defaultValue, .nativeFullscreen)
        XCTAssertTrue(GreenButtonBehavior.nativeFullscreen.usesNativeFullscreen)
        XCTAssertFalse(GreenButtonBehavior.maximizeInCurrentSpace.usesNativeFullscreen)
        let decoded = try JSONDecoder().decode(GreenButtonBehavior.self,
                                               from: JSONEncoder().encode(GreenButtonBehavior.maximizeInCurrentSpace))
        XCTAssertEqual(decoded, .maximizeInCurrentSpace)
    }

    func testSnapZonePlannerResolvesEveryPointerLayout() {
        let area = CGRect(x: 100, y: 50, width: 900, height: 600)
        let left = SnapZonePlanner.resolve(at: CGPoint(x: 105, y: 350), in: area)
        XCTAssertEqual(left?.position, .leftHalf)
        XCTAssertEqual(left?.frame, SnapPosition.leftHalf.frame(in: area))

        XCTAssertEqual(SnapZonePlanner.resolve(at: CGPoint(x: 200, y: 350), in: area, layout: .thirds)?.position, .leftThird)
        XCTAssertEqual(SnapZonePlanner.resolve(at: CGPoint(x: 550, y: 350), in: area, layout: .thirds)?.position, .centerThird)
        XCTAssertEqual(SnapZonePlanner.resolve(at: CGPoint(x: 950, y: 350), in: area, layout: .thirds)?.position, .rightThird)

        XCTAssertEqual(SnapZonePlanner.resolve(at: CGPoint(x: 550, y: 350), in: area, layout: .centerAndMaximize)?.position, .center)
        XCTAssertEqual(SnapZonePlanner.resolve(at: CGPoint(x: 110, y: 60), in: area, layout: .centerAndMaximize)?.position, .maximize)
        XCTAssertNil(SnapZonePlanner.resolve(at: CGPoint(x: 0, y: 0), in: area, layout: .thirds))
        XCTAssertNil(SnapZonePlanner.resolve(at: CGPoint(x: 550, y: 350), in: .zero))
        XCTAssertEqual(SnapZonePlanner.dragLayout(optionDown: false), .edgesAndCorners)
        XCTAssertEqual(SnapZonePlanner.dragLayout(optionDown: true), .thirds)
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

    func testIdleAppAutoQuitPolicyEligibilityAndThresholds() {
        XCTAssertFalse(IdleAppAutoQuitPolicy.isEligible(bundleID: "com.apple.Safari"))
        XCTAssertFalse(IdleAppAutoQuitPolicy.isEligible(bundleID: "com.katikati.app"))
        XCTAssertTrue(IdleAppAutoQuitPolicy.isEligible(bundleID: "com.spotify.client"))
        XCTAssertTrue(IdleAppAutoQuitPolicy.isEligible(bundleID: "com.google.Chrome"))

        let disabledPolicy = IdleAppAutoQuitPolicy(idleThresholdSeconds: 0)
        XCTAssertFalse(disabledPolicy.shouldQuit(bundleID: "com.spotify.client", idleDuration: 7200))

        let policy = IdleAppAutoQuitPolicy(idleThresholdSeconds: 1800) // 30 mins
        XCTAssertFalse(policy.shouldQuit(bundleID: "com.spotify.client", idleDuration: 600))
        XCTAssertTrue(policy.shouldQuit(bundleID: "com.spotify.client", idleDuration: 1801))

        // Suppressed while playing media or when an AI agent is working
        XCTAssertFalse(policy.shouldQuit(bundleID: "com.spotify.client", idleDuration: 3600, isPlayingMedia: true))
        XCTAssertFalse(policy.shouldQuit(bundleID: "com.spotify.client", idleDuration: 3600, isAgentWorking: true))
        XCTAssertFalse(policy.shouldQuit(bundleID: "com.apple.Notes", idleDuration: 3600))
    }

    func testQuitOnLastWindowPolicyModesAndWindowFilter() {
        let offPolicy = QuitOnLastWindowPolicy.parse("com.spotify.client", mode: .off)
        XCTAssertFalse(offPolicy.applies(to: "com.spotify.client"))

        let globalPolicy = QuitOnLastWindowPolicy.parse("", mode: .allExceptExcluded, excludedRaw: "com.tinyspeck.slackmacgap")
        XCTAssertTrue(globalPolicy.applies(to: "com.spotify.client"))
        XCTAssertFalse(globalPolicy.applies(to: "com.tinyspeck.slackmacgap"))
        XCTAssertFalse(globalPolicy.applies(to: "com.apple.finder"), "system surfaces remain always ignored")

        XCTAssertTrue(QuitOnLastWindowPolicy.isCountableWindow(subrole: "AXStandardWindow", size: CGSize(width: 800, height: 600)))
        XCTAssertTrue(QuitOnLastWindowPolicy.isCountableWindow(subrole: "AXDialog", size: CGSize(width: 400, height: 300)))
        XCTAssertFalse(QuitOnLastWindowPolicy.isCountableWindow(subrole: "AXUnknown", size: CGSize(width: 400, height: 300)))
        XCTAssertFalse(QuitOnLastWindowPolicy.isCountableWindow(subrole: "AXStandardWindow", size: .zero))
        XCTAssertEqual(QuitOnLastWindowPolicy.clampDelay(0.05), 0.25)
        XCTAssertEqual(QuitOnLastWindowPolicy.clampDelay(10.0), 5.0)
    }

    func testIdleAppPolicyActionsMemoryAndPerAppOverrides() {
        let oneGB: UInt64 = 1024 * 1024 * 1024
        let overrides = IdleAppAutoQuitPolicy.parsePerAppActions("com.tinyspeck.slackmacgap=keep, com.spotify.client=hide")
        XCTAssertEqual(IdleAppAutoQuitPolicy.serializePerAppActions(overrides), "com.spotify.client=hide, com.tinyspeck.slackmacgap=keep")

        let policy = IdleAppAutoQuitPolicy(
            idleThresholdSeconds: 1800,
            defaultAction: .notify,
            minMemoryBytes: oneGB,
            perAppActions: overrides
        )
        // Below RAM filter -> nil even when idle
        XCTAssertNil(policy.resolvedAction(bundleID: "com.google.Chrome", idleDuration: 2400, memoryBytes: 500 * 1024 * 1024))
        // Idle AND above RAM filter -> .notify
        XCTAssertEqual(policy.resolvedAction(bundleID: "com.google.Chrome", idleDuration: 2400, memoryBytes: 2 * oneGB), .notify)
        // Per-app .keep suppresses
        XCTAssertNil(policy.resolvedAction(bundleID: "com.tinyspeck.slackmacgap", idleDuration: 3600, memoryBytes: 2 * oneGB))
        // Per-app .hide overrides default .notify
        XCTAssertEqual(policy.resolvedAction(bundleID: "com.spotify.client", idleDuration: 2400, memoryBytes: 2 * oneGB), .hide)
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
