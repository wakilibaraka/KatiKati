import Foundation
import XCTest
@testable import KatiKati

@MainActor
final class SnapPickerModelTests: XCTestCase {
    func testSelectionStartsEmptyAndArrowNavigationClampsToAvailableZones() {
        let model = SnapPickerModel()
        XCTAssertNil(model.selected)
        XCTAssertNil(model.selectedZone)
        model.move(by: 1)
        XCTAssertEqual(model.selected, 0)
        XCTAssertEqual(model.selectedZone, .leftHalf)
        model.move(by: 1)
        XCTAssertEqual(model.selected, 0)
        XCTAssertEqual(model.selectedZone, .rightHalf)
        model.move(by: 100)
        XCTAssertEqual(model.selected, SnapLayoutCatalog.presets.count - 1)
        XCTAssertEqual(model.selectedZone, .maximize)
        model.move(by: -100)
        XCTAssertEqual(model.selected, 0)
        XCTAssertEqual(model.selectedZone, .leftHalf)
    }

    func testPickDismissesBeforeApplyingAnyChosenZone() {
        let model = SnapPickerModel()
        var order: [String] = []
        var picked: [SnapPosition] = []
        model.onDismiss = { order.append("dismiss") }
        model.onPick = { zone in order.append("apply"); picked.append(zone) }
        model.pick(2)
        model.pick(zone: .rightHalf)
        model.pick(zone: .bottomRight)
        model.pick(zone: .centerThird)
        XCTAssertEqual(order, ["dismiss", "apply", "dismiss", "apply", "dismiss", "apply", "dismiss", "apply"])
        XCTAssertEqual(picked, [.leftThird, .rightHalf, .bottomRight, .centerThird])
    }
}

final class WindowInspectorMathTests: XCTestCase {
    func testCocoaFrameHandlesStackedExternalDisplaysWithNegativeQuartzY() {
        let quartz = CGRect(x: -164, y: -900, width: 1200, height: 800)
        let cocoa = WindowInspectorMath.cocoaFrame(fromQuartz: quartz, primaryMaxY: 1112)
        XCTAssertEqual(cocoa, CGRect(x: -164, y: 1212, width: 1200, height: 800))
    }

