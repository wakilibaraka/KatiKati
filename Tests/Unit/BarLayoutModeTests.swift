import XCTest
@testable import KatiKati

final class BarLayoutModeTests: XCTestCase {
    func testAllFourModesExist() {
        XCTAssertEqual(BarLayoutMode.allCases.count, 4)
        XCTAssertEqual(BarLayoutMode.allCases, [.windows, .split3, .split4, .centered])
    }

    func testSlotCountsAndSplitFlags() {
        XCTAssertEqual(BarLayoutMode.windows.slotCount, 1)
        XCTAssertTrue(BarLayoutMode.windows.isSingleIsland)
        XCTAssertFalse(BarLayoutMode.windows.isSplit)

        XCTAssertEqual(BarLayoutMode.split3.slotCount, 3)
        XCTAssertFalse(BarLayoutMode.split3.isSingleIsland)
        XCTAssertTrue(BarLayoutMode.split3.isSplit)

        XCTAssertEqual(BarLayoutMode.split4.slotCount, 3)
        // Decision 8b (`.tray` removed): the split-4 rule yields the same 3 groups as
        // split3 for the canonical order — a 4th slot would allocate a phantom panel.
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
        XCTAssertEqual(windowsIslands[0], [.weather, .apps, .media, .clock])

        let split3Islands = BarSection.islands(for: .split3)
        XCTAssertEqual(split3Islands.count, 3)
        XCTAssertEqual(split3Islands[0], [.weather])
        XCTAssertEqual(split3Islands[1], [.apps])
        XCTAssertEqual(split3Islands[2], [.clock])

        let split4Islands = BarSection.islands(for: .split4)
        XCTAssertEqual(split4Islands.count, 3)
        XCTAssertEqual(split4Islands[0], [.weather])
        XCTAssertEqual(split4Islands[1], [.apps])
        XCTAssertEqual(split4Islands[2], [.clock])

        let centeredIslands = BarSection.islands(for: .centered)
        XCTAssertEqual(centeredIslands.count, 1)
        XCTAssertEqual(centeredIslands[0], [.weather, .apps, .media, .clock])
    }

    func testEverySectionLivesInExactlyOneIslandPerMode() {
        for mode in BarLayoutMode.allCases {
            let groups = BarSection.islands(for: mode)
            let flattened = groups.flatMap { $0 }
            XCTAssertEqual(flattened.count, BarSection.allCases.count)
            XCTAssertEqual(Set(flattened), Set(BarSection.allCases))
        }
    }

    func testSlotIndexForSections() {
        XCTAssertEqual(BarSection.weather.slotIndex(for: .split3), 0)
        XCTAssertEqual(BarSection.apps.slotIndex(for: .split3), 1)
        XCTAssertEqual(BarSection.clock.slotIndex(for: .split3), 2)

        XCTAssertEqual(BarSection.weather.slotIndex(for: .split4), 0)
        XCTAssertEqual(BarSection.apps.slotIndex(for: .split4), 1)
        XCTAssertEqual(BarSection.clock.slotIndex(for: .split4), 2)

        XCTAssertEqual(BarSection.apps.slotIndex(for: .windows), 0)
        XCTAssertEqual(BarSection.apps.slotIndex(for: .centered), 0)
    }

    // MARK: - Hardcoded order + settings-only widths (Phase 4U decision 3, 2026-10-09)

    func testCanonicalOrderIsHardcoded() {
        // Declaration order IS the canonical widget order: no reader, no writer.
        XCTAssertEqual(BarSection.allCases, [.weather, .apps, .media, .clock])
    }

    func testDefaultWidgetWidths() {
        XCTAssertEqual(BarSection.weather.defaultWidgetWidth, 120)
        XCTAssertEqual(BarSection.apps.defaultWidgetWidth, 0)
        XCTAssertEqual(BarSection.clock.defaultWidgetWidth, 160)
    }
}
