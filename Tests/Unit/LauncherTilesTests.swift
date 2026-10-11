import XCTest
@testable import KatiKati

final class LauncherTilesTests: XCTestCase {
    func testFrozenIDsAndParse() {
        XCTAssertEqual(LauncherTile.allCases.map(\.rawValue), ["clock", "calculator", "countdown"])
        XCTAssertEqual(LauncherTile.parse("files, clock,bogus,clock"), [.clock], "the retired files id is ignored")
        XCTAssertEqual(LauncherTile.parse(nil), [])
        XCTAssertEqual(LauncherTile.ordered([.countdown, .clock]), [.clock, .countdown])
    }

    func testCalculatorBasics() {
        XCTAssertEqual(CalculatorEngine.evaluate("12+6"), 18)
        XCTAssertEqual(CalculatorEngine.evaluate("2+3*4"), 14)
        XCTAssertEqual(CalculatorEngine.evaluate("(2+3)*4"), 20)
        XCTAssertEqual(CalculatorEngine.evaluate("-3 + 5"), 2)
        XCTAssertEqual(CalculatorEngine.evaluate("10/4"), 2.5)
        XCTAssertEqual(CalculatorEngine.evaluate("50%"), 0.5)
        XCTAssertEqual(CalculatorEngine.evaluate("3×4÷2"), 6)
        XCTAssertEqual(CalculatorEngine.evaluate("3x4"), 12)
        XCTAssertEqual(CalculatorEngine.evaluate("1,5+1"), 2.5)
    }

    func testCalculatorRejectsMalformed() {
        for bad in ["", "+", "2+", "(2", "2)", "1/0", "abc", "1..2"] {
            XCTAssertNil(CalculatorEngine.evaluate(bad), bad)
        }
    }

    func testFormat() {
        XCTAssertEqual(CalculatorEngine.format(18), "18")
        XCTAssertEqual(CalculatorEngine.format(0.1 + 0.2), "0.3")
        XCTAssertEqual(CalculatorEngine.format(2.5), "2.5")
        XCTAssertEqual(CalculatorEngine.format(-0.25), "-0.25")
        XCTAssertEqual(CalculatorEngine.format(1.0 / 3.0), "0.333333333")
    }
}
