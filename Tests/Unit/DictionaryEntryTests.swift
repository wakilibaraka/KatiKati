import XCTest
@testable import KatiKati

/// Fixtures are hand-built from the New Oxford American Dictionary's plain-text shape (`headword |phonetic| pos
/// 1 sense: example | example … ORIGIN …`): `DCSCopyTextDefinition` returned nil in the sandboxed shell this was
/// written in, so a live payload capture is owed in step 2 (see the plan).
final class DictionaryEntryTests: XCTestCase {
    private let serendipity = """
    serendipity |ˌserənˈdipədē| noun the occurrence and development of events by chance in a happy or \
    beneficial way: a fortunate stroke of serendipity | a series of small serendipities.ORIGIN 1754: coined by \
    Horace Walpole, suggested by The Three Princes of Serendip.
    """

    func testParsesHeadPhoneticSenseExamplesAndOrigin() throws {
        let entry = try XCTUnwrap(DictionaryEntry.parse(headword: "serendipity", payload: serendipity))
        XCTAssertEqual(entry.headword, "serendipity")
        XCTAssertEqual(entry.phonetic, "ˌserənˈdipədē")
        XCTAssertEqual(entry.blocks.count, 1)
        XCTAssertEqual(entry.blocks[0].partOfSpeech, "noun")
        XCTAssertEqual(entry.blocks[0].senses.count, 1)
        XCTAssertEqual(entry.blocks[0].senses[0].text, "the occurrence and development of events by chance in a happy or beneficial way")
        XCTAssertEqual(entry.blocks[0].senses[0].examples, ["a fortunate stroke of serendipity", "a series of small serendipities"])
        XCTAssertEqual(entry.origin?.hasPrefix("1754: coined by Horace Walpole"), true)
    }

    func testNumberedSensesAndTwoPartsOfSpeech() throws {
        let payload = "run |rən| verb 1 move at a speed faster than a walk: she ran home 2 operate: run a program. noun 1 an act of running: a morning run"
        let entry = try XCTUnwrap(DictionaryEntry.parse(headword: "run", payload: payload))
        XCTAssertEqual(entry.blocks.map(\.partOfSpeech), ["verb", "noun"])
        XCTAssertEqual(entry.blocks[0].senses.map(\.text), ["move at a speed faster than a walk", "operate"])
        XCTAssertEqual(entry.blocks[1].senses.map(\.text), ["an act of running"])
    }

    func testPartOfSpeechWordInsideASenseDoesNotSplit() throws {
        let payload = "gloss |glôs| noun a short note: the noun phrase is glossed"
        let entry = try XCTUnwrap(DictionaryEntry.parse(headword: "gloss", payload: payload))
        XCTAssertEqual(entry.blocks.count, 1)
        XCTAssertEqual(entry.blocks[0].senses[0].examples, ["the noun phrase is glossed"])
    }

    func testStrayNumberDoesNotSplitUnnumberedSense() throws {
        let payload = "word |wərd| noun a unit of language, about 3 letters long"
        let entry = try XCTUnwrap(DictionaryEntry.parse(headword: "word", payload: payload))
        XCTAssertEqual(entry.senseTexts, ["a unit of language, about 3 letters long"])
    }

    func testMultilinePayloadIsFlattened() throws {
        let payload = "cat |kat|\nnoun\n1 a small pet: tabby"
        let entry = try XCTUnwrap(DictionaryEntry.parse(headword: "cat", payload: payload))
        XCTAssertEqual(entry.blocks[0].senses.map(\.text), ["a small pet"])
    }

    func testUnexpectedShapeStillYieldsOnePlainSense() throws {
        let entry = try XCTUnwrap(DictionaryEntry.parse(headword: "thing", payload: "just some prose with no structure"))
        XCTAssertEqual(entry.headword, "thing")
        XCTAssertNil(entry.phonetic)
        XCTAssertEqual(entry.senseTexts, ["just some prose with no structure"])
    }

    func testNilAndBlankPayloadsAreNil() {
        XCTAssertNil(DictionaryEntry.parse(headword: "x", payload: nil))
        XCTAssertNil(DictionaryEntry.parse(headword: "x", payload: " \n "))
    }

    func testCopyTextNumbersSensesUnderPartOfSpeech() throws {
        let payload = "run |rən| verb 1 move fast 2 operate"
        let entry = try XCTUnwrap(DictionaryEntry.parse(headword: "run", payload: payload))
        XCTAssertEqual(entry.copyText, "run\nverb\n1. move fast\n2. operate")
    }
}
