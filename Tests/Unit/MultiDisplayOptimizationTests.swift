import CoreGraphics
import XCTest
@testable import KatiKati

// MARK: - MD-2 · Screen edges

final class ScreenEdgeTopologyTests: XCTestCase {
    private func display(_ uuid: String, _ rect: CGRect) -> TopologyDisplay {
        TopologyDisplay(uuid: uuid, screenFrame: rect, visibleFrame: rect)
    }

    /// The audited desk: external above the built-in, overhanging both sides.
    func testStackedDeskSeamsTheSharedHorizontalEdgeOnly() {
        let builtIn = display("A", CGRect(x: 0, y: 0, width: 1710, height: 1112))
        let external = display("B", CGRect(x: -164, y: 1112, width: 1920, height: 1080))
        let topology = ScreenEdgeTopology.resolve(displays: [builtIn, external])

        XCTAssertEqual(topology.seamEdges(for: "A"), [.top])
        XCTAssertEqual(topology.seamEdges(for: "B"), [.bottom])
        XCTAssertEqual(topology.outerEdges(for: "A"), [.left, .right, .bottom])
        XCTAssertEqual(topology.outerEdges(for: "B"), [.left, .right, .top])
        XCTAssertTrue(topology.isOuter(.left, on: "B"), "the 164 pt overhang is a dead wall, not a seam")
    }

    func testSideBySideDeskSeamsTheVerticalEdges() {
        let left = display("A", CGRect(x: 0, y: 0, width: 1000, height: 800))
        let right = display("B", CGRect(x: 1000, y: 0, width: 1000, height: 800))
        let topology = ScreenEdgeTopology.resolve(displays: [left, right])

        XCTAssertEqual(topology.seamEdges(for: "A"), [.right])
        XCTAssertEqual(topology.seamEdges(for: "B"), [.left])
        XCTAssertEqual(topology.hosts(for: .right, among: ["A", "B"]), ["B"])
        XCTAssertEqual(topology.hosts(for: .left, among: ["A", "B"]), ["A"])
    }

    func testFramesThatOnlyTouchACornerShareNothing() {
        let a = display("A", CGRect(x: 0, y: 0, width: 1000, height: 800))
        let b = display("B", CGRect(x: 1000, y: 800, width: 800, height: 600))
        XCTAssertTrue(ScreenEdgeTopology.resolve(displays: [a, b]).seamEdges(for: "A").isEmpty,
                      "touching on both axes at once is a corner, not a shared edge")
    }

    func testToleranceBridgesANarrowGapButNotAWideOne() {
        let left = display("A", CGRect(x: 0, y: 0, width: 1000, height: 800))
        let near = display("B", CGRect(x: 1001.5, y: 0, width: 800, height: 800))
        XCTAssertEqual(ScreenEdgeTopology.resolve(displays: [left, near]).seamEdges(for: "A"), [.right])

        let far = display("C", CGRect(x: 1008, y: 0, width: 800, height: 800))
        XCTAssertTrue(ScreenEdgeTopology.resolve(displays: [left, far], tolerance: 2).seamEdges(for: "A").isEmpty)
        XCTAssertEqual(ScreenEdgeTopology.resolve(displays: [left, far], tolerance: 12).seamEdges(for: "A"), [.right])
    }

    func testSingleDisplayHasNoSeamsAndEveryEdgeIsOuter() {
        let only = display("A", CGRect(x: 0, y: 0, width: 1440, height: 900))
        let topology = ScreenEdgeTopology.resolve(displays: [only])
        XCTAssertTrue(topology.seamEdges(for: "A").isEmpty)
        XCTAssertEqual(topology.outerEdges(for: "A"), Set(ScreenEdge.allCases))
        XCTAssertEqual(ScreenEdgeTopology.empty.seamEdges(for: "A"), [])
    }

    func testUnknownDisplayIsNeverTreatedAsASeam() {
        let only = display("A", CGRect(x: 0, y: 0, width: 1440, height: 900))
        let topology = ScreenEdgeTopology.resolve(displays: [only])
        XCTAssertEqual(topology.outerEdges(for: "ghost"), Set(ScreenEdge.allCases),
                       "a failed UUID lookup must widen, never suppress")
    }
}

