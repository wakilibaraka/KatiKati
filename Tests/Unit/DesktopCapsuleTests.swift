import CoreGraphics
import Foundation
import XCTest

final class DesktopCapsuleTests: XCTestCase {
    func testCapsuleModeCodableRoundTrip() throws {
        let modes: [DesktopCapsuleMode] = [
            .expanded,
            .capsule,
            .edgeDocked(edge: .left),
            .edgeDocked(edge: .right),
            .edgeDocked(edge: .top),
            .edgeDocked(edge: .bottom)
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for mode in modes {
            let data = try encoder.encode(mode)
            let decoded = try decoder.decode(DesktopCapsuleMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    func testLegacyWidgetItemDecodesToExpandedCapsuleMode() throws {
        let legacyJSON = #"{"title":"Downloads","frame":{"x":10,"y":20,"width":240,"height":200}}"#
        let item = try JSONDecoder().decode(DesktopWidgetItem.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(item.capsuleMode, .expanded)
    }

    func testCapsuleLayoutFloatingAnchorAndClamping() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let expanded = CGRect(x: 100, y: 100, width: 300, height: 200)

        let capsule = DesktopCapsuleLayout.capsuleFrame(for: expanded, visibleFrame: visibleFrame, edgeMargin: 12)
        XCTAssertEqual(capsule.width, DesktopCapsuleLayout.standardCapsuleSize.width)
        XCTAssertEqual(capsule.height, DesktopCapsuleLayout.standardCapsuleSize.height)
        XCTAssertEqual(capsule.minX, 100)
        // Top edge of expanded is 100 + 200 = 300. Top edge of capsule is capsule.y + 32 = 300 -> capsule.y = 268
        XCTAssertEqual(capsule.maxY, expanded.maxY)

        // Test clamping off right edge
        let nearRight = CGRect(x: 1400, y: 500, width: 200, height: 200)
        let clampedCapsule = DesktopCapsuleLayout.capsuleFrame(for: nearRight, visibleFrame: visibleFrame, edgeMargin: 12)
        XCTAssertLessThanOrEqual(clampedCapsule.maxX, visibleFrame.maxX - 12)
    }

    func testCapsuleLayoutEdgeDockedPositions() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

        let left = DesktopCapsuleLayout.dockedFrame(edge: .left, positionRatio: 0.5, visibleFrame: visibleFrame)
        XCTAssertEqual(left.minX, visibleFrame.minX + DesktopCapsuleLayout.dockedEdgePeekMargin)

        let right = DesktopCapsuleLayout.dockedFrame(edge: .right, positionRatio: 0.5, visibleFrame: visibleFrame)
        XCTAssertEqual(right.maxX, visibleFrame.maxX - DesktopCapsuleLayout.dockedEdgePeekMargin)

        let top = DesktopCapsuleLayout.dockedFrame(edge: .top, positionRatio: 0.5, visibleFrame: visibleFrame)
        XCTAssertEqual(top.maxY, visibleFrame.maxY - DesktopCapsuleLayout.dockedEdgePeekMargin)

        let bottom = DesktopCapsuleLayout.dockedFrame(edge: .bottom, positionRatio: 0.5, visibleFrame: visibleFrame)
        XCTAssertEqual(bottom.minY, visibleFrame.minY + DesktopCapsuleLayout.dockedEdgePeekMargin)
    }

    func testCapsuleLayoutExpandedFrameFromCapsule() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let capsule = CGRect(x: 100, y: 500, width: 150, height: 32)
        let originalSize = CGSize(width: 300, height: 250)

        // Floating expansion
        let floatingExpanded = DesktopCapsuleLayout.expandedFrame(
            from: capsule,
            originalSize: originalSize,
            dockedEdge: nil,
            visibleFrame: visibleFrame
        )
        XCTAssertEqual(floatingExpanded.width, 300)
        XCTAssertEqual(floatingExpanded.height, 250)
        XCTAssertEqual(floatingExpanded.minX, 100)
        XCTAssertEqual(floatingExpanded.maxY, capsule.maxY)

        // Edge docked expansion (left edge expands rightward from left edge)
        let leftCapsule = CGRect(x: 4, y: 400, width: 150, height: 32)
        let leftExpanded = DesktopCapsuleLayout.expandedFrame(
            from: leftCapsule,
            originalSize: originalSize,
            dockedEdge: .left,
            visibleFrame: visibleFrame
        )
        XCTAssertEqual(leftExpanded.minX, visibleFrame.minX + 12)
    }

    func testCapsuleHoverPolicyInteractionLock() {
        // Hovered with no locks -> remains expanded
        XCTAssertTrue(DesktopCapsuleHoverPolicy.shouldRemainExpanded(isHovered: true, activeLocks: []))

        // Not hovered with no locks -> collapses
        XCTAssertFalse(DesktopCapsuleHoverPolicy.shouldRemainExpanded(isHovered: false, activeLocks: []))

        // Not hovered but inline rename lock active -> remains expanded!
        XCTAssertTrue(DesktopCapsuleHoverPolicy.shouldRemainExpanded(isHovered: false, activeLocks: [.inlineRename]))

        // Not hovered but popover lock active -> remains expanded!
        XCTAssertTrue(DesktopCapsuleHoverPolicy.shouldRemainExpanded(isHovered: false, activeLocks: [.popover]))

        // Multiple locks
        XCTAssertTrue(DesktopCapsuleHoverPolicy.shouldRemainExpanded(isHovered: false, activeLocks: [.contextMenu, .drag]))
    }

    func testEdgePositionRatioCalculation() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        var item = DesktopWidgetItem(title: "Downloads", frame: CGRect(x: 100, y: 400, width: 200, height: 100))
        // midY = 450 -> ratio = 450 / 900 = 0.5
        XCTAssertEqual(item.edgePositionRatio(for: .left, in: visibleFrame), 0.5, accuracy: 0.001)
        XCTAssertEqual(item.edgePositionRatio(for: .right, in: visibleFrame), 0.5, accuracy: 0.001)

        // midX = 200 -> ratio = 200 / 1440 ~ 0.1388
        XCTAssertEqual(item.edgePositionRatio(for: .top, in: visibleFrame), 200.0 / 1440.0, accuracy: 0.001)
    }
}
