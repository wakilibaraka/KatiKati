import XCTest
@testable import KatiKati

final class LidSleepSudoersTests: XCTestCase {
    func testRuleNamesOnlyTheTwoPmsetCommands() {
        let rule = LidSleepSudoers.rule(user: "baraka")
        XCTAssertEqual(rule, "baraka ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0")
    }

    func testOddUserNamesAreRefused() {
        for bad in ["", "a b", "x;rm", "-evil", "a\nALL ALL=(ALL) NOPASSWD: ALL", "$(id)", String(repeating: "a", count: 33)] {
            XCTAssertNil(LidSleepSudoers.rule(user: bad), bad)
        }
        XCTAssertNotNil(LidSleepSudoers.rule(user: "first.last-2_x"))
    }
}