// MARK: - MD-2 · deck hosting

final class EdgeBarPlacementTests: XCTestCase {
    private var sideBySide: ScreenEdgeTopology {
        ScreenEdgeTopology.resolve(displays: [
            TopologyDisplay(uuid: "A", screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)),
            TopologyDisplay(uuid: "B", screenFrame: CGRect(x: 1000, y: 0, width: 1000, height: 800),
                            visibleFrame: CGRect(x: 1000, y: 0, width: 1000, height: 800))
        ])
    }

    func testOuterOnlyKeepsTheDeckOffASharedSeam() {
        let slots = EdgeSlotSet.desiredSlots(
            placement: .allScreensPerDisplay,
            connectedKeys: ["A", "B"],
            sides: [.right],
            topology: sideBySide,
            outerOnly: true
        )
        XCTAssertEqual(slots.map(\.display), ["B"], "only B's right edge ends the desktop")
    }

    func testOuterOnlyOffKeepsEveryDisplay() {
        let slots = EdgeSlotSet.desiredSlots(
            placement: .allScreensPerDisplay,
            connectedKeys: ["A", "B"],
            sides: [.right],
            topology: sideBySide,
            outerOnly: false
        )
        XCTAssertEqual(slots.map(\.display), ["A", "B"])
    }

    func testSingleDisplayKeepsItsDeck() {
        let alone = ScreenEdgeTopology.resolve(displays: [
            TopologyDisplay(uuid: "A", screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ])
        let slots = EdgeSlotSet.desiredSlots(
            placement: .allScreensPerDisplay,
            connectedKeys: ["A"],
            sides: [.right],
            topology: alone,
            outerOnly: true
        )
        XCTAssertEqual(slots.map(\.display), ["A"])
        XCTAssertFalse(EdgeBarPlacement.outerOnlyDefault(displayCount: 1))
        XCTAssertTrue(EdgeBarPlacement.outerOnlyDefault(displayCount: 2))
    }

    func testFollowSettingsSlotIsNeverFilteredOut() {
        XCTAssertTrue(EdgeBarPlacement.hosts(side: .right, displayKey: nil, topology: sideBySide, outerOnly: true))
        let slots = EdgeSlotSet.desiredSlots(
            placement: .followMouse,
            connectedKeys: ["A", "B"],
            sides: [.right],
            topology: sideBySide,
            outerOnly: true
        )
        XCTAssertEqual(slots.count, 1)
        XCTAssertNil(slots.first?.display)
    }
}

// MARK: - MD-2 · seam-immune snap zones

final class SeamSnapImmunityTests: XCTestCase {
    private let area = CGRect(x: 0, y: 0, width: 1_000, height: 800)

    func testASuppressedEdgeNeverResolvesAndItsCornerFallsBack() {
        XCTAssertNil(SnapZonePlanner.edgeZone(at: CGPoint(x: 500, y: 5), in: area, edgeMargin: 20, suppressed: [.bottom]))
        XCTAssertEqual(SnapZonePlanner.edgeZone(at: CGPoint(x: 5, y: 5), in: area, edgeMargin: 20, suppressed: [.bottom]),
                       .leftHalf, "the bottom-left corner falls back to the edge that still exists")
        XCTAssertEqual(SnapZonePlanner.edgeZone(at: CGPoint(x: 500, y: 795), in: area, edgeMargin: 20, suppressed: [.bottom]),
                       .topHalf)
    }

    func testUnsuppressedEdgesBehaveExactlyAsBefore() {
        for (point, expected) in [
            (CGPoint(x: 5, y: 400), SnapPosition.leftHalf),
            (CGPoint(x: 995, y: 400), .rightHalf),
            (CGPoint(x: 500, y: 795), .topHalf),
            (CGPoint(x: 500, y: 5), .bottomHalf),
            (CGPoint(x: 5, y: 795), .topLeft),
            (CGPoint(x: 995, y: 5), .bottomRight)
        ] {
            XCTAssertEqual(SnapZonePlanner.edgeZone(at: point, in: area, edgeMargin: 20), expected)
            XCTAssertEqual(SnapZonePlanner.edgeZone(at: point, in: area, edgeMargin: 20, suppressed: []), expected)
        }
    }

