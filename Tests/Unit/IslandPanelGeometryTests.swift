import XCTest
@testable import KatiKati

final class IslandPanelGeometryTests: XCTestCase {
    private let testScreen = PanelScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
        safeAreaTop: 25
    )

    func testWindowsModeMatchesDockTargetFrame() {
        let metrics = PanelLayoutMetrics.tungstenEdge
        let contentWidth: CGFloat = 500

        let legacyFrame = PanelGeometry.dockTargetFrame(
            contentWidth: contentWidth,
            on: testScreen,
            metrics: metrics
        )
        let islandFrame = PanelGeometry.islandTargetFrame(
            slot: 0,
            contentWidth: contentWidth,
            mode: .windows,
            on: testScreen,
            metrics: metrics
        )

        XCTAssertEqual(islandFrame, legacyFrame)
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
}
