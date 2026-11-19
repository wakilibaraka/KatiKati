import CoreGraphics
import Foundation
import XCTest

final class DesktopTopologyTests: XCTestCase {
    private let smallDisplay = TopologyDisplay(
        uuid: "SMALL",
        screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875)
    )
    private let largeDisplay = TopologyDisplay(
        uuid: "LARGE",
        screenFrame: CGRect(x: 1440, y: 0, width: 3840, height: 2160),
        visibleFrame: CGRect(x: 1440, y: 0, width: 3840, height: 2100)
    )

    // MARK: - Signature & archive

    func testSignatureIsCanonicalSortedAndDeduplicated() {
        XCTAssertEqual(DisplayTopologySignature.make(["B", "A", "B"]), "A|B")
        XCTAssertEqual(DisplayTopologySignature.make(["A", "B"]), DisplayTopologySignature.make(["B", "A", ""]))
        XCTAssertEqual(DisplayTopologySignature.uuids(in: "A|B"), ["A", "B"])
    }

    func testArchiveRecordingReplacesSignatureAndCapsEntries() {
        var archive = TopologyLayoutArchive()
        for index in 0..<5 {
            archive = archive.recording(TopologyArchiveEntry(
                signature: "S\(index)",
                displays: [smallDisplay],
                placements: [:],
                updatedAt: Date(timeIntervalSince1970: Double(index))
            ), limit: 3)
        }
        XCTAssertEqual(archive.entries.count, 3)
        XCTAssertEqual(archive.entries.map(\.signature), ["S4", "S3", "S2"])

        archive = archive.recording(TopologyArchiveEntry(
            signature: "S3",
            displays: [largeDisplay],
            placements: ["w": TopologyWidgetPlacement(
                displayUUID: "LARGE",
                normalizedFrame: NormalizedWidgetRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
                capsuleMode: .capsule
            )],
            updatedAt: Date(timeIntervalSince1970: 99)
        ), limit: 3)
        XCTAssertEqual(archive.entries.count, 3)
        XCTAssertEqual(archive.entries.first?.signature, "S3")
        XCTAssertEqual(archive.entries.first?.placements["w"]?.capsuleMode, .capsule)
    }

    func testArchiveCodableRoundTrip() throws {
        let entry = TopologyArchiveEntry(
            signature: "A|B",
            displays: [smallDisplay, largeDisplay],
            placements: ["id": TopologyWidgetPlacement(
                displayUUID: "LARGE",
                normalizedFrame: NormalizedWidgetRect(x: 0.25, y: 0.5, width: 0.2, height: 0.3),
                capsuleMode: .edgeDocked(edge: .left)
            )],
            updatedAt: Date(timeIntervalSince1970: 1000)
        )
        let archive = TopologyLayoutArchive(entries: [entry])
        let data = try JSONEncoder().encode(archive)
        let decoded = try JSONDecoder().decode(TopologyLayoutArchive.self, from: data)
        XCTAssertEqual(decoded, archive)
    }

    // MARK: - Similarity

    func testMostSimilarDisplayPrefersMatchingGeometry() {
        let third = TopologyDisplay(
            uuid: "THIRD",
            screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055)
        )
        let best = DisplayTopologySimilarity.mostSimilarDisplay(
            to: third,
            among: [smallDisplay, largeDisplay]
        )
        XCTAssertEqual(best?.uuid, "SMALL")

        let near4K = TopologyDisplay(
            uuid: "NEAR4K",
            screenFrame: CGRect(x: 0, y: 0, width: 3200, height: 1800),
            visibleFrame: CGRect(x: 0, y: 0, width: 3200, height: 1755)
        )
        XCTAssertEqual(
            DisplayTopologySimilarity.mostSimilarDisplay(to: near4K, among: [smallDisplay, largeDisplay])?.uuid,
            "LARGE"
        )

        let score = DisplayTopologySimilarity.displaySimilarity(smallDisplay, smallDisplay)
        XCTAssertEqual(score, 1, accuracy: 0.0001)
    }

    func testBestEntryUsesSharedDisplayUUIDs() {
        let current = [
            smallDisplay,
            TopologyDisplay(
                uuid: "REPLACEMENT",
                screenFrame: CGRect(x: 1440, y: 0, width: 3840, height: 2160),
                visibleFrame: CGRect(x: 1440, y: 0, width: 3840, height: 2100)
            )
        ]
        let unrelated = TopologyArchiveEntry(
            signature: "OTHER",
            displays: [TopologyDisplay(
                uuid: "OTHER",
                screenFrame: CGRect(x: 0, y: 0, width: 1280, height: 800),
                visibleFrame: CGRect(x: 0, y: 0, width: 1280, height: 775)
            )],
            placements: [:],
            updatedAt: Date()
        )
        let related = TopologyArchiveEntry(
            signature: "SMALL|LARGE",
            displays: [smallDisplay, largeDisplay],
            placements: [:],
            updatedAt: Date()
        )
        let best = DisplayTopologySimilarity.bestEntry(
            in: TopologyLayoutArchive(entries: [unrelated, related]),
            for: current
        )
        XCTAssertEqual(best?.signature, "SMALL|LARGE")
    }

    // MARK: - Disconnect / reconnect / seed

    func testDisconnectPlanRelocatesProportionallyOntoMostSimilarDisplay() {
        let widget = DesktopTopologyWidget(
            id: UUID(),
            displayUUID: "SMALL",
            normalizedFrame: NormalizedWidgetRect(x: 0.25, y: 0.5, width: 0.3, height: 0.2),
            frame: CGRect(x: 360, y: 437, width: 432, height: 175),
            capsuleMode: .expanded
        )
        let plan = DisplayDisconnectPlanner.disconnectPlan(
            disconnected: [smallDisplay],
            current: [largeDisplay],
            widgets: [widget],
            action: .relocate
        )
        let move = try? XCTUnwrap(plan.moves[widget.id])
        XCTAssertEqual(move?.kind, .relocate)
        XCTAssertEqual(move?.displayUUID, "LARGE")
        XCTAssertEqual(move?.normalizedFrame, widget.normalizedFrame)
        XCTAssertEqual(move?.capsuleMode, .expanded)
        XCTAssertEqual(plan.disconnectedUUIDs, ["SMALL"])
    }

    func testDisconnectPlanCollapseActionCapsulesWidgets() {
        let widget = DesktopTopologyWidget(
            id: UUID(),
            displayUUID: "SMALL",
            normalizedFrame: NormalizedWidgetRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            frame: CGRect(x: 144, y: 87, width: 288, height: 175),
            capsuleMode: .expanded
        )
        let plan = DisplayDisconnectPlanner.disconnectPlan(
            disconnected: [smallDisplay],
            current: [largeDisplay],
            widgets: [widget],
            action: .capsule
        )
        let move = try? XCTUnwrap(plan.moves[widget.id])
        XCTAssertEqual(move?.kind, .collapse)
        XCTAssertEqual(move?.capsuleMode, .capsule)
    }

    func testRestorePlanReturnsToExactArchivedSpot() {
        let widget = DesktopTopologyWidget(
            id: UUID(),
            displayUUID: "LARGE",
            normalizedFrame: NormalizedWidgetRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
            frame: .zero,
            capsuleMode: .expanded
        )
        let placements: [String: TopologyWidgetPlacement] = [
            widget.id.uuidString: TopologyWidgetPlacement(
                displayUUID: "SMALL",
                normalizedFrame: NormalizedWidgetRect(x: 0.7, y: 0.15, width: 0.18, height: 0.22),
                capsuleMode: .edgeDocked(edge: .right)
            )
        ]
        let plan = DisplayDisconnectPlanner.restorePlan(
            reconnectedUUIDs: ["SMALL"],
            widgets: [widget],
            placements: placements
        )
        let move = try? XCTUnwrap(plan.moves[widget.id])
        XCTAssertEqual(move?.kind, .restore)
        XCTAssertEqual(move?.displayUUID, "SMALL")
        XCTAssertEqual(move?.normalizedFrame.x, 0.7)
        XCTAssertEqual(move?.capsuleMode, .edgeDocked(edge: .right))

        let unrelated = DisplayDisconnectPlanner.restorePlan(
            reconnectedUUIDs: ["THIRD"],
            widgets: [widget],
            placements: placements
        )
        XCTAssertTrue(unrelated.moves.isEmpty)
    }

    func testFirstSeenSeedMapsOntoMostSimilarConnectedDisplay() {
        let widget = DesktopTopologyWidget(
            id: UUID(),
            displayUUID: nil,
            normalizedFrame: NormalizedWidgetRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            frame: .zero,
            capsuleMode: .expanded
        )
        let entry = TopologyArchiveEntry(
            signature: "SMALL|LARGE",
            displays: [smallDisplay, largeDisplay],
            placements: [
                widget.id.uuidString: TopologyWidgetPlacement(
                    displayUUID: "LARGE",
                    normalizedFrame: NormalizedWidgetRect(x: 0.55, y: 0.35, width: 0.2, height: 0.25),
                    capsuleMode: .expanded
                )
            ],
            updatedAt: Date()
        )
        let plan = DisplayDisconnectPlanner.seedPlan(
            entry: entry,
            current: [smallDisplay],
            widgets: [widget]
        )
        let move = try? XCTUnwrap(plan.moves[widget.id])
        XCTAssertEqual(move?.kind, .seed)
        XCTAssertEqual(move?.displayUUID, "SMALL")
        XCTAssertEqual(move?.normalizedFrame.x, 0.55)
    }

    // MARK: - Move-all undo

    func testMoveAllPlanScalesProportionallyAndUndoesExactly() {
        let source = TopologyDisplay(
            uuid: "A",
            screenFrame: CGRect(x: 100, y: 50, width: 1440, height: 900),
            visibleFrame: CGRect(x: 100, y: 50, width: 1440, height: 900)
        )
        let target = TopologyDisplay(
            uuid: "B",
            screenFrame: CGRect(x: 500, y: 300, width: 2880, height: 1800),
            visibleFrame: CGRect(x: 500, y: 300, width: 2880, height: 1800)
        )
        let item = DesktopWidgetItem(
            kind: .folder,
            title: "Box",
            displayUUID: "A",
            frame: CGRect(x: 244, y: 140, width: 288, height: 180),
            normalizedFrame: DesktopLayoutEngine.normalize(
                CGRect(x: 244, y: 140, width: 288, height: 180),
                in: source.visibleFrame.cgRect
            )
        )
        let plan = DesktopMoveAllPlanner.plan(
            items: [item],
            sourceDisplay: source,
            targetDisplay: target,
            edgeMargin: 0
        )
        let change = try? XCTUnwrap(plan.changes.first)
        XCTAssertEqual(change?.after.frame, CGRect(x: 788, y: 480, width: 576, height: 360))
        XCTAssertEqual(change?.after.displayUUID, "B")

        let moved = plan.applying([item], forward: true)
        XCTAssertEqual(moved.first?.frame, CGRect(x: 788, y: 480, width: 576, height: 360))

        let restored = plan.applying(moved, forward: false)
        XCTAssertEqual(restored.first?.frame, item.frame)
        XCTAssertEqual(restored.first?.displayUUID, "A")
        XCTAssertEqual(restored.first, item)
    }

    func testMoveAllPlanClampsIntoTargetVisibleFrame() {
        let source = TopologyDisplay(uuid: "A", screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 1000), visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        let target = TopologyDisplay(uuid: "B", screenFrame: CGRect(x: 0, y: 0, width: 300, height: 300), visibleFrame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let item = DesktopWidgetItem(
            kind: .folder,
            title: "Box",
            frame: CGRect(x: 900, y: 900, width: 400, height: 300),
            normalizedFrame: NormalizedWidgetRect(x: 0.9, y: 0.9, width: 0.4, height: 0.3)
        )
        let plan = DesktopMoveAllPlanner.plan(items: [item], sourceDisplay: source, targetDisplay: target, edgeMargin: 0)
        let frame = plan.changes.first?.after.frame ?? .zero
        XCTAssertEqual(frame.maxX, 300)
        XCTAssertEqual(frame.maxY, 300)
    }
}