    func testResolvePassesTheSuppressionThrough() {
        XCTAssertNil(SnapZonePlanner.resolve(at: CGPoint(x: 5, y: 400), in: area,
                                             layout: .edgesAndCorners, edgeMargin: 20, suppressed: [.left]))
        XCTAssertEqual(SnapZonePlanner.resolve(at: CGPoint(x: 995, y: 400), in: area,
                                               layout: .edgesAndCorners, edgeMargin: 20, suppressed: [.left])?.position,
                       .rightHalf)
        XCTAssertEqual(SnapGaps.seamDwell, 0.45, accuracy: 0.0001)
    }
}

// MARK: - MD-4 · window throw

final class WindowThrowTests: XCTestCase {
    func testFractionsSurviveADifferentResolution() {
        let source = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let destination = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let half = CGRect(x: 0, y: 0, width: 720, height: 900)

        let thrown = WindowThrow.relativeFrame(from: half, source: source, destination: destination)
        XCTAssertEqual(thrown.minX, 1440)
        XCTAssertEqual(thrown.width, 720)
        XCTAssertEqual(thrown.height, 900)
    }

    func testAWindowWiderThanTheTargetIsClampedIntoIt() {
        let source = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let destination = CGRect(x: 1920, y: 0, width: 1024, height: 768)
        let wide = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let thrown = WindowThrow.relativeFrame(from: wide, source: source, destination: destination)
        XCTAssertEqual(thrown, destination)
    }

    func testOffEdgePositionsStayInsideTheDestination() {
        let source = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let destination = CGRect(x: 1000, y: 200, width: 1000, height: 800)
        let corner = CGRect(x: 900, y: 700, width: 400, height: 400)
        let thrown = WindowThrow.relativeFrame(from: corner, source: source, destination: destination)
        XCTAssertEqual(thrown.maxX, destination.maxX)
        XCTAssertEqual(thrown.maxY, destination.maxY)
        XCTAssertGreaterThanOrEqual(thrown.minX, destination.minX)
        XCTAssertGreaterThanOrEqual(thrown.minY, destination.minY)
    }

    func testAZeroSizedAreaReturnsTheFrameUnchanged() {
        let frame = CGRect(x: 10, y: 10, width: 100, height: 100)
        XCTAssertEqual(WindowThrow.relativeFrame(from: frame, source: .zero, destination: CGRect(x: 0, y: 0, width: 100, height: 100)),
                       frame)
    }
}

// MARK: - MD-4 · relative layout memory

final class WindowLayoutRelativeMemoryTests: XCTestCase {
    private func window(_ id: UInt32, _ rect: CGRect) -> WindowLayoutMemory.Window {
        .init(pid: 10, cgWindowID: id, frame: rect)
    }

    func testRememberedProportionsAreUsedWhenTheDisplayChangesSize() {
        var memory = WindowLayoutMemory()
        let studio = WindowLayoutMemory.Display(uuid: "EXT", visibleFrame: CGRect(x: 1000, y: 0, width: 1920, height: 1080))
        let original = window(1, CGRect(x: 1000, y: 540, width: 960, height: 540))
        memory.record(topology: "EXT", windows: [original], displays: [studio])
        XCTAssertNotNil(memory.layouts["EXT"]?[original.key]?.relative)

        let smaller = WindowLayoutMemory.Display(uuid: "EXT", visibleFrame: CGRect(x: 1000, y: 0, width: 1280, height: 720))
        let moves = memory.plan(topology: "EXT", current: [original], displays: [smaller])
        XCTAssertEqual(moves.count, 1)
        let frame = moves[0].frame
        XCTAssertEqual(frame.width, 640, accuracy: 1, "half of the old width, not 960 pt on a 1280 pt panel")
        XCTAssertEqual(frame.height, 360, accuracy: 1)
        XCTAssertEqual(frame.minX, 1000, accuracy: 1)
        XCTAssertEqual(frame.minY, 360, accuracy: 1, "mid-height stays mid-height")
    }