    func testCpuPercentScalesMachTimebaseAndResetsAcrossPidChange() {
        // Apple Silicon timebase: 125 / 3 ns per tick. 24_000_000 ticks = 1_000_000_000 ns (100% of 1s).
        let pct = WindowInspectorMath.cpuPercent(
            previous: (pid: 100, wall: 10.0, ticks: 1_000_000),
            current: (pid: 100, wall: 11.0, ticks: 25_000_000),
            timebaseNumer: 125,
            timebaseDenom: 3
        )
        XCTAssertEqual(pct, 100.0, accuracy: 0.001)

        let pidChanged = WindowInspectorMath.cpuPercent(
            previous: (pid: 100, wall: 10.0, ticks: 1_000_000),
            current: (pid: 200, wall: 11.0, ticks: 99_000_000),
            timebaseNumer: 125,
            timebaseDenom: 3
        )
        XCTAssertEqual(pidChanged, 0)
    }
}

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
        XCTAssertEqual(SnapPosition.allCases.count, 16, "AT-7 added the focus size")
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

    func testSnapGapsClampingAndDefaults() {
        let clamped = SnapGaps(outer: -8, inner: 99)
        XCTAssertEqual(clamped, SnapGaps(outer: 0, inner: 32))

        let suiteName = "com.katikati.tests.snapgaps.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        XCTAssertEqual(SnapGaps.current(defaults: defaults), .zero)

        defaults.set(14.0, forKey: SnapGaps.outerKey)
        defaults.set(8.0, forKey: SnapGaps.innerKey)
        XCTAssertEqual(SnapGaps.current(defaults: defaults), SnapGaps(outer: 14, inner: 8))
    }

    func testSnapPositionFrameWithOuterAndInnerGaps() {
        let area = CGRect(x: 0, y: 40, width: 1000, height: 600)
        let gaps = SnapGaps(outer: 10, inner: 12) // padded: (10, 50, 980, 580)

        let maxFrame = SnapPosition.maximize.frame(in: area, gaps: gaps)
        XCTAssertEqual(maxFrame, CGRect(x: 10, y: 50, width: 980, height: 580))

        let left = SnapPosition.leftHalf.frame(in: area, gaps: gaps)
        let right = SnapPosition.rightHalf.frame(in: area, gaps: gaps)
        XCTAssertEqual(left, CGRect(x: 10, y: 50, width: 484, height: 580))
        XCTAssertEqual(right, CGRect(x: 506, y: 50, width: 484, height: 580))
        XCTAssertEqual(right.minX - left.maxX, 12)

        let topLeft = SnapPosition.topLeft.frame(in: area, gaps: gaps)
        let bottomRight = SnapPosition.bottomRight.frame(in: area, gaps: gaps)
        XCTAssertEqual(topLeft, CGRect(x: 10, y: 346, width: 484, height: 284))
        XCTAssertEqual(bottomRight, CGRect(x: 506, y: 50, width: 484, height: 284))
        XCTAssertEqual(topLeft.minY - bottomRight.maxY, 12)

        let twoThirds = SnapPosition.leftTwoThirds.frame(in: area, gaps: SnapGaps(outer: 10, inner: 0))
        XCTAssertEqual(twoThirds, CGRect(x: 10, y: 50, width: 653, height: 580))
    }

    func testSnapZonePlannerAndDockClearanceParity() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let gaps = SnapGaps(outer: 8, inner: 10)

        let bottomArea = DockReserve.workArea(visible: visible, screen: screen,
                                              dock: CGRect(x: 320, y: 0, width: 800, height: 70))
        let bottomZone = SnapZonePlanner.resolve(at: CGPoint(x: 2, y: 400), in: bottomArea,
                                                 layout: .edgesAndCorners, edgeMargin: 12, gaps: gaps)
        XCTAssertEqual(bottomZone?.position, .leftHalf)
        XCTAssertEqual(bottomZone?.frame, SnapPosition.leftHalf.frame(in: bottomArea, gaps: gaps))
        XCTAssertGreaterThanOrEqual(bottomZone?.frame.minY ?? 0, 78)

        let leftArea = DockReserve.workArea(visible: visible, screen: screen,
                                            dock: CGRect(x: 0, y: 150, width: 64, height: 600))
        XCTAssertEqual(SnapPosition.leftHalf.frame(in: leftArea, gaps: gaps).minX, 72)

        let rightArea = DockReserve.workArea(visible: visible, screen: screen,
                                             dock: CGRect(x: 1376, y: 150, width: 64, height: 600))
        XCTAssertEqual(SnapPosition.rightHalf.frame(in: rightArea, gaps: gaps).maxX, 1368)
    }

    func testSnapDragSessionSeedsOnceAndRejectsOutsideDrags() {
        var session = SnapDragSession()
        let windowFrame = CGRect(x: 200, y: 150, width: 800, height: 500)
        let pressID = session.beginPress(at: CGPoint(x: 50, y: 50))
        XCTAssertFalse(session.isIdle, "subsequent drag ticks must not re-seed the same press")
        XCTAssertNil(session.seededPressID)

        session.applySeed(pressID: pressID, windowFrameCocoa: windowFrame, windowOriginQuartz: CGPoint(x: 200, y: 250))
        XCTAssertEqual(session.phase, .rejected(pressID: pressID))
        XCTAssertNil(session.seededPressID, "rejected desktop/outside drags never poll AXPosition again")
        XCTAssertFalse(session.isTracking)

        let edgeZone = SnapZonePlanner.resolve(at: CGPoint(x: 2, y: 400), in: visible)
        XCTAssertNil(session.finishPress(activeZone: edgeZone))
        XCTAssertTrue(session.isIdle)
    }

    func testSnapDragSessionIgnoresInteriorScrollbarAndTextDrags() {
        var session = SnapDragSession()
        let windowFrame = CGRect(x: 100, y: 100, width: 900, height: 600)
        let initialOrigin = CGPoint(x: 100, y: 200)
        let pressID = session.beginPress(at: CGPoint(x: 992, y: 400))
        session.applySeed(pressID: pressID, windowFrameCocoa: windowFrame, windowOriginQuartz: initialOrigin)
        XCTAssertEqual(session.seededPressID, pressID)

        // Dragging a scrollbar or text selection all the way to the screen edge leaves AXPosition unchanged.
        XCTAssertFalse(session.observeWindowOrigin(initialOrigin, pressID: pressID))
        XCTAssertFalse(session.observeWindowOrigin(CGPoint(x: 101.2, y: 200.5), pressID: pressID), "sub-2pt jitter stays disarmed")
        XCTAssertFalse(session.isTracking)

        let rightZone = SnapZonePlanner.resolve(at: CGPoint(x: 1438, y: 400), in: visible)
        XCTAssertNotNil(rightZone)
        XCTAssertNil(session.finishPress(activeZone: rightZone), "interior drags must never snap on release")
    }

    func testSnapDragSessionArmsOnRealWindowMoveAndIgnoresStalePressIDs() {
        var session = SnapDragSession()
        let windowFrame = CGRect(x: 200, y: 150, width: 800, height: 500)
        let initialOrigin = CGPoint(x: 200, y: 250)
        let staleID = session.beginPress(at: CGPoint(x: 400, y: 640))
        let activeID = session.beginPress(at: CGPoint(x: 400, y: 640))

        session.applySeed(pressID: staleID, windowFrameCocoa: nil, windowOriginQuartz: nil)
        XCTAssertEqual(session.phase, .seeding(pressID: activeID, mouseDown: CGPoint(x: 400, y: 640)))

        session.applySeed(pressID: activeID, windowFrameCocoa: windowFrame, windowOriginQuartz: initialOrigin)
        XCTAssertTrue(session.observeWindowOrigin(CGPoint(x: 202.5, y: 250), pressID: activeID))
        XCTAssertTrue(session.isTracking)
        XCTAssertNil(session.seededPressID, "once armed, drag ticks stop polling AXPosition")

        let leftZone = SnapZonePlanner.resolve(at: CGPoint(x: 4, y: 400), in: visible)
        XCTAssertEqual(session.finishPress(activeZone: leftZone), leftZone)
        XCTAssertTrue(session.isIdle)
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

    func testAXMessagingPolicyHasBoundedTimeoutAndAppliesToElement() {
        XCTAssertEqual(AXMessagingPolicy.defaultTimeoutSeconds, 0.15, accuracy: 1e-6)
        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        XCTAssertTrue(AXMessagingPolicy.applyTimeout(app) === app)
    }
}

