import XCTest
@testable import KatiKati

final class TranslateRequestTests: XCTestCase {

    func testBlankIsNotTranslatable() {
        let r = TranslateRequest.detect("   \n ")
        XCTAssertEqual(r.text, "")
        XCTAssertFalse(r.isTranslatable)
    }

    func testProseIsTranslatableAndTrimmed() {
        let r = TranslateRequest.detect("  bonjour le monde  ")
        XCTAssertEqual(r.text, "bonjour le monde")
        XCTAssertTrue(r.isTranslatable)
    }

    func testURLsAndNumbersShortCircuit() {
        for text in ["https://example.com", "example.com", "12345", "3.14", "!!!"] {
            XCTAssertFalse(TranslateRequest.isWorthTranslating(text), text)
        }
    }

    func testSingleWordWithLettersIsTranslatable() {
        XCTAssertTrue(TranslateRequest.isWorthTranslating("serendipity"))
    }
}

final class TranslationAvailabilityTests: XCTestCase {

    func testTranslateNeedsMacOS15() {
        XCTAssertFalse(TranslationAvailability.translateAvailable(os: OperatingSystemVersion(majorVersion: 12, minorVersion: 0, patchVersion: 0)))
        XCTAssertFalse(TranslationAvailability.translateAvailable(os: OperatingSystemVersion(majorVersion: 14, minorVersion: 6, patchVersion: 0)))
        XCTAssertTrue(TranslationAvailability.translateAvailable(os: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)))
        XCTAssertTrue(TranslationAvailability.translateAvailable(os: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)))
    }
}

final class DictionaryCardModelTests: XCTestCase {

    func testParsesHeadwordAndSenses() {
        let payload = "run | rʌn | verb\nmove fast\noperate"
        let card = DictionaryCardModel.parse(headword: "run", payload: payload)
        XCTAssertEqual(card?.headword, "run")
        XCTAssertEqual(card?.senses, ["move fast", "operate"])
    }

    func testSingleLinePayloadKeepsTheRestAsASense() {
        let card = DictionaryCardModel.parse(headword: "cat", payload: "cat | kat | noun")
        XCTAssertEqual(card?.headword, "cat")
        XCTAssertEqual(card?.senses, ["kat | noun"])
    }

    func testNilOrEmptyPayloadIsNoCard() {
        XCTAssertNil(DictionaryCardModel.parse(headword: "x", payload: nil))
        XCTAssertNil(DictionaryCardModel.parse(headword: "x", payload: "   \n "))
    }

    func testBlankHeadFallsBackToTheQuery() {
        let card = DictionaryCardModel.parse(headword: "query", payload: " | note\nsomething")
        XCTAssertEqual(card?.headword, "query")
    }
}