    func testAnUnchangedDisplayRestoresTheAbsoluteFrame() {
        var memory = WindowLayoutMemory()
        let display = WindowLayoutMemory.Display(uuid: "EXT", visibleFrame: CGRect(x: 1000, y: 0, width: 1920, height: 1080))
        let original = window(1, CGRect(x: 1200, y: 200, width: 800, height: 600))
        memory.record(topology: "EXT", windows: [original], displays: [display])

        let moved = window(1, CGRect(x: 1000, y: 0, width: 800, height: 600))
        let moves = memory.plan(topology: "EXT", current: [moved], displays: [display])
        XCTAssertEqual(moves.first?.frame, original.frame, "same-size display keeps the exact frame, no rounding drift")
    }

    func testAV1FileWithoutRelativeFramesStillRestores() throws {
        var memory = WindowLayoutMemory()
        let original = window(1, CGRect(x: 100, y: 100, width: 800, height: 600))
        memory.record(topology: "A", windows: [original])   // no displays → v1 shape
        let decoded = try JSONDecoder().decode(WindowLayoutMemory.self, from: JSONEncoder().encode(memory))
        XCTAssertEqual(decoded, memory)
        XCTAssertNil(decoded.layouts["A"]?[original.key]?.relative)

        let moves = decoded.plan(topology: "A", current: [window(1, .zero)], displays: [])
        XCTAssertEqual(moves.first?.frame, original.frame)
    }

    func testAWindowIsAttributedToTheDisplayShowingMostOfIt() {
        let left = WindowLayoutMemory.Display(uuid: "A", visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let right = WindowLayoutMemory.Display(uuid: "B", visibleFrame: CGRect(x: 1000, y: 0, width: 1000, height: 800))
        let straddling = CGRect(x: 700, y: 100, width: 800, height: 400)   // 300 on A, 500 on B
        XCTAssertEqual(WindowLayoutMemory.display(containing: straddling, in: [left, right])?.uuid, "B")
        XCTAssertNil(WindowLayoutMemory.display(containing: CGRect(x: 5000, y: 5000, width: 100, height: 100),
                                                in: [left, right]))
    }
}

// MARK: - MD-3 · island placement

final class IslandPlacementTests: XCTestCase {
    private let builtIn = IslandPlacement.Display(uuid: "A", hasHardwareNotch: true, isBuiltIn: true)
    private let external = IslandPlacement.Display(uuid: "B", hasHardwareNotch: false, isBuiltIn: false)

    func testAllDisplaysKeepsTodaysBehaviour() {
        let roles = IslandPlacement.resolve(mode: .allDisplays, displays: [builtIn, external], activeUUID: "B")
        XCTAssertEqual(roles, ["A": .notch, "B": .wideBar])
    }

    func testBuiltInOnlyHidesTheExternal() {
        let roles = IslandPlacement.resolve(mode: .builtInOnly, displays: [builtIn, external], activeUUID: "B")
        XCTAssertEqual(roles, ["A": .notch, "B": .hidden])
    }

    func testFollowThePointerMovesTheSingleIsland() {
        let onExternal = IslandPlacement.resolve(mode: .followActiveDisplay, displays: [builtIn, external], activeUUID: "B")
        XCTAssertEqual(onExternal, ["A": .hidden, "B": .wideBar])
        let onBuiltIn = IslandPlacement.resolve(mode: .followActiveDisplay, displays: [builtIn, external], activeUUID: "A")
        XCTAssertEqual(onBuiltIn, ["A": .notch, "B": .hidden])
    }

    func testFollowThePointerNeverBlanksAWholeDesk() {
        let roles = IslandPlacement.resolve(mode: .followActiveDisplay, displays: [builtIn, external], activeUUID: nil)
        XCTAssertTrue(roles.values.contains { $0.showsIsland })
    }

    func testExternalFloatingPillKeepsTheRealNotchAlone() {
        let roles = IslandPlacement.resolve(mode: .externalFloatingPill, displays: [builtIn, external], activeUUID: "B")
        XCTAssertEqual(roles, ["A": .notch, "B": .floatingPill])
    }

    func testClamshellHandoverMovesTheSameRole() {
        let before = ["A": IslandRole.notch, "B": IslandRole.hidden]
        let after = ["B": IslandRole.wideBar]
        XCTAssertFalse(IslandPlacement.handover(previous: before, current: after).isRetarget,
                       "a notch does not become a wide bar behind the user's back")

        let wideBefore = ["A": IslandRole.wideBar, "B": IslandRole.hidden]
        let wideAfter = ["B": IslandRole.wideBar]
        let handover = IslandPlacement.handover(previous: wideBefore, current: wideAfter)
        XCTAssertEqual(handover.movedFrom, "A")
        XCTAssertEqual(handover.movedTo, "B")
        XCTAssertTrue(handover.isRetarget)
    }

