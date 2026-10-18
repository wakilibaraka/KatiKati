import XCTest

// `TimeOfDayPalette.swift` is dual-compiled.

final class TimeOfDayPaletteTests: XCTestCase {
    func testPhasesFollowTheHour() {
        XCTAssertEqual(TimeOfDayPalette(hour: 2).phase, .night)
        XCTAssertEqual(TimeOfDayPalette(hour: 6).phase, .dawn)
        XCTAssertEqual(TimeOfDayPalette(hour: 13).phase, .day)
        XCTAssertEqual(TimeOfDayPalette(hour: 19).phase, .dusk)
        XCTAssertEqual(TimeOfDayPalette(hour: 22).phase, .night)
    }

    func testKeyframesAreExactAndMidpointsBlend() {
        XCTAssertEqual(TimeOfDayPalette(hour: 12).tint, TimeOfDayPalette.RGB(red: 0.45, green: 0.72, blue: 1.00))
        let mid = TimeOfDayPalette(hour: 9).tint
        XCTAssertEqual(mid.red, (0.98 + 0.45) / 2, accuracy: 1e-9)
    }

    func testMidnightWrapsWithoutASeam() {
        XCTAssertEqual(TimeOfDayPalette(hour: 0).tint, TimeOfDayPalette(hour: 24).tint)
        XCTAssertEqual(TimeOfDayPalette(hour: -1).tint, TimeOfDayPalette(hour: 23).tint)
        XCTAssertEqual(TimeOfDayPalette(hour: 49).tint, TimeOfDayPalette(hour: 1).tint)
    }
}
