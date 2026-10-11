import XCTest
@testable import KatiKati

final class CaptureRulesTests: XCTestCase {
    private func block(_ t: String, x: CGFloat, y: CGFloat) -> CaptureRules.Block {
        .init(text: t, box: CGRect(x: x, y: y, width: 0.2, height: 0.05))
    }

    func testReadingOrderIsTopToBottomThenLeftToRight() {
        let blocks = [block("world", x: 0.5, y: 0.80), block("second", x: 0.1, y: 0.60),
                      block("hello", x: 0.1, y: 0.81), block("line", x: 0.4, y: 0.605)]
        XCTAssertEqual(CaptureRules.readingOrder(blocks), "hello world\nsecond line")
    }

    func testBlankBlocksAreDroppedAndEmptyInputIsEmpty() {
        XCTAssertEqual(CaptureRules.readingOrder([block("  ", x: 0, y: 0.5), block("a", x: 0, y: 0.1)]), "a")
        XCTAssertEqual(CaptureRules.readingOrder([]), "")
    }

    func testOnlyWebLinksAreOpenable() {
        XCTAssertNotNil(CaptureRules.openableURL(" https://example.com/a?b=1 "))
        XCTAssertNotNil(CaptureRules.openableURL("http://example.com"))
        XCTAssertNil(CaptureRules.openableURL("file:///etc/hosts"))
        XCTAssertNil(CaptureRules.openableURL("tel:+123456"))
        XCTAssertNil(CaptureRules.openableURL("WIFI:S:home;T:WPA;P:secret;;"))
        XCTAssertNil(CaptureRules.openableURL("https://"))
        XCTAssertNil(CaptureRules.openableURL("javascript:alert(1)"))
    }

    func testUniquePayloadsKeepOrderAndDropBlanks() {
        XCTAssertEqual(CaptureRules.uniquePayloads(["a", " a ", "", "b", "a"]), ["a", "b"])
    }
}
