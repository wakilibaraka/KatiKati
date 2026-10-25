import XCTest
@testable import KatiKati

final class BarLayoutModeTests: XCTestCase {
    func testAllFiveModesExist() {
        XCTAssertEqual(BarLayoutMode.allCases.count, 5)
        XCTAssertEqual(BarLayoutMode.allCases, [.windows, .split3, .split4, .split5, .centered])
    }

    func testSplit5SeparatesEveryOuterSection() {
        let islands = BarSection.islands(for: .split5)
        XCTAssertEqual(islands, [[.launcher], [.weather], [.apps, .media], [.clock], [.widgets]])
        XCTAssertEqual(BarLayoutMode.split5.slotCount, 5)
        XCTAssertTrue(BarLayoutMode.split5.isSplit)
        XCTAssertEqual(BarSection.widgets.slotIndex(for: .split5), 4)
    }

    func testSplitModesAreAllDistinct() {
        let counts = [BarLayoutMode.split3, .split4, .split5].map { $0.slotCount }
        XCTAssertEqual(counts, [3, 4, 5])
    }

    func testSlotCountsAndSplitFlags() {
        XCTAssertEqual(BarLayoutMode.windows.slotCount, 1)
        XCTAssertTrue(BarLayoutMode.windows.isSingleIsland)
        XCTAssertFalse(BarLayoutMode.windows.isSplit)

        XCTAssertEqual(BarLayoutMode.split3.slotCount, 3)
        XCTAssertFalse(BarLayoutMode.split3.isSingleIsland)
        XCTAssertTrue(BarLayoutMode.split3.isSplit)

        XCTAssertEqual(BarLayoutMode.split4.slotCount, 4)
        // 4U-A: split4 detaches media into its own island (launcher·weather | apps | media | clock·widgets).
        XCTAssertFalse(BarLayoutMode.split4.isSingleIsland)
        XCTAssertTrue(BarLayoutMode.split4.isSplit)

        XCTAssertEqual(BarLayoutMode.centered.slotCount, 1)
        XCTAssertTrue(BarLayoutMode.centered.isSingleIsland)
        XCTAssertFalse(BarLayoutMode.centered.isSplit)
    }

    func testTitlesAndDetailsNotEmpty() {
        for mode in BarLayoutMode.allCases {
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.detail.isEmpty)
            XCTAssertEqual(mode.id, mode.rawValue)
        }
    }

    func testCodableRoundTrip() throws {
        for mode in BarLayoutMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(BarLayoutMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    func testSectionIslandsPerMode() {
        let windowsIslands = BarSection.islands(for: .windows)
        XCTAssertEqual(windowsIslands.count, 1)
        XCTAssertEqual(windowsIslands[0], BarSection.defaultOrder)

        let split3Islands = BarSection.islands(for: .split3)
        XCTAssertEqual(split3Islands.count, 3)
        XCTAssertEqual(split3Islands[0], [.launcher, .weather])
        XCTAssertEqual(split3Islands[1], [.apps, .media])
        XCTAssertEqual(split3Islands[2], [.clock, .widgets])

        let split4Islands = BarSection.islands(for: .split4)
        XCTAssertEqual(split4Islands.count, 4)
        XCTAssertEqual(split4Islands[0], [.launcher, .weather])
        XCTAssertEqual(split4Islands[1], [.apps])
        XCTAssertEqual(split4Islands[2], [.media])
        XCTAssertEqual(split4Islands[3], [.clock, .widgets])

        let centeredIslands = BarSection.islands(for: .centered)
        XCTAssertEqual(centeredIslands.count, 1)
        XCTAssertEqual(centeredIslands[0], BarSection.defaultOrder)
    }

    func testEverySectionLivesInExactlyOneIslandPerMode() {
        for mode in BarLayoutMode.allCases {
            let groups = BarSection.islands(for: mode)
            let flattened = groups.flatMap { $0 }
            XCTAssertEqual(flattened.count, BarSection.defaultOrder.count)
            XCTAssertEqual(Set(flattened), Set(BarSection.defaultOrder))
        }
    }

    func testSlotIndexForSections() {
        XCTAssertEqual(BarSection.weather.slotIndex(for: .split3), 0)
        XCTAssertEqual(BarSection.apps.slotIndex(for: .split3), 1)
        XCTAssertEqual(BarSection.clock.slotIndex(for: .split3), 2)

        XCTAssertEqual(BarSection.weather.slotIndex(for: .split4), 0)
        XCTAssertEqual(BarSection.apps.slotIndex(for: .split4), 1)
        XCTAssertEqual(BarSection.clock.slotIndex(for: .split4), 3)

        XCTAssertEqual(BarSection.apps.slotIndex(for: .windows), 0)
        XCTAssertEqual(BarSection.apps.slotIndex(for: .centered), 0)
    }

    // MARK: - Hardcoded order + settings-only widths (Phase 4U decision 3, 2026-10-09)

    func testCanonicalOrderIsHardcoded() {
        // Declaration order IS the canonical widget order: no reader, no writer.
        XCTAssertEqual(BarSection.allCases, BarSection.canonicalOrder)
        XCTAssertEqual(BarSection.defaultOrder, [.launcher, .weather, .apps, .media, .clock, .widgets])
    }

    func testDefaultWidgetWidths() {
        XCTAssertEqual(BarSection.weather.defaultWidgetWidth, 150)
        XCTAssertEqual(BarSection.apps.defaultWidgetWidth, 0)
        XCTAssertEqual(BarSection.media.defaultWidgetWidth, 215)
        XCTAssertEqual(BarSection.clock.defaultWidgetWidth, 160)
    }

    func testFABSectionsAreSquareAndIdentified() {
        for fab in [BarSection.launcher, .widgets] {
            XCTAssertEqual(fab.defaultWidgetWidth, 40)
            XCTAssertEqual(fab.minimumWidgetWidth, 40)
        }
        XCTAssertEqual(BarSection.launcher.title, "Launcher")
        XCTAssertEqual(BarSection.widgets.title, "Widgets")
        XCTAssertEqual(BarSection.launcher.placeholderEntryID, "sec-launcher")
        XCTAssertEqual(BarSection.widgets.placeholderEntryID, "sec-widgets")
    }
}