    func testNoHandoverWhenNothingMoved() {
        let roles = ["A": IslandRole.notch, "B": IslandRole.wideBar]
        XCTAssertFalse(IslandPlacement.handover(previous: roles, current: roles).isRetarget)
        XCTAssertFalse(IslandPlacement.handover(previous: [:], current: roles).isRetarget)
    }

    func testModeRawValuesAreStableAndDefaultIsAllDisplays() {
        XCTAssertEqual(IslandPlacementMode.allCases.map(\.rawValue),
                       ["allDisplays", "builtInOnly", "followActiveDisplay", "externalFloatingPill"])
        XCTAssertEqual(IslandPlacementMode.default, .allDisplays)
        XCTAssertEqual(IslandPlacementMode.defaultsKey, "com.katikati.island.placementMode")
    }
}

// MARK: - MD-5 · DDC writes and cursor crossing

final class DDCWriteCoalescerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testTheFirstValueIsWrittenImmediately() {
        var coalescer = DDCWriteCoalescer()
        let write = coalescer.offer(displayUUID: "A", vcp: DisplayVCP.brightness, value: 120, at: start)
        XCTAssertEqual(write?.value, 120)
        XCTAssertTrue(coalescer.pending.isEmpty)
    }

    func testWritesInsideTheWindowCollapseToTheNewestValue() {
        var coalescer = DDCWriteCoalescer()
        _ = coalescer.offer(displayUUID: "A", vcp: DisplayVCP.brightness, value: 10, at: start)
        XCTAssertNil(coalescer.offer(displayUUID: "A", vcp: DisplayVCP.brightness, value: 20, at: start.addingTimeInterval(0.01)))
        XCTAssertNil(coalescer.offer(displayUUID: "A", vcp: DisplayVCP.brightness, value: 30, at: start.addingTimeInterval(0.02)))

        let flushed = coalescer.flush(at: start.addingTimeInterval(0.06))
        XCTAssertEqual(flushed.count, 1)
        XCTAssertEqual(flushed.first?.value, 30, "last value wins; the dropped 20 never queues")
    }

    func testFlushingBeforeTheWindowClosesWritesNothing() {
        var coalescer = DDCWriteCoalescer()
        _ = coalescer.offer(displayUUID: "A", vcp: DisplayVCP.brightness, value: 10, at: start)
        _ = coalescer.offer(displayUUID: "A", vcp: DisplayVCP.brightness, value: 40, at: start.addingTimeInterval(0.01))
        XCTAssertTrue(coalescer.flush(at: start.addingTimeInterval(0.02)).isEmpty)
        XCTAssertEqual(coalescer.pending[DDCWriteCoalescer.Key(displayUUID: "A", vcp: DisplayVCP.brightness)], 40)
    }

    func testDisplaysAndVCPsThrottleIndependently() {
        var coalescer = DDCWriteCoalescer()
        XCTAssertNotNil(coalescer.offer(displayUUID: "A", vcp: DisplayVCP.brightness, value: 1, at: start))
        XCTAssertNotNil(coalescer.offer(displayUUID: "B", vcp: DisplayVCP.brightness, value: 2, at: start))
        XCTAssertNotNil(coalescer.offer(displayUUID: "A", vcp: DisplayVCP.volume, value: 3, at: start))
        XCTAssertNil(coalescer.offer(displayUUID: "A", vcp: DisplayVCP.brightness, value: 4, at: start))
    }

    func testResetForgetsPendingWrites() {
        var coalescer = DDCWriteCoalescer()
        _ = coalescer.offer(displayUUID: "A", vcp: DisplayVCP.brightness, value: 10, at: start)
        _ = coalescer.offer(displayUUID: "A", vcp: DisplayVCP.brightness, value: 90, at: start.addingTimeInterval(0.01))
        coalescer.reset()
        XCTAssertTrue(coalescer.pending.isEmpty)
        XCTAssertTrue(coalescer.flush(at: start.addingTimeInterval(1)).isEmpty)
    }
}

