import XCTest
@testable import KatiKati

// Phase 8e — link cleaner rules.

final class URLCleanerTests: XCTestCase {
    func testStripsUTMAndClickIdsKeepsTheRest() {
        XCTAssertEqual(
            URLCleaner.clean("https://example.com/p?id=7&utm_source=x&UTM_Campaign=y&fbclid=abc&q=a%20b#frag"),
            "https://example.com/p?id=7&q=a%20b#frag")
    }

    func testRemovingEveryParameterDropsTheQuestionMark() {
        XCTAssertEqual(URLCleaner.clean("https://example.com/a?utm_source=x&gclid=1"), "https://example.com/a")
    }

    func testNothingToCleanReturnsNil() {
        XCTAssertNil(URLCleaner.clean("https://example.com/a?id=1&ref=home&si=abc&v=2"))
        XCTAssertNil(URLCleaner.clean("https://example.com/a"))
    }

    func testOnlyAPlainSingleHTTPURLIsTouched() {
        XCTAssertNil(URLCleaner.clean("see https://example.com/?utm_source=x for details"))
        XCTAssertNil(URLCleaner.clean("ftp://example.com/?utm_source=x"))
        XCTAssertNil(URLCleaner.clean("example.com/?utm_source=x"))
        XCTAssertNil(URLCleaner.clean(""))
        XCTAssertNil(URLCleaner.clean("https://?utm_source=x"))
    }

    func testSurroundingWhitespaceIsTolerated() {
        XCTAssertEqual(URLCleaner.clean("  https://example.com/?utm_medium=m\n"), "https://example.com/")
    }

    func testEncodedTrackingNameAndValuelessParam() {
        XCTAssertEqual(URLCleaner.clean("https://example.com/?%75tm_source=1&keep&fbclid"), "https://example.com/?keep")
    }
}
