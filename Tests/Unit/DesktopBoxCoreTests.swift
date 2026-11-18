import CoreGraphics
import Foundation
import XCTest
@testable import KatiKati

final class DesktopBoxCoreTests: XCTestCase {
    private let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func testWidgetItemLenientDecodeAndClamping() throws {
        let legacyJSON = Data("""
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "title": "Projects",
          "frame": { "x": 40, "y": 50, "width": 20, "height": 30 },
          "iconSizeOverride": 200
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(DesktopWidgetItem.self, from: legacyJSON)
        XCTAssertEqual(decoded.kind, .folder)
        XCTAssertEqual(decoded.title, "Projects")
        XCTAssertEqual(decoded.frame.width, DesktopWidgetItem.minimumSize.width)
        XCTAssertEqual(decoded.frame.height, DesktopWidgetItem.minimumSize.height)
        XCTAssertEqual(decoded.iconSizeOverride, DesktopCanvasConfig.iconSizeRange.upperBound)
        XCTAssertEqual(decoded.filenameLines, .two)
        XCTAssertEqual(decoded.sortMode, .rule(.dateAdded))
    }

    func testWidgetItemRoundTripWithManualSort() throws {
        let item = DesktopWidgetItem(
            title: "Inbox",
            backingPath: "/tmp/Inbox/",
            displayUUID: "DISP-1",
            frame: CGRect(x: 100, y: 200, width: 320, height: 260),
            normalizedFrame: NormalizedWidgetRect(x: 0.1, y: 0.2, width: 0.3, height: 0.25),
            viewStyle: .compactList,
            compactDensity: true,
            iconSizeOverride: 32,
            filenameLines: .one,
            sortMode: .manual,
            manualOrder: ["b.txt", "a.txt"],
            isHidden: true,
            zOrder: 4
        )
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(DesktopWidgetItem.self, from: data)
        XCTAssertEqual(decoded, item)
        XCTAssertEqual(decoded.backingPath, "/tmp/Inbox")
    }

    func testClampRespectsMinimumSizeAndEdgeMargin() {
        let tinyOut = CGRect(x: -50, y: 2000, width: 10, height: 20)
        let clamped = DesktopLayoutEngine.clamp(tinyOut, in: screenFrame, edgeMargin: 12)
        XCTAssertEqual(clamped.width, 50)
        XCTAssertEqual(clamped.height, 50)
        XCTAssertEqual(clamped.minX, 12)
        XCTAssertEqual(clamped.maxY, 1068)
    }

    func testSnapMoveSnapsToSiblingGapAndScreenEdge() {
        let sibling = CGRect(x: 200, y: 500, width: 300, height: 200)
        let candidate = CGRect(x: 517, y: 504, width: 250, height: 200) // 5px from sibling.maxX + 12 (512)
        let snapped = DesktopLayoutEngine.snapMove(
            candidate: candidate,
            others: [sibling],
            visibleFrame: screenFrame,
            gap: 12,
            edgeMargin: 12
        )
        XCTAssertEqual(snapped.frame.minX, 512)
        XCTAssertEqual(snapped.frame.minY, 500)
        XCTAssertEqual(snapped.snappedX, 512)
        XCTAssertEqual(snapped.snappedY, 500)
    }

    func testSnapResizeRespectsMinimumSizeAndSnapsEdge() {
        let origin = CGRect(x: 100, y: 100, width: 200, height: 200)
        let shrinkTooFar = DesktopLayoutEngine.snapResize(
            origin: origin,
            handle: .right,
            delta: CGSize(width: -180, height: 0),
            others: [],
            visibleFrame: screenFrame,
            gap: 12,
            edgeMargin: 12
        )
        XCTAssertEqual(shrinkTooFar.frame.minX, 100)
        XCTAssertEqual(shrinkTooFar.frame.width, 50)

        let sibling = CGRect(x: 412, y: 100, width: 200, height: 200)
        let snapToSibling = DesktopLayoutEngine.snapResize(
            origin: origin,
            handle: .right,
            delta: CGSize(width: 96, height: 0), // maxX -> 396, within 10pt of 412 - 12 = 400
            others: [sibling],
            visibleFrame: screenFrame,
            gap: 12,
            edgeMargin: 12
        )
        XCTAssertEqual(snapToSibling.frame.maxX, 400)
        XCTAssertEqual(snapToSibling.snappedX, 400)
    }

    func testBoundedGroupMovePreservesRelativeSpacingAndClampsUnion() {
        let a = UUID()
        let b = UUID()
        let frames: [UUID: CGRect] = [
            a: CGRect(x: 100, y: 100, width: 200, height: 200),
            b: CGRect(x: 320, y: 150, width: 200, height: 200)
        ]
        // Dragging far left should stop when `a` hits edgeMargin (12), moving both by -88
        let moved = DesktopLayoutEngine.boundedGroupMove(
            frames: frames,
            delta: CGSize(width: -200, height: 25),
            visibleFrame: screenFrame,
            edgeMargin: 12
        )
        XCTAssertEqual(moved[a]?.minX, 12)
        XCTAssertEqual(moved[b]?.minX, 232)
        XCTAssertEqual(moved[a]?.minY, 125)
        XCTAssertEqual(moved[b]?.minY, 175)
    }

    func testNormalizeAndDenormalizeAcrossScaleJump() {
        let hd = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let fourK = CGRect(x: 0, y: 0, width: 3840, height: 2160)
        let box = CGRect(x: 192, y: 108, width: 384, height: 270)
        let norm = DesktopLayoutEngine.normalize(box, in: hd)
        let reflowed = DesktopLayoutEngine.denormalize(norm, in: fourK, edgeMargin: 12)
        XCTAssertEqual(reflowed.minX, 384, accuracy: 0.5)
        XCTAssertEqual(reflowed.minY, 216, accuracy: 0.5)
        XCTAssertEqual(reflowed.width, 768, accuracy: 0.5)
        XCTAssertEqual(reflowed.height, 540, accuracy: 0.5)
    }

    func testResolveDisplayHonorsFollowMainAndFallback() {
        let table = WindowDisplayAttribution.Table(
            displays: [
                .init(uuid: "MAIN", cgFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)),
                .init(uuid: "EXT", cgFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1080))
            ],
            primaryUUID: "MAIN"
        )
        var item = DesktopWidgetItem(title: "Ext", displayUUID: "EXT", followMainDisplay: false)
        XCTAssertEqual(DesktopLayoutEngine.resolveDisplay(for: item, table: table)?.uuid, "EXT")

        item.followMainDisplay = true
        XCTAssertEqual(DesktopLayoutEngine.resolveDisplay(for: item, table: table)?.uuid, "MAIN")

        item.followMainDisplay = false
        item.displayUUID = "DISCONNECTED"
        XCTAssertEqual(DesktopLayoutEngine.resolveDisplay(for: item, table: table)?.uuid, "MAIN")
    }

    func testManualOrderingReconcileAndMultiItemBlockReorder() {
        let t1 = Date(timeIntervalSince1970: 100)
        let t2 = Date(timeIntervalSince1970: 200)
        let entries: [FolderContentsLoader.Entry] = [
            .init(url: URL(fileURLWithPath: "/tmp/alpha.txt"), name: "alpha.txt", isDirectory: false, dateAdded: t1, dateModified: t1),
            .init(url: URL(fileURLWithPath: "/tmp/beta.txt"), name: "beta.txt", isDirectory: false, dateAdded: t2, dateModified: t2),
            .init(url: URL(fileURLWithPath: "/tmp/gamma.txt"), name: "gamma.txt", isDirectory: false, dateAdded: t1, dateModified: t1)
        ]

        let result = DesktopFolderOrdering.reconcile(
            entries: entries,
            manualOrder: ["gamma.txt", "deleted.txt", "alpha.txt"],
            sortMode: .manual
        )
        XCTAssertEqual(result.ordered.map { $0.url.lastPathComponent }, ["gamma.txt", "alpha.txt", "beta.txt"])
        XCTAssertEqual(result.updatedManualOrder, ["gamma.txt", "alpha.txt", "beta.txt"])

        let reordered = DesktopFolderOrdering.reorder(
            manualOrder: ["a", "b", "c", "d", "e"],
            moving: ["a", "c"],
            toIndex: 4
        )
        XCTAssertEqual(reordered, ["b", "d", "a", "c", "e"])
    }
}