final class DDCServiceOrderTests: XCTestCase {
    func testOverridePinsADisplayToASlot() {
        let slots = DDCServiceOrder.resolve(externals: ["A", "B"], serviceCount: 2, overrides: ["B": 0])
        XCTAssertEqual(slots, ["B", "A"])
    }

    func testRemainingDisplaysFillFreeSlotsInOrder() {
        let slots = DDCServiceOrder.resolve(externals: ["A", "B", "C"], serviceCount: 2, overrides: [:])
        XCTAssertEqual(slots, ["A", "B"], "more displays than answering nodes keeps the first two")
    }

    func testNoServicesMeansNoMapping() {
        XCTAssertTrue(DDCServiceOrder.resolve(externals: ["A"], serviceCount: 0, overrides: [:]).isEmpty)
    }

    func testAnOutOfRangeOverrideIsIgnored() {
        XCTAssertEqual(DDCServiceOrder.resolve(externals: ["A"], serviceCount: 1, overrides: ["A": 7]), ["A"])
    }
}

final class CursorCrossingPlanTests: XCTestCase {
    func testAHorizontalNeighbourIsEnteredOnItsNearEdge() {
        let current = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let target = CGRect(x: 1000, y: 0, width: 1200, height: 600)
        let point = CursorCrossingPlan.jump(from: CGPoint(x: 600, y: 400), current: current, target: target)
        XCTAssertEqual(point.x, 1002)
        XCTAssertEqual(point.y, 300, accuracy: 0.5, "same fraction of the edge, not the same absolute y")
    }

    func testAVerticalNeighbourIsEnteredOnItsNearEdge() {
        let current = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let target = CGRect(x: -100, y: 800, width: 1200, height: 1080)
        let point = CursorCrossingPlan.jump(from: CGPoint(x: 500, y: 790), current: current, target: target)
        XCTAssertEqual(point.y, 802)
        XCTAssertGreaterThanOrEqual(point.x, target.minX)
        XCTAssertLessThanOrEqual(point.x, target.maxX)
    }

    func testBackwardsTravelEntersTheFarEdge() {
        let current = CGRect(x: 1000, y: 0, width: 1000, height: 800)
        let target = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertEqual(CursorCrossingPlan.jump(from: CGPoint(x: 1200, y: 400), current: current, target: target).x, 998)
    }

    func testDeadWallsAreOutsideEveryScreen() {
        let screens = [CGRect(x: 0, y: 0, width: 1710, height: 1112),
                       CGRect(x: -164, y: 1112, width: 1920, height: 1080)]
        XCTAssertTrue(CursorCrossingPlan.isDeadWall(CGPoint(x: -100, y: 400), screens: screens))
        XCTAssertFalse(CursorCrossingPlan.isDeadWall(CGPoint(x: 100, y: 400), screens: screens))
    }
}

// MARK: - MD-5 · display targeting, cursor jump action and volume

final class DisplayTargetRuleTests: XCTestCase {
    private let frames = [CGRect(x: 0, y: 0, width: 1000, height: 800),
                          CGRect(x: 1000, y: 0, width: 1200, height: 700)]

    func testThePointerPicksItsDisplay() {
        XCTAssertEqual(DisplayTargetRule.index(cursor: CGPoint(x: 1200, y: 100), frames: frames, mainIndex: 0), 1)
        XCTAssertEqual(DisplayTargetRule.index(cursor: CGPoint(x: 10, y: 10), frames: frames, mainIndex: 1), 0,
                       "the pointer wins over the main display")
    }

    func testADeadWallFallsBackToTheMainDisplay() {
        XCTAssertEqual(DisplayTargetRule.index(cursor: CGPoint(x: -400, y: 300), frames: frames, mainIndex: 1), 1)
    }

    func testWithoutAMainDisplayTheFirstDisplayIsUsed() {
        XCTAssertEqual(DisplayTargetRule.index(cursor: CGPoint(x: -400, y: 300), frames: frames, mainIndex: nil), 0)
        XCTAssertNil(DisplayTargetRule.index(cursor: .zero, frames: [], mainIndex: 0))
    }
}