// MARK: - SN-1: snApp catalog and shake gate

extension WindowSnapTests {
    func testSnapCatalogLeadsWithVerticalHalves() {
        let first = SnapLayoutCatalog.presets.first
        XCTAssertEqual(first?.id, "halves")
        XCTAssertEqual(first?.zones, [.leftHalf, .rightHalf], "the pointer arrives from an edge")
        let everyZone = SnapLayoutCatalog.presets.flatMap(\.zones)
        XCTAssertTrue(everyZone.contains(.topHalf), "AT-7 added the vertical pair")
        XCTAssertTrue(everyZone.contains(.bottomHalf))
        XCTAssertEqual(SnapLayoutCatalog.presets.count, 8, "two rows of four")
    }

    func testSnapCatalogCoversPickerZonesWithoutRepeatingOne() {
        let everyZone = SnapLayoutCatalog.presets.flatMap(\.zones)
        XCTAssertEqual(Set(everyZone).count, everyZone.count, "a zone on two cards is a mis-click waiting")
        XCTAssertEqual(Set(everyZone), [.leftHalf, .rightHalf, .topLeft, .topRight, .bottomLeft, .bottomRight,
                                        .leftThird, .centerThird, .rightThird,
                                        .leftTwoThirds, .rightTwoThirds, .maximize,
                                        .topHalf, .bottomHalf, .center, .focus])
        XCTAssertEqual(everyZone.count, 16)
    }

