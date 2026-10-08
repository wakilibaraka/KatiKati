import XCTest
@testable import KatiKati

final class PinnedIslandTests: XCTestCase {
    private let testScreen = PanelScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
        safeAreaTop: 25
    )

    func testDesiredSlotsPlacementMatrix() {
        let connected = ["display-1", "display-2"]

        // 1. followMouse: exactly 1 unit (nil) expanded across slots
        let followMouseSplit3 = IslandSlotSet.desiredSlots(
            placement: .followMouse,
            connectedKeys: connected,
            mode: .split3
        )
        XCTAssertEqual(followMouseSplit3.count, 3)
        XCTAssertEqual(followMouseSplit3.map(\.slot), [0, 1, 2])
        XCTAssertTrue(followMouseSplit3.allSatisfy { $0.display == nil })

        let followMouseSplit4 = IslandSlotSet.desiredSlots(
            placement: .followMouse,
            connectedKeys: connected,
            mode: .split4
        )
        XCTAssertEqual(followMouseSplit4.count, 4)
        XCTAssertEqual(followMouseSplit4.map(\.slot), [0, 1, 2, 3])

        // 2. allScreens: each display expanded across slots
        let allScreensSplit4 = IslandSlotSet.desiredSlots(
            placement: .allScreens,
            connectedKeys: connected,
            mode: .split4
        )
        XCTAssertEqual(allScreensSplit4.count, 8)
        let disp1Slots = allScreensSplit4.filter { $0.display == "display-1" }
        let disp2Slots = allScreensSplit4.filter { $0.display == "display-2" }
        XCTAssertEqual(disp1Slots.count, 4)
        XCTAssertEqual(disp2Slots.count, 4)
        XCTAssertEqual(disp1Slots.map(\.slot), [0, 1, 2, 3])
        XCTAssertEqual(disp2Slots.map(\.slot), [0, 1, 2, 3])

        // 3. allScreensPerDisplay with 3 screens and split3
        let threeScreens = ["d1", "d2", "d3"]
        let allScreensPerDisplaySplit3 = IslandSlotSet.desiredSlots(
            placement: .allScreensPerDisplay,
            connectedKeys: threeScreens,
            mode: .split3
        )
        XCTAssertEqual(allScreensPerDisplaySplit3.count, 9)

        // 4. pinned display: exactly 1 unit (nil displayKey in desiredUnitKeys) expanded across slots
        let pinnedSplit4 = IslandSlotSet.desiredSlots(
            placement: .pinned(PinnedScreenSelection(uuid: "display-1", name: "Display 1")),
            connectedKeys: connected,
            mode: .split4
        )
        XCTAssertEqual(pinnedSplit4.count, 4)
        XCTAssertTrue(pinnedSplit4.allSatisfy { $0.display == nil })

        // 5. empty connected keys fallback: degrades to 1 unit (nil), never drops to 0
        let emptyConnectedFallback = IslandSlotSet.desiredSlots(
            placement: .allScreens,
            connectedKeys: [],
            mode: .split4
        )
        XCTAssertEqual(emptyConnectedFallback.count, 4)
        XCTAssertTrue(emptyConnectedFallback.allSatisfy { $0.display == nil })
    }

    func testPinnedScreenResolutionOutcome() {
        let screenUUIDs = ["disp-alpha", "disp-beta"]

        // Matched pinned display
        let matched = TaskbarScreenResolution.resolve(
            pinnedUUID: "disp-beta",
            screenUUIDs: screenUUIDs,
            mainIndex: 0
        )
        XCTAssertEqual(matched, .matched(index: 1))

        // Missing pinned display falls back to main screen
        let fallback = TaskbarScreenResolution.resolve(
            pinnedUUID: "disp-gamma-disconnected",
            screenUUIDs: screenUUIDs,
            mainIndex: 0
        )
        XCTAssertEqual(fallback, .fallback(index: 0))
    }

    func testHoverSwitchIslandFrameWidthReflectsSlotSize() {
        let metrics = PanelLayoutMetrics.tungstenEdge
        let gap: CGFloat = 12
        let margin: CGFloat = 16

        // In split4 mode, slot widths vary by section content rather than stretching across full display
        let slot0Frame = PanelGeometry.islandTargetFrame(
            slot: 0,
            contentWidth: 300,
            mode: .split4,
            on: testScreen,
            metrics: metrics,
            gap: gap,
            margin: margin
        )
        let slot0VisibleWidth = slot0Frame.width - metrics.shadowPadding * 2

        let slot1Frame = PanelGeometry.islandTargetFrame(
            slot: 1,
            contentWidth: 300,
            mode: .split4,
            on: testScreen,
            metrics: metrics,
            gap: gap,
            margin: margin
        )
        let slot1VisibleWidth = slot1Frame.width - metrics.shadowPadding * 2

        // Weather slot width is fixed (120pt) vs apps slot width (flex)
        XCTAssertEqual(slot0VisibleWidth, 120)
        XCTAssertGreaterThan(slot1VisibleWidth, slot0VisibleWidth)
        XCTAssertLessThan(slot1VisibleWidth, testScreen.frame.width)
    }
}
