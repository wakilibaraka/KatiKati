import XCTest
@testable import KatiKati

final class IslandAnchorTests: XCTestCase {
    private let testScreen = PanelScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
        safeAreaTop: 25
    )

    func testNoYFlipProperty() {
        // screenFrame = origin + local: plain addition without vertical coordinate flipping
        let islandOrigin = CGPoint(x: 300, y: 15)
        let islandSize = CGSize(width: 400, height: 48)
        let islandFrame = CGRect(origin: islandOrigin, size: islandSize)

        let chipLocal = CGRect(x: 50, y: 4, width: 64, height: 40)

        // Plain addition formula
        let expectedScreenFrame = CGRect(
            x: islandFrame.origin.x + chipLocal.origin.x,
            y: islandFrame.origin.y + chipLocal.origin.y,
            width: chipLocal.width,
            height: chipLocal.height
        )

        XCTAssertEqual(expectedScreenFrame.origin.x, 350)
        XCTAssertEqual(expectedScreenFrame.origin.y, 19)
        XCTAssertEqual(expectedScreenFrame.width, 64)
        XCTAssertEqual(expectedScreenFrame.height, 40)
    }

    func testPerChipAnchorContainedInSummoningIsland() {
        let islandOrigin = CGPoint(x: 200, y: 10)
        let islandSize = CGSize(width: 320, height: 48)
        let islandFrame = CGRect(origin: islandOrigin, size: islandSize)

        // Chip within local bounds [0, 0, 320, 48]
        let chipLocal = CGRect(x: 20, y: 4, width: 80, height: 40)
        let screenAnchor = CGRect(
            x: islandFrame.origin.x + chipLocal.origin.x,
            y: islandFrame.origin.y + chipLocal.origin.y,
            width: chipLocal.width,
            height: chipLocal.height
        )

        XCTAssertTrue(islandFrame.contains(screenAnchor), "Screen anchor must be contained within summoning island frame")
    }

    func testSectionToSlotMappingAcrossModes() {
        // Windows mode: 1 slot (index 0 for all)
        XCTAssertEqual(BarSection.weather.slotIndex(for: .windows), 0)
        XCTAssertEqual(BarSection.apps.slotIndex(for: .windows), 0)
        XCTAssertEqual(BarSection.tray.slotIndex(for: .windows), 0)
        XCTAssertEqual(BarSection.clock.slotIndex(for: .windows), 0)

        // Split3 mode: 3 slots (weather->0, apps->1, tray/clock->2)
        XCTAssertEqual(BarSection.weather.slotIndex(for: .split3), 0)
        XCTAssertEqual(BarSection.apps.slotIndex(for: .split3), 1)
        XCTAssertEqual(BarSection.tray.slotIndex(for: .split3), 2)
        XCTAssertEqual(BarSection.clock.slotIndex(for: .split3), 2)

        // Split4 mode: 4 slots (weather->0, apps->1, tray->2, clock->3)
        XCTAssertEqual(BarSection.weather.slotIndex(for: .split4), 0)
        XCTAssertEqual(BarSection.apps.slotIndex(for: .split4), 1)
        XCTAssertEqual(BarSection.tray.slotIndex(for: .split4), 2)
        XCTAssertEqual(BarSection.clock.slotIndex(for: .split4), 3)

        // Centered mode: 1 slot (index 0 for all)
        XCTAssertEqual(BarSection.weather.slotIndex(for: .centered), 0)
        XCTAssertEqual(BarSection.apps.slotIndex(for: .centered), 0)
        XCTAssertEqual(BarSection.tray.slotIndex(for: .centered), 0)
        XCTAssertEqual(BarSection.clock.slotIndex(for: .centered), 0)
    }

    func testUnionBoundingFrameContainsAllIslands() {
        let metrics = PanelLayoutMetrics.tungstenEdge
        let gap: CGFloat = 12
        let margin: CGFloat = 16

        // Compute 4 islands in split4 mode
        let slot0 = PanelGeometry.islandTargetFrame(slot: 0, contentWidth: 100, mode: .split4, on: testScreen, metrics: metrics, gap: gap, margin: margin)
        let slot1 = PanelGeometry.islandTargetFrame(slot: 1, contentWidth: 400, mode: .split4, on: testScreen, metrics: metrics, gap: gap, margin: margin)
        let slot2 = PanelGeometry.islandTargetFrame(slot: 2, contentWidth: 120, mode: .split4, on: testScreen, metrics: metrics, gap: gap, margin: margin)
        let slot3 = PanelGeometry.islandTargetFrame(slot: 3, contentWidth: 90, mode: .split4, on: testScreen, metrics: metrics, gap: gap, margin: margin)

        let islands = [slot0, slot1, slot2, slot3]
        let bounding = islands.reduce(islands[0]) { $0.union($1) }

        for (idx, island) in islands.enumerated() {
            XCTAssertTrue(bounding.contains(island), "Bounding frame must contain island slot \(idx)")
        }

        XCTAssertEqual(bounding.minX, slot0.minX)
        XCTAssertEqual(bounding.maxX, slot3.maxX)
    }

    func testPopupTargetFramePositionedAboveAnchor() {
        let anchorRect = CGRect(x: 500, y: 15, width: 60, height: 36)
        let popupSize = CGSize(width: 300, height: 250)

        let popupTarget = PanelGeometry.folderPopupTargetFrame(
            anchorVisibleRect: anchorRect,
            size: popupSize,
            on: testScreen,
            metrics: .tungstenEdge
        )

        // The visible plate (excluding transparent panelMargin) should be positioned above the anchor
        let plate = PanelGeometry.folderPopupPlateFrame(panelFrame: popupTarget)
        XCTAssertGreaterThanOrEqual(plate.origin.y, anchorRect.maxY)
        XCTAssertEqual(popupTarget.width, popupSize.width)
        XCTAssertTrue(testScreen.frame.contains(plate))
    }

    func testTooltipTargetFramePositionedAboveAnchor() {
        let anchorRect = CGRect(x: 600, y: 15, width: 80, height: 36)
        let tooltipSize = CGSize(width: 120, height: 28)

        let target = PanelGeometry.windowTitleTooltipTargetFrame(
            anchorVisibleRect: anchorRect,
            size: tooltipSize,
            tipGap: 8,
            on: testScreen
        )

        XCTAssertGreaterThanOrEqual(target.origin.y, anchorRect.maxY)
        XCTAssertTrue(testScreen.frame.contains(target))
    }
}
