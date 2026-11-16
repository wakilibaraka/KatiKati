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

final class ClipboardCardMetadataTests: XCTestCase {

    func testClassifyTextCountsCharsAndWords() {
        let meta = ClipboardCardMetadata.classify(text: "Hello world from KatiKati")
        if case .text(let chars, let words) = meta.contentType {
            XCTAssertEqual(chars, 25)
            XCTAssertEqual(words, 4)
        } else {
            XCTFail("Expected text content type")
        }
        XCTAssertEqual(meta.category, .personal)
    }

    func testClassifyHexColors() {
        let meta6 = ClipboardCardMetadata.classify(text: "#FF8000")
        if case .hexColor(let hex, let color) = meta6.contentType {
            XCTAssertEqual(hex, "#FF8000")
            XCTAssertEqual(color.r, 1.0, accuracy: 0.01)
            XCTAssertEqual(color.g, 128.0 / 255.0, accuracy: 0.01)
            XCTAssertEqual(color.b, 0.0, accuracy: 0.01)
            XCTAssertEqual(color.a, 1.0)
        } else {
            XCTFail("Expected hexColor content type for 6-digit hex")
        }

        let meta3 = ClipboardCardMetadata.classify(text: "#F80")
        if case .hexColor(let hex, let color) = meta3.contentType {
            XCTAssertEqual(hex, "#FF8800")
            XCTAssertEqual(color.r, 1.0, accuracy: 0.01)
        } else {
            XCTFail("Expected hexColor content type for 3-digit hex")
        }
    }

    func testClassifyImage() {
        let meta = ClipboardCardMetadata.classifyImage(width: 1920, height: 1080)
        if case .image(let w, let h) = meta.contentType {
            XCTAssertEqual(w, 1920)
            XCTAssertEqual(h, 1080)
        } else {
            XCTFail("Expected image content type")
        }
    }

    func testCategoryClassification() {
        let workApps: Set<String> = ["com.tinyspeck.slackmacgap", "com.microsoft.teams"]
        let workMeta = ClipboardCardMetadata.classify(text: "meeting notes", originBundleID: "com.tinyspeck.slackmacgap", workBundleIDs: workApps)
        XCTAssertEqual(workMeta.category, .work)

        let personalMeta = ClipboardCardMetadata.classify(text: "recipe list", originBundleID: "com.apple.Safari", workBundleIDs: workApps)
        XCTAssertEqual(personalMeta.category, .personal)
    }
}