    func testSnapCatalogSchematicStaysInsideTheCard() {
        for preset in SnapLayoutCatalog.presets {
            XCTAssertFalse(preset.areas.isEmpty, preset.id)
            for area in preset.areas {
                XCTAssertGreaterThan(area.unit.width, 0, preset.id)
                XCTAssertGreaterThan(area.unit.height, 0, preset.id)
                XCTAssertGreaterThanOrEqual(area.unit.minX, 0, preset.id)
                XCTAssertGreaterThanOrEqual(area.unit.minY, 0, preset.id)
                XCTAssertLessThanOrEqual(area.unit.maxX, 1.000001, preset.id)
                XCTAssertLessThanOrEqual(area.unit.maxY, 1.000001, preset.id)
            }
        }
    }

    func testSnapCatalogHitTestsTheShapeUnderThePointer() {
        for preset in SnapLayoutCatalog.presets {
            for area in preset.areas {
                let center = CGPoint(x: area.unit.midX, y: area.unit.midY)
                XCTAssertEqual(SnapLayoutCatalog.area(at: center, in: preset)?.zone, area.zone, preset.id)
            }
            XCTAssertNil(SnapLayoutCatalog.area(at: CGPoint(x: -0.1, y: 0.5), in: preset), preset.id)
            XCTAssertNil(SnapLayoutCatalog.area(at: CGPoint(x: 0.5, y: 1.1), in: preset), preset.id)
        }
    }

    func testSnapCatalogTwoThirdsCardIsDrawnAsTwoLabelledHalves() throws {
        let card = try XCTUnwrap(SnapLayoutCatalog.preset(id: "twoThirds"))
        XCTAssertEqual(card.zones, [.leftTwoThirds, .rightTwoThirds])
        XCTAssertEqual(card.areas.map(\.label), ["⅔", "⅔"])
        XCTAssertEqual(card.areas.map(\.unit), [CGRect(x: 0, y: 0, width: 0.5, height: 1),
                                               CGRect(x: 0.5, y: 0, width: 0.5, height: 1)],
                       "the drawing splits, the frame does not")
        XCTAssertNil(SnapLayoutCatalog.preset(id: "no-such-card"))
    }

    private func feedGate(_ gate: inout SnapShakeGate, _ xs: [Double],
                          start: TimeInterval = 0, step: TimeInterval = 0.05) -> Int {
        var opens = 0
        for (i, x) in xs.enumerated() where gate.add(x: x, at: start + Double(i) * step) { opens += 1 }
        return opens
    }

    func testSnapShakeGateFiresOncePerPress() {
        var gate = SnapShakeGate()
        gate.beginPress(1)
        XCTAssertEqual(feedGate(&gate, [0, 50, 0, 50, 0, 50, 0]), 1)
        XCTAssertEqual(feedGate(&gate, [100, 50, 100, 50, 100, 50, 100], start: 0.4), 0,
                       "one picker per press, however long the drag lasts")
        gate.endPress()
    }

    func testSnapShakeGateIgnoresSamplesOutsideAPress() {
        var gate = SnapShakeGate()
        XCTAssertEqual(feedGate(&gate, [0, 50, 0, 50, 0, 50, 0]), 0, "a hover is not a drag")
    }

    func testSnapShakeGateIgnoresAStraightDrag() {
        var gate = SnapShakeGate()
        gate.beginPress(7)
        XCTAssertEqual(feedGate(&gate, Array(stride(from: 0.0, to: 600, by: 20))), 0)
        gate.endPress()
    }

    func testSnapShakeGateKeepsTheDetectorCooldownAcrossPresses() {
        var gate = SnapShakeGate()
        gate.beginPress(1)
        XCTAssertEqual(feedGate(&gate, [0, 50, 0, 50, 0, 50, 0]), 1)
        gate.endPress()
        gate.beginPress(2)
        XCTAssertEqual(feedGate(&gate, [0, 50, 0, 50, 0, 50, 0], start: 0.4), 0, "inside the cooldown")
        gate.endPress()
        gate.beginPress(3)
        XCTAssertEqual(feedGate(&gate, [0, 50, 0, 50, 0, 50, 0], start: 3), 1, "after the cooldown")
        gate.endPress()
    }

}

