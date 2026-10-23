import XCTest
@testable import KatiKati

final class ClipboardIgnoreRulesTests: XCTestCase {

    func testParsesSubstringAndRegexOnePerLine() {
        let rules = ClipboardIgnoreRules.parseLines("secret\n/^\\d{16}$/\n\n  token  ")
        XCTAssertEqual(rules, [.substring("secret"), .regex("^\\d{16}$"), .substring("token")])
    }

    func testSubstringIsCaseInsensitive() {
        let rules = ClipboardIgnoreRules.parseLines("Secret")
        XCTAssertTrue(ClipboardIgnoreRules.matches("my SECRET value", rules: rules))
        XCTAssertFalse(ClipboardIgnoreRules.matches("nothing here", rules: rules))
    }

    func testRegexRule() {
        let rules = ClipboardIgnoreRules.parseLines("/\\d{16}/")
        XCTAssertTrue(ClipboardIgnoreRules.matches("4111111111111111", rules: rules))
        XCTAssertFalse(ClipboardIgnoreRules.matches("no digits", rules: rules))
    }

    func testNoRulesNeverMatches() {
        XCTAssertFalse(ClipboardIgnoreRules.matches("anything", rules: []))
    }

    func testInvalidRegexIsIgnoredNotCrashing() {
        let rules = ClipboardIgnoreRules.parseLines("/([/")
        XCTAssertFalse(ClipboardIgnoreRules.matches("anything", rules: rules))
    }
}

final class ClipboardToastPolicyTests: XCTestCase {

    func testBlankTextDoesNotToast() {
        XCTAssertFalse(ClipboardToastPolicy.shouldToast(""))
        XCTAssertFalse(ClipboardToastPolicy.shouldToast("   \n\t"))
    }

    func testOrdinaryTextToasts() {
        XCTAssertTrue(ClipboardToastPolicy.shouldToast("hello"))
    }
}

final class PasteImageNamingTests: XCTestCase {

    private func name(_ existing: Set<String>) -> String {
        PasteImageNaming.uniqueName(base: "Clipboard Image", fileExtension: "png", existing: existing)
    }

    func testPlainNameWhenNothingExists() {
        XCTAssertEqual(name([]), "Clipboard Image.png")
    }

    func testCountsUpPastEveryTakenName() {
        XCTAssertEqual(name(["Clipboard Image.png", "Clipboard Image 2.png"]), "Clipboard Image 3.png")
    }

    func testExistingNamesAreMatchedCaseInsensitively() {
        XCTAssertEqual(name(["clipboard image.PNG"]), "Clipboard Image 2.png")
    }

    func testNeverHandsBackATakenName() {
        var existing = Set<String>()
        for _ in 0..<5 {
            let next = name(existing)
            XCTAssertFalse(existing.contains(next.lowercased()), next)
            existing.insert(next.lowercased())
        }
        XCTAssertEqual(existing.count, 5)
    }
}
