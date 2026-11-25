import XCTest
@testable import KatiKati

final class IslandPanelGeometryTests: XCTestCase {
    private let testScreen = PanelScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
        safeAreaTop: 25
    )

    func testWindowsModeHugsItsContentAndCentresTheBar() {
        let metrics = PanelLayoutMetrics.tungstenEdge
        let margin: CGFloat = 12
        let capsuleSpace = metrics.capsuleGap + metrics.capsuleWidth
        var plates: [CGFloat] = []
        for contentWidth: CGFloat in [300, 500, 900] {
            let frame = PanelGeometry.islandTargetFrame(
                slot: 0, contentWidth: contentWidth, mode: .windows, on: testScreen,
                metrics: metrics, margin: margin)
            let plate = frame.width - 2 * metrics.shadowPadding
            XCTAssertEqual(plate, max(contentWidth, metrics.minimumDockWidth), accuracy: 0.5,
                           "Full Width is content + chrome, never an edge-to-edge bar (owner 2026-11-25)")
            XCTAssertLessThan(plate, testScreen.frame.width - 2 * margin,
                              "no dead plate beyond the content")
            // Centred in the room the trailing capsule leaves, rather than pinned to a margin.
            XCTAssertEqual(plate / 2 + (frame.minX + metrics.shadowPadding),
                           (testScreen.frame.width - capsuleSpace) / 2, accuracy: 1,
                           "the hug bar is centred")
            plates.append(plate)
        }
        XCTAssertEqual(plates, plates.sorted(), "wider content makes a wider bar")
    }

    func testCenteredModeHugsContent() {
        let metrics = PanelLayoutMetrics.tungstenEdge
        let contentWidth: CGFloat = 400
        let centeredSetting: CGFloat = 600

        let islandFrame = PanelGeometry.islandTargetFrame(
            slot: 0,
            contentWidth: contentWidth,
            mode: .centered,
            on: testScreen,
            metrics: metrics,
            centeredWidth: centeredSetting
        )

        // Centered frame has width based on centeredWidth and shadowPadding
        let visibleWidth = islandFrame.width - 2 * metrics.shadowPadding
        XCTAssertEqual(visibleWidth, centeredSetting)

        // X coordinate is horizontally centered
        let visibleX = islandFrame.minX + metrics.shadowPadding
        let expectedX = testScreen.frame.minX + (testScreen.frame.width - (visibleWidth + metrics.capsuleGap + metrics.capsuleWidth)) / 2
        XCTAssertEqual(visibleX, expectedX, accuracy: 0.1)
    }

    func testSplit3ProducesThreeValidIslands() {
        let metrics = PanelLayoutMetrics.tungstenEdge
        let gap: CGFloat = 12
        let margin: CGFloat = 16

        let slot0 = PanelGeometry.islandTargetFrame(
            slot: 0,
            contentWidth: 300,
            mode: .split3,
            on: testScreen,
            metrics: metrics,
            gap: gap,
            margin: margin
        )
        let slot1 = PanelGeometry.islandTargetFrame(
            slot: 1,
            contentWidth: 300,
            mode: .split3,
            on: testScreen,
            metrics: metrics,
            gap: gap,
            margin: margin
        )
        let slot2 = PanelGeometry.islandTargetFrame(
            slot: 2,
            contentWidth: 300,
            mode: .split3,
            on: testScreen,
            metrics: metrics,
            gap: gap,
            margin: margin
        )

        // Strip shadow padding to inspect visible frames
        let v0 = slot0.insetBy(dx: metrics.shadowPadding, dy: metrics.shadowPadding)
        let v1 = slot1.insetBy(dx: metrics.shadowPadding, dy: metrics.shadowPadding)
        let v2 = slot2.insetBy(dx: metrics.shadowPadding, dy: metrics.shadowPadding)

        // Left island touches margin
        XCTAssertEqual(v0.minX, testScreen.frame.minX + margin, accuracy: 0.1)

        // Right island touches margin on right
        XCTAssertEqual(v2.maxX, testScreen.frame.maxX - margin, accuracy: 0.1)

        // Middle island is strictly between left and right with at least gap separation
        XCTAssertGreaterThanOrEqual(v1.minX - v0.maxX, gap - 0.1)
        XCTAssertGreaterThanOrEqual(v2.minX - v1.maxX, gap - 0.1)

        // All visible frames are within screen bounds
        XCTAssertTrue(testScreen.frame.contains(v0))
        XCTAssertTrue(testScreen.frame.contains(v1))
        XCTAssertTrue(testScreen.frame.contains(v2))
    }

    func testSplit4ProducesFourValidIslands() {
        let metrics = PanelLayoutMetrics.tungstenEdge
        let gap: CGFloat = 8
        let margin: CGFloat = 12

        var visibleFrames: [CGRect] = []
        for slot in 0..<4 {
            let frame = PanelGeometry.islandTargetFrame(
                slot: slot,
                contentWidth: 280,
                mode: .split4,
                on: testScreen,
                metrics: metrics,
                gap: gap,
                margin: margin
            )
            let v = frame.insetBy(dx: metrics.shadowPadding, dy: metrics.shadowPadding)
            visibleFrames.append(v)
            XCTAssertTrue(testScreen.frame.contains(v), "Slot \(slot) visible frame must be inside screen")
        }

        // Verify ordering: v0 < v1 < v2 < v3
        for i in 0..<3 {
            let left = visibleFrames[i]
            let right = visibleFrames[i + 1]
            XCTAssertGreaterThanOrEqual(
                right.minX - left.maxX,
                0.5,
                "Separation between island \(i) and \(i + 1) must be at least 0.5pt"
            )
        }
    }

    func testCapsuleOwnershipAcrossModes() {
        // In windows and centered, only slot 0 hosts apps
        let windowsIslands = BarSection.islands(for: .windows)
        XCTAssertTrue(windowsIslands[0].contains(.apps))

        let centeredIslands = BarSection.islands(for: .centered)
        XCTAssertTrue(centeredIslands[0].contains(.apps))

        // In split3, slot 1 hosts apps
        let split3Islands = BarSection.islands(for: .split3)
        XCTAssertFalse(split3Islands[0].contains(.apps))
        XCTAssertTrue(split3Islands[1].contains(.apps))
        XCTAssertFalse(split3Islands[2].contains(.apps))

        // In split4, slot 1 hosts apps
        let split4Islands = BarSection.islands(for: .split4)
        XCTAssertFalse(split4Islands[0].contains(.apps))
        XCTAssertTrue(split4Islands[1].contains(.apps))
        XCTAssertFalse(split4Islands[2].contains(.apps))
        XCTAssertFalse(split4Islands[3].contains(.apps))
    }

    /// PHN-6a: a full dock used to leave the wings zero room, because the Centered plate grew to the
    /// whole usable width and only the outside of the plate was measured. The plate now hands each
    /// parked wing its width back, so the ladder keeps the requested size instead of hiding.
    func testFullDockStillParksBothWingsOutsideThePlate() {
        let metrics = PanelLayoutMetrics.tungstenEdge
        let margin: CGFloat = 12
        let width = DockWingsConfiguration.clampedGap(10)
        var wings = DockWingsConfiguration(
            left: DockWingSlotConfig(preset: .pause, size: .medium),
            right: DockWingSlotConfig(preset: .hydrate, size: .medium)
        )
        wings.gap = width

        // 1640 pt of content on a 1440 pt screen: the live case, where the dock wants more than the
        // screen can give and the plate is clamped.
        let frame = PanelGeometry.islandTargetFrame(
            slot: 0, contentWidth: 1640, mode: .centered, on: testScreen,
            metrics: metrics, margin: margin, wingConfig: wings)
        let plate = frame.insetBy(dx: metrics.shadowPadding, dy: metrics.shadowPadding)

        // The real caller hands over the panel frame (shadow included) and lets the planner inset it.
        let plan = PanelGeometry.wingPanelFrames(
            dockFrame: frame, capsuleFrame: .zero, config: wings,
            stripPlacement: .bottom, drawerPlacement: .right, controlCentreTrailing: false,
            on: testScreen, metrics: metrics, margin: margin)

        XCTAssertNotNil(plan.leftFrame, "a full dock must still park the left wing")
        XCTAssertNotNil(plan.rightFrame, "a full dock must still park the right wing")
        XCTAssertEqual(plan.leftSize, .medium)
        XCTAssertEqual(plan.rightSize, .medium)

        // The reserve is what pays for them: without wings the same content takes a wider plate.
        let plain = PanelGeometry.islandTargetFrame(
            slot: 0, contentWidth: 1640, mode: .centered, on: testScreen,
            metrics: metrics, margin: margin, wingConfig: .default)
        XCTAssertGreaterThan(plain.width, frame.width)

        // And each wing sits outside the plate, not over it. Wing frames carry their own shadow
        // padding, so compare the visible plates to each other.
        XCTAssertLessThanOrEqual(plan.leftFrame!.maxX - metrics.shadowPadding, plate.minX + 0.5)
        XCTAssertGreaterThanOrEqual(plan.rightFrame!.minX + metrics.shadowPadding, plate.maxX - 0.5)
    }

    /// PHN-6a in Full Width, where the plate used to run to both margins and left a wing nowhere to
    /// go. This mode has no slack to park in, so the wings take the bar's own ends: they start and
    /// finish on the margins the plate used to reach, the bar fills everything between them, and the
    /// plate gives up exactly the wings' park so the strip scrolls instead of clipping.
    func testFullWidthDockKeepsItsWingsBesideTheHugPlate() {
        let metrics = PanelLayoutMetrics.tungstenEdge
        let margin: CGFloat = 12
        var wings = DockWingsConfiguration(
            left: DockWingSlotConfig(preset: .pause, size: .medium),
            right: DockWingSlotConfig(preset: .hydrate, size: .medium)
        )
        wings.gap = DockWingsConfiguration.clampedGap(10)

        let frame = PanelGeometry.islandTargetFrame(
            slot: 0, contentWidth: 1640, mode: .windows, on: testScreen,
            metrics: metrics, margin: margin, wingConfig: wings)
        let plate = frame.insetBy(dx: metrics.shadowPadding, dy: metrics.shadowPadding)
        let capsule = PanelGeometry.stripCapsuleTargetFrame(
            forDock: frame, stripPlacement: .bottom, on: testScreen,
            drawerPlacement: .right, metrics: metrics)
        let plan = PanelGeometry.wingPanelFrames(
            dockFrame: frame, capsuleFrame: capsule, config: wings,
            stripPlacement: .bottom, drawerPlacement: .right, controlCentreTrailing: false,
            on: testScreen, metrics: metrics, margin: margin)

        XCTAssertNotNil(plan.leftFrame, "a hug bar must still show the left wing")
        XCTAssertNotNil(plan.rightFrame, "a hug bar must still show the right wing")
        XCTAssertEqual(plan.leftSize, .medium)
        XCTAssertEqual(plan.rightSize, .medium)

        // Wings flank the plate without overlapping it, and stay inside the screen margins.
        XCTAssertLessThanOrEqual(plan.leftFrame!.maxX - metrics.shadowPadding, plate.minX + 0.5)
        XCTAssertGreaterThanOrEqual(plan.rightFrame!.minX + metrics.shadowPadding, plate.maxX - 0.5)
        XCTAssertGreaterThanOrEqual(plan.leftFrame!.minX + metrics.shadowPadding, margin - 0.5)
        XCTAssertLessThanOrEqual(plan.rightFrame!.maxX - metrics.shadowPadding,
                                 testScreen.frame.maxX - margin + 0.5)

        // Reserving wing room makes the hug plate narrower by exactly that reserve, never wider.
        let plain = PanelGeometry.islandTargetFrame(
            slot: 0, contentWidth: 1640, mode: .windows, on: testScreen,
            metrics: metrics, margin: margin, wingConfig: .default)
        let reserve = PanelGeometry.dockWingReserve(config: wings, metrics: metrics)
        // The capsule rides beside the plate, so the forward side hands back its shadow padding too.
        XCTAssertEqual(plain.width - frame.width,
                       reserve.left + reserve.right + 2 * metrics.shadowPadding, accuracy: 0.5)
        XCTAssertGreaterThan(frame.insetBy(dx: metrics.shadowPadding, dy: 0).width,
                             metrics.minimumDockWidth * 4, "a busy dock still fills its room")
    }
}
