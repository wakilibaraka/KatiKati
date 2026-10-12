import XCTest
@testable import KatiKati

// Phase 8e — colour picker hex formatting.

final class ColorFormatTests: XCTestCase {
    func testPrimaryAndMidValues() {
        XCTAssertEqual(ColorFormat.hex(red: 1, green: 0, blue: 0), "#FF0000")
        XCTAssertEqual(ColorFormat.hex(red: 0, green: 0.5, blue: 1), "#0080FF")
        XCTAssertEqual(ColorFormat.hex(red: 0, green: 0, blue: 0), "#000000")
    }

    func testOutOfRangeAndNonFiniteAreClamped() {
        XCTAssertEqual(ColorFormat.hex(red: 2, green: -1, blue: .nan), "#FF0000")
    }
}
