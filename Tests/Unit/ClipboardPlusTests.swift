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

        let defaultXcodeMeta = ClipboardCardMetadata.classify(text: "let x = 42", originBundleID: "com.apple.dt.Xcode")
        XCTAssertEqual(defaultXcodeMeta.category, .work)

        let personalMeta = ClipboardCardMetadata.classify(text: "recipe list", originBundleID: "com.apple.Safari", workBundleIDs: workApps)
        XCTAssertEqual(personalMeta.category, .personal)
    }

    func testClipboardToastBadge() {
        XCTAssertEqual(ClipboardToastBadge.badge(for: "#ff5500"), "#FF5500")
        XCTAssertEqual(ClipboardToastBadge.badge(for: "https://example.com", linkCleaned: true), "Link Cleaned")
        XCTAssertEqual(ClipboardToastBadge.badge(for: "https://example.com"), "URL")
        XCTAssertEqual(ClipboardToastBadge.badge(for: "hello"), "5 ch")
    }
}

/// Slice MC-2 — the Maccy-derived pure rules: pasteboard filter, capture mode, pin slots and key mapping.
final class MaccyClipboardTests: XCTestCase {
    func testConcealedAndRemoteCopiesAreFilteredByRule() {
        XCTAssertFalse(MaccyPasteboardFilter.shouldRecord(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        XCTAssertFalse(MaccyPasteboardFilter.shouldRecord(types: ["com.agilebits.onepassword"]))
        XCTAssertFalse(MaccyPasteboardFilter.shouldRecord(types: ["org.nspasteboard.TransientType"]))
        XCTAssertTrue(MaccyPasteboardFilter.shouldRecord(types: ["public.utf8-plain-text"]))
        var rules = MaccyPasteboardFilter.Rules()
        rules.ignoreConcealed = false
        XCTAssertTrue(MaccyPasteboardFilter.shouldRecord(types: ["org.nspasteboard.ConcealedType"], rules: rules))
    }

    func testUniversalClipboardAndUserIgnoresAreOptional() {
        let types = ["public.utf8-plain-text", "com.apple.is-remote-clipboard"]
        XCTAssertTrue(MaccyPasteboardFilter.shouldRecord(types: types))
        var rules = MaccyPasteboardFilter.Rules(ignoreUniversal: true)
        XCTAssertFalse(MaccyPasteboardFilter.shouldRecord(types: types, rules: rules))

        rules = MaccyPasteboardFilter.Rules(ignoredBundleIDs: ["com.example.Secret"], ignoredPatterns: ["token="])
        XCTAssertFalse(MaccyPasteboardFilter.shouldRecord(types: ["public.utf8-plain-text"],
                                                           sourceBundleID: "com.example.Secret", rules: rules))
        XCTAssertTrue(MaccyPasteboardFilter.shouldRecord(types: ["public.utf8-plain-text"],
                                                          sourceBundleID: "com.example.Other", text: "hello", rules: rules))
        XCTAssertFalse(MaccyPasteboardFilter.shouldRecord(types: ["public.utf8-plain-text"],
                                                           text: "api TOKEN=abc", rules: rules))
    }

    func testSkipNextCopyIgnoresExactlyOneCopy() {
        XCTAssertEqual(ClipboardCaptureMode.active.shouldRecordCopy().record, true)
        XCTAssertEqual(ClipboardCaptureMode.paused.shouldRecordCopy().record, false)
        XCTAssertEqual(ClipboardCaptureMode.paused.shouldRecordCopy().nextMode, .paused)

        let skipped = ClipboardCaptureMode.skipNextCopy.shouldRecordCopy()
        XCTAssertFalse(skipped.record)
        XCTAssertEqual(skipped.nextMode, .active, "the latch clears itself after one copy")
        XCTAssertEqual(skipped.nextMode.shouldRecordCopy().record, true)
    }

    func testPinSlotsStayPutAndStopAtNine() {
        let ids = (1...11).map { _ in UUID() }
        let first = MaccyPinShortcutAssigner.assign(pinnedIDs: ids)
        XCTAssertEqual(first[ids[0]], 1)
        XCTAssertEqual(first[ids[8]], 9)
        XCTAssertNil(first[ids[9]], "a tenth pin is unnumbered")
        XCTAssertEqual(MaccyPinShortcutAssigner.assign(pinnedIDs: ids, previous: first), first)

        // Unpin the second: its slot is offered to the next unnumbered pin, everyone else keeps their number.
        let fewer = ids.enumerated().filter { $0.offset != 1 }.map(\.element)
        let second = MaccyPinShortcutAssigner.assign(pinnedIDs: fewer, previous: first)
        XCTAssertEqual(second[ids[0]], 1)
        XCTAssertNil(second[ids[1]])
        XCTAssertEqual(second[ids[9]], 2, "the gap left by an unpin is refilled")
        XCTAssertEqual(second[ids[8]], 9)
        XCTAssertEqual(MaccyPinShortcutAssigner.entryID(forSlot: 1, in: second), ids[0])
        XCTAssertEqual(MaccyPinShortcutAssigner.entryID(forSlot: 2, in: second), ids[9])
        XCTAssertNil(MaccyPinShortcutAssigner.entryID(forSlot: 10, in: second))
    }

    func testKeyboardTableMatchesMaccy() {
        XCTAssertEqual(MaccyKeyAction.action(key: "return", modifiers: []), .copy)
        XCTAssertEqual(MaccyKeyAction.action(key: "\r", modifiers: .option), .paste)
        XCTAssertEqual(MaccyKeyAction.action(key: "return", modifiers: [.option, .shift]), .pastePlain)
        XCTAssertEqual(MaccyKeyAction.action(key: "p", modifiers: .option), .togglePin)
        XCTAssertEqual(MaccyKeyAction.action(key: "delete", modifiers: .option), .delete)
        XCTAssertEqual(MaccyKeyAction.action(key: "backspace", modifiers: [.option, .command]), .clearUnpinned)
        XCTAssertEqual(MaccyKeyAction.action(key: "\u{7f}", modifiers: [.shift, .option, .command]), .clearAll)
        XCTAssertEqual(MaccyKeyAction.action(key: "1", modifiers: .command), .selectPinSlot(1))
        XCTAssertEqual(MaccyKeyAction.action(key: "9", modifiers: .command), .selectPinSlot(9))
        XCTAssertNil(MaccyKeyAction.action(key: "0", modifiers: .command))
        XCTAssertNil(MaccyKeyAction.action(key: "1", modifiers: [.command, .option]))
        XCTAssertNil(MaccyKeyAction.action(key: "return", modifiers: .command))
        XCTAssertNil(MaccyKeyAction.action(key: "x", modifiers: .option))
    }
}
