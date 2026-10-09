import XCTest
@testable import KatiKati

final class IslandStripProjectionTests: XCTestCase {
    func testBarSectionTitles() {
        XCTAssertEqual(BarSection.weather.title, "Weather")
        XCTAssertEqual(BarSection.apps.title, "Apps")
        XCTAssertEqual(BarSection.clock.title, "Clock")
    }

    func testSectionPlaceholderEntryID() {
        XCTAssertEqual(BarSection.weather.placeholderEntryID, "sec-weather")
        XCTAssertEqual(BarSection.clock.placeholderEntryID, "sec-clock")
    }

    func testHostedSectionsAcrossModes() {
        // Windows mode: 1 slot hosting all sections
        let windowsIslands = BarSection.islands(for: .windows)
        XCTAssertEqual(windowsIslands.count, 1)
        XCTAssertTrue(windowsIslands[0].contains(.apps))
        XCTAssertTrue(windowsIslands[0].contains(.weather))

        // Centered mode: 1 slot hosting all sections
        let centeredIslands = BarSection.islands(for: .centered)
        XCTAssertEqual(centeredIslands.count, 1)
        XCTAssertTrue(centeredIslands[0].contains(.apps))

        // Split3 mode: 3 slots
        let split3Islands = BarSection.islands(for: .split3)
        XCTAssertEqual(split3Islands.count, 3)
        XCTAssertEqual(split3Islands[0], [.weather])
        XCTAssertFalse(split3Islands[0].contains(.apps))
        XCTAssertEqual(split3Islands[1], [.apps, .media])
        XCTAssertTrue(split3Islands[1].contains(.apps))
        XCTAssertEqual(split3Islands[2], [.clock])
        XCTAssertFalse(split3Islands[2].contains(.apps))

        // Split4 mode: the split-4 rule yields 3 groups for the canonical order
        // (Phase 4U decision 8b removed `tray`)
        let split4Islands = BarSection.islands(for: .split4)
        XCTAssertEqual(split4Islands.count, 3)
        XCTAssertEqual(split4Islands[0], [.weather])
        XCTAssertEqual(split4Islands[1], [.apps, .media])
        XCTAssertEqual(split4Islands[2], [.clock])
        XCTAssertFalse(split4Islands[0].contains(.apps))
        XCTAssertTrue(split4Islands[1].contains(.apps))
        XCTAssertFalse(split4Islands[2].contains(.apps))
    }

    func testSlotIndexForMode() {
        XCTAssertEqual(BarSection.weather.slotIndex(for: .windows), 0)
        XCTAssertEqual(BarSection.apps.slotIndex(for: .windows), 0)

        XCTAssertEqual(BarSection.weather.slotIndex(for: .split3), 0)
        XCTAssertEqual(BarSection.apps.slotIndex(for: .split3), 1)
        XCTAssertEqual(BarSection.clock.slotIndex(for: .split3), 2)

        XCTAssertEqual(BarSection.weather.slotIndex(for: .split4), 0)
        XCTAssertEqual(BarSection.apps.slotIndex(for: .split4), 1)
        XCTAssertEqual(BarSection.clock.slotIndex(for: .split4), 2)
    }
}