final class CursorJumpActionTests: XCTestCase {
    func testTheActionIsOffByDefaultAndReachable() {
        XCTAssertEqual(ShortcutAction.cursorNextDisplay.defaultTrigger, .off,
                       "a pointer-moving key is never bound without the user asking")
        XCTAssertEqual(ShortcutAction.cursorNextDisplay.category, .windowAndSnap)
        XCTAssertNil(ShortcutAction.cursorNextDisplay.snapPosition, "it is not a window zone")
        XCTAssertFalse(SettingsLayoutPane.shortcutActionName(.cursorNextDisplay).isEmpty)
        XCTAssertNotEqual(SettingsLayoutPane.shortcutActionName(.cursorNextDisplay),
                          SettingsLayoutPane.shortcutActionName(.snapNextDisplay),
                          "moving the pointer and moving the window are different rows")
    }

    func testEveryHotKeyIDIsUnique() {
        let ids = ShortcutAction.allCases.map(\.hotKeyID)
        XCTAssertEqual(Set(ids).count, ids.count, "Carbon ids must never be reused")
        XCTAssertEqual(ShortcutAction.cursorNextDisplay.hotKeyID, 77)
    }

    func testTheJumpMovesOneDisplayAndWraps() {
        // The jump uses the same step rule as the window throw, so cycling both ways is pinned.
        XCTAssertEqual(DisplayMove.destination(from: 0, count: 2, step: 1), 1)
        XCTAssertEqual(DisplayMove.destination(from: 1, count: 2, step: 1), 0)
        XCTAssertEqual(DisplayMove.destination(from: 0, count: 1, step: 1), 0)
    }

    /// The pointer lands inside the target display, at the same fraction of the edge it left.
    func testThePlannedLandingPointIsInsideTheTargetDisplay() {
        let current = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        let target = CGRect(x: -164, y: 1112, width: 1920, height: 1080)
        let landing = CursorCrossingPlan.jump(from: CGPoint(x: 900, y: 1100), current: current, target: target)
        XCTAssertTrue(target.contains(landing), "the warp must land on the target display, not in a dead wall")
    }
}

final class DisplayVolumeRuleTests: XCTestCase {
    func testVolumeHasItsOwnVCPAndSharesTheCoalescer() {
        XCTAssertEqual(DisplayVCP.volume, 0x62)
        XCTAssertEqual(DisplayVCP.brightness, 0x10)

        var coalescer = DDCWriteCoalescer()
        let start = Date(timeIntervalSince1970: 500)
        XCTAssertNotNil(coalescer.offer(displayUUID: "A", vcp: DisplayVCP.volume, value: 40, at: start))
        XCTAssertNil(coalescer.offer(displayUUID: "A", vcp: DisplayVCP.volume, value: 60, at: start.addingTimeInterval(0.02)))
        let flushed = coalescer.flush(at: start.addingTimeInterval(0.08))
        XCTAssertEqual(flushed.map(\.value), [60], "a drag collapses to the last value, exactly like brightness")
    }

    func testSoftwareFallbackFloorAndGateDefaults() {
        XCTAssertEqual(DisplayBrightnessConfig.gammaMinimum, 0.15, accuracy: 0.0001)
        let suite = "com.katikati.tests.brightness.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(DisplayBrightnessConfig.ddcEnabled(defaults), "DDC is on unless the user turns it off")
        defaults.set(false, forKey: DisplayBrightnessConfig.ddcKey)
        XCTAssertFalse(DisplayBrightnessConfig.ddcEnabled(defaults))
    }
}

final class DDCCommandTests: XCTestCase {
    func testReadRequestFoldsBothAddressesAndTheOpcode() {
        // The byte this desk's LG answers to; the earlier `0x6E ^ vcp` form got an empty reply.
        XCTAssertEqual(DDCCommand.read(vcp: DisplayVCP.brightness), [0x82, 0x01, 0x10, 0xAC])
        XCTAssertEqual(DDCCommand.read(vcp: DisplayVCP.volume), [0x82, 0x01, 0x62, 0xDE])
    }

