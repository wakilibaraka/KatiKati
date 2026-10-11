import XCTest
@testable import KatiKati

final class LauncherAppearanceTests: XCTestCase {
    func testDefaults() {
        XCTAssertEqual(LauncherTheme.parse(nil), .system)
        XCTAssertEqual(LauncherTheme.parse("nope"), .system)
        XCTAssertEqual(LauncherTint.parse(nil), .none)
        XCTAssertEqual(LauncherIconStyle.parse(nil), .orbit)
        XCTAssertEqual(LauncherIconStyle.parse("petal"), .petal)
    }

    func testFrozenRawValues() {
        XCTAssertEqual(LauncherTheme.allCases.map(\.rawValue), ["system", "light", "dark", "glass", "desktop"])
        XCTAssertEqual(LauncherTint.allCases.map(\.rawValue), ["none", "blue", "purple", "pink", "orange", "green"])
        XCTAssertEqual(LauncherIconStyle.allCases.map(\.rawValue), ["orbit", "tiles", "petal"])
    }

    func testTintRGBInRangeAndNoneIsNil() {
        XCTAssertNil(LauncherTint.none.rgb)
        for t in LauncherTint.allCases.dropFirst() {
            let c = t.rgb!
            XCTAssertTrue([c.r, c.g, c.b].allSatisfy { (0...1).contains($0) })
        }
    }
}
