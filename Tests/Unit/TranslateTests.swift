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

final class DropClipPolicyTests: XCTestCase {

    func testStatsCountsWordsAndCharacters() {
        let stats = DropClipPolicy.stats(for: "Quick brown fox jumps")
        XCTAssertEqual(stats.charCount, 21)
        XCTAssertEqual(stats.wordCount, 4)
    }

    func testShouldPresentEnforcesLengthAndSensitivity() {
        // Normal text in standard app
        XCTAssertTrue(DropClipPolicy.shouldPresent(
            text: "Hello world",
            originBundleID: "com.apple.Safari",
            isSecureInput: false
        ))

        // Suppressed under secure input (password field)
        XCTAssertFalse(DropClipPolicy.shouldPresent(
            text: "MySecretPassword123",
            originBundleID: "com.apple.Safari",
            isSecureInput: true
        ))

        // Suppressed in excluded apps (1Password, Bitwarden, etc.)
        XCTAssertFalse(DropClipPolicy.shouldPresent(
            text: "Sensitive token",
            originBundleID: "com.agilebits.onepassword",
            isSecureInput: false
        ))

        // Suppressed if text is too short or blank
        XCTAssertFalse(DropClipPolicy.shouldPresent(
            text: "a",
            originBundleID: "com.apple.Safari",
            isSecureInput: false
        ))
        XCTAssertFalse(DropClipPolicy.shouldPresent(
            text: "   ",
            originBundleID: "com.apple.Safari",
            isSecureInput: false
        ))
    }

    func testActionsFiltersByContent() {
        let proseActions = DropClipPolicy.actions(for: "Translate this sentence please")
        XCTAssertTrue(proseActions.contains(.translate))
        XCTAssertTrue(proseActions.contains(.copy))
        XCTAssertTrue(proseActions.contains(.search))

        let urlActions = DropClipPolicy.actions(for: "https://example.com/test")
        XCTAssertFalse(urlActions.contains(.translate))
        XCTAssertTrue(urlActions.contains(.copy))
    }
}