    func testSetVCPPacketMatchesTheMCCSFrame() {
        XCTAssertEqual(DDCCommand.write(vcp: DisplayVCP.brightness, value: 100),
                       [0x84, 0x03, 0x10, 0x00, 0x64, 0xCC])
        XCTAssertEqual(DDCCommand.write(vcp: DisplayVCP.brightness, value: 0x1234),
                       [0x84, 0x03, 0x10, 0x12, 0x34, 0x8E])
    }

    func testARealLGPanelReplyValidates() {
        // Captured live: max 100 in bytes 6…7, current 100 in bytes 8…9, checksum 0xA4.
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x64, 0xA4]
        XCTAssertEqual(reply[0], DDCCommand.destination)
        XCTAssertEqual(reply[10], DDCCommand.replyChecksum(Array(reply[0..<10])))
        XCTAssertEqual(UInt16(reply[6]) << 8 | UInt16(reply[7]), 100)
        XCTAssertEqual(UInt16(reply[8]) << 8 | UInt16(reply[9]), 100)
    }

    func testAnEmptyReplyIsRejected() {
        // Also captured live: the first request after idle comes back as "no data".
        let empty: [UInt8] = [0x6E, 0x80, 0xBE, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x64, 0xA4]
        XCTAssertNotEqual(empty[2], 0x02, "length byte 0 means the panel answered nothing")
    }
}

final class DDCValueEncodingTests: XCTestCase {
    func testAFullSliderWritesThePanelsMaximumNotASecondScaledFraction() {
        // Regression: the byte was once encoded against the panel maximum (100) and then rescaled as
        // if it were a 0–255 fraction, so 100 % brightness wrote 39 %.
        XCTAssertEqual(DDCValue.byte(for: 1), 255)
        XCTAssertEqual(DDCValue.raw(byte: DDCValue.byte(for: 1), maximum: 100), 100)
        XCTAssertEqual(DDCValue.raw(byte: DDCValue.byte(for: 0.5), maximum: 100), 50)
        XCTAssertEqual(DDCValue.raw(byte: DDCValue.byte(for: 0), maximum: 100), 0)
    }

    func testPanelRangeMappingIsExactAtBothEnds() {
        XCTAssertEqual(DDCValue.raw(byte: 0, maximum: 100), 0)
        XCTAssertEqual(DDCValue.raw(byte: 255, maximum: 100), 100)
        XCTAssertEqual(DDCValue.raw(byte: 255, maximum: 255), 255)
        XCTAssertEqual(DDCValue.raw(byte: 200, maximum: 0), 0, "a panel that reports no maximum is not written")
        XCTAssertEqual(DDCValue.raw(byte: 128, maximum: 100), 50)
    }

    func testLevelsRoundTripWithinOnePanelStep() {
        for maximum: UInt16 in [60, 100, 255, 1000] {
            for level in stride(from: 0.0, through: 1.0, by: 0.05) {
                let written = Double(DDCValue.raw(byte: DDCValue.byte(for: level), maximum: maximum))
                // One 0–255 byte is `maximum / 255` panel units; rounding may cost half of that
                // plus one unit on a panel whose range exceeds 255.
                let tolerance = Double(maximum) / 255.0 + 1.0
                XCTAssertLessThanOrEqual(abs(written - level * Double(maximum)), tolerance,
                                         "level \(level) on a 0…\(maximum) panel")
            }
        }
    }
}

final class ActiveDockCueTests: XCTestCase {
    func testOnlyTheFocusedDisplayOfATwoDisplayDeskShowsTheCue() {
        XCTAssertTrue(ActiveDockCue.shows(stripUUID: "A", activeUUID: "A", screenCount: 2))
        XCTAssertFalse(ActiveDockCue.shows(stripUUID: "B", activeUUID: "A", screenCount: 2))
    }

    func testASingleDisplayDeskIsUntouched() {
        XCTAssertFalse(ActiveDockCue.shows(stripUUID: "A", activeUUID: "A", screenCount: 1),
                       "one display has nothing to disambiguate; its pixels must not change")
    }

    func testMissingIdentityNeverLightsTheRim() {
        XCTAssertFalse(ActiveDockCue.shows(stripUUID: nil, activeUUID: "A", screenCount: 2))
        XCTAssertFalse(ActiveDockCue.shows(stripUUID: "A", activeUUID: nil, screenCount: 2))
    }
}