// MARK: - AT-7: picker placement, density and the expanded catalog

final class SnapPickerGeometryTests: XCTestCase {
    private let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let visibleFrame = CGRect(x: 0, y: 0, width: 1920, height: 1050)
    private let panelSize = CGSize(width: 420, height: 190)

    private func frame(_ placement: SnapPanelPlacement, pointer: CGPoint = CGPoint(x: 1700, y: 80),
                       notch: CGFloat = 0, menu: CGFloat = 30, anchor: CGRect? = nil) -> CGRect {
        SnapPanelGeometry.frame(placement: placement, panelSize: panelSize, pointer: pointer,
                                screenFrame: screenFrame, visibleFrame: visibleFrame, anchor: anchor,
                                notchInset: notch, menuBarHeight: menu)
    }

    func testScreenCentreIsCentredOnTheVisibleFrame() {
        let f = frame(.screenCentre)
        XCTAssertEqual(f.midX, visibleFrame.midX, accuracy: 1)
        XCTAssertEqual(f.midY, visibleFrame.midY, accuracy: 1)
        XCTAssertEqual(f.size, panelSize)
    }

    func testBelowNotchAndBelowMenuBarHangFromTheTopEdge() {
        let notch = frame(.belowNotch, notch: 37.5, menu: 38)
        XCTAssertEqual(notch.maxY, screenFrame.maxY - 37.5 - 8, accuracy: 1)
        XCTAssertEqual(notch.midX, screenFrame.midX, accuracy: 1)

        let menu = frame(.belowMenuBar, notch: 37.5, menu: 38)
        XCTAssertEqual(menu.maxY, screenFrame.maxY - 38 - 8, accuracy: 1)
        XCTAssertLessThan(menu.maxY, notch.maxY)
    }

    func testFullScreenOverlayFillsTheVisibleFrameWithAComfortableInset() {
        let f = frame(.fullScreen)
        XCTAssertEqual(f, visibleFrame.insetBy(dx: 24, dy: 24))
    }

    func testFollowPointerNeverLeavesTheVisibleFrame() {
        for pointer in [CGPoint(x: 0, y: 0), CGPoint(x: 1920, y: 1080), CGPoint(x: 960, y: 540)] {
            let f = frame(.followPointer, pointer: pointer)
            XCTAssertTrue(visibleFrame.insetBy(dx: 8, dy: 8).contains(f), "\(pointer) put the panel at \(f)")
        }
    }

    func testDensityChangesCardSizeButNotTheColumnCount() {
        XCTAssertEqual(SnapGridDensity.compact.cardSize, CGSize(width: 78, height: 56))
        XCTAssertEqual(SnapGridDensity.regular.cardSize, CGSize(width: 94, height: 66))
        XCTAssertEqual(SnapGridDensity.large.cardSize, CGSize(width: 118, height: 82))
        XCTAssertEqual(Set(SnapGridDensity.allCases.map(\.columns)), [4])
        XCTAssertLessThan(SnapGridDensity.compact.spacing, SnapGridDensity.large.spacing)
    }

    func testCatalogHasTwoRowsOfFourLabelledCards() {
        XCTAssertEqual(SnapLayoutCatalog.presets.count, 8)
        XCTAssertEqual(Set(SnapLayoutCatalog.presets.map(\.id)).count, 8)
        XCTAssertEqual(SnapLayoutCatalog.presets.first?.id, "halves")
        XCTAssertEqual(SnapLayoutCatalog.presets.last?.id, "maximize")
        for preset in SnapLayoutCatalog.presets {
            XCTAssertFalse(SnapLayoutCatalog.titleKey(for: preset).isEmpty)
        }
    }

    func testFocusIsNarrowerThanComfortableAndCentred() {
        let focus = SnapPosition.focus.unit
        let comfortable = SnapPosition.center.unit
        XCTAssertLessThan(focus.width, comfortable.width)
        XCTAssertEqual(focus.midX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(focus.midY, 0.5, accuracy: 0.0001)
        XCTAssertEqual(SnapSizePreset.focus.position, .focus)
        XCTAssertEqual(SnapSizePreset.full.position, .maximize)
    }
}
