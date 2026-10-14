import XCTest
@testable import KatiKati

final class LauncherAnswersTests: XCTestCase {

    func testMathEvaluatesToAnAnswerRow() {
        XCTAssertEqual(LauncherAnswers.answers(for: .math("2+2")), [.math(expression: "2+2", value: "4")])
    }

    func testMathThatDoesNotEvaluateHasNoRow() {
        XCTAssertTrue(LauncherAnswers.answers(for: .math("not maths")).isEmpty)
    }

    func testWebAlwaysYieldsASearchRow() {
        XCTAssertEqual(LauncherAnswers.answers(for: .web("swift news")), [.web(query: "swift news")])
        XCTAssertTrue(LauncherAnswers.answers(for: .web("")).isEmpty)
    }

    func testAppAndOtherRoutesHaveNoAnswer() {
        XCTAssertTrue(LauncherAnswers.answers(for: .apps("Safari")).isEmpty)
        XCTAssertTrue(LauncherAnswers.answers(for: .path("/tmp")).isEmpty)
        XCTAssertTrue(LauncherAnswers.answers(for: .script("ls")).isEmpty)
        XCTAssertTrue(LauncherAnswers.answers(for: .shortcut("Clean Up")).isEmpty)
    }
}
