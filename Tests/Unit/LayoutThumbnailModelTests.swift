import CoreGraphics
import XCTest

final class LayoutThumbnailModelTests: XCTestCase {
    func testIslandCountMatchesEachModesSlotCount() {
        let expected: [BarLayoutMode: Int] = [.windows: 1, .split3: 3, .split4: 4, .split5: 5, .centered: 1]
        for mode in BarLayoutMode.allCases {
            let islands = LayoutThumbnailModel.islands(for: mode)
            XCTAssertEqual(islands.count, expected[mode], "\(mode)")
            XCTAssertEqual(islands.count, mode.slotCount, "\(mode): thumbnail and panel slots agree")
        }
    }

    func testEveryRectStaysInsideTheUnitBoxAndEverySectionAppearsOnce() {
        for mode in BarLayoutMode.allCases {
            let islands = LayoutThumbnailModel.islands(for: mode)
            for island in islands {
                XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).insetBy(dx: -1e-9, dy: -1e-9).contains(island.rect), "\(mode) slot \(island.slot)")
                XCTAssertGreaterThan(island.rect.width, 0)
            }
            XCTAssertEqual(islands.flatMap(\.sections).sorted { $0.rawValue < $1.rawValue },
                           BarSection.canonicalOrder.sorted { $0.rawValue < $1.rawValue }, "\(mode)")
        }
    }

    func testBottomGapMovesIslandsTowardTheEdge() {
        var hug = LayoutThumbnailModel.Inputs()
        hug.bottomGap = 2
        let floating = LayoutThumbnailModel.islands(for: .split3)[0].rect
        let hugging = LayoutThumbnailModel.islands(for: .split3, inputs: hug)[0].rect
        XCTAssertEqual(floating.maxY, 1 - 8 / 900, accuracy: 1e-9)
        XCTAssertEqual(hugging.maxY, 1 - 2 / 900, accuracy: 1e-9)
    }

    func testCenteredWidthWidensTheCenteredIsland() {
        var wide = LayoutThumbnailModel.Inputs()
        wide.centeredWidth = 1300
        let narrow = LayoutThumbnailModel.islands(for: .centered)[0].rect
        let widened = LayoutThumbnailModel.islands(for: .centered, inputs: wide)[0].rect
        XCTAssertGreaterThan(widened.width, narrow.width)
        // Bar + capsule are centred together, as on the live bar.
        let capsule = LayoutThumbnailModel.capsule(beside: LayoutThumbnailModel.islands(for: .centered, inputs: wide),
                                                   barHeight: wide.barHeight)!
        XCTAssertEqual((widened.minX + capsule.maxX) / 2, 0.5, accuracy: 1e-6)
    }

    func testEveryModeDrawsTheCapsuleOnScreenWithoutOverlap() {
        for mode in BarLayoutMode.allCases {
            let islands = LayoutThumbnailModel.islands(for: mode)
            let capsule = LayoutThumbnailModel.capsule(beside: islands, barHeight: LayoutThumbnailModel.Inputs().barHeight)
            XCTAssertNotNil(capsule, "\(mode)")
            guard let capsule else { continue }
            XCTAssertLessThanOrEqual(capsule.maxX, 1 + 1e-9, "\(mode)")
            for island in islands {
                XCTAssertFalse(island.rect.intersects(capsule), "\(mode) slot \(island.slot)")
            }
        }
    }

    func testRailThumbnailsRunDownTheSideWithTheCapsuleBelowApps() {
        var inputs = LayoutThumbnailModel.Inputs()
        inputs.placement = .left
        for mode in BarLayoutMode.allCases {
            let islands = LayoutThumbnailModel.islands(for: mode, inputs: inputs)
            XCTAssertEqual(islands.count, BarSection.islands(for: StripPlacement.left.effectiveMode(mode)).count, "\(mode)")
            for island in islands {
                XCTAssertLessThan(island.rect.minX, 0.1, "\(mode): hugs the left edge")
                XCTAssertGreaterThan(island.rect.height, island.rect.width * 0.5, "\(mode): runs vertically")
            }
            let capsule = LayoutThumbnailModel.capsule(for: mode, inputs: inputs)
            let apps = islands.first { $0.sections.contains(.apps) }!.rect
            XCTAssertNotNil(capsule)
            XCTAssertGreaterThanOrEqual(capsule!.minY, apps.maxY - 1e-9, "\(mode): capsule below the apps island")
        }
    }
}

