import XCTest
@testable import KatiKati

/// SD-6: the EasyDict page's recent-lookup history and the day's word, tested without a dictionary, a window
/// or a calendar the test cannot control.
final class DictionaryDeckTests: XCTestCase {
    private func makeDefaults() -> (UserDefaults, String) {
        let name = "DictionaryDeckTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (defaults, name)
    }

    func testRecordingPutsTheWordFirstAndOnlyOnce() {
        var history = DictionaryHistory()
        history.record("canvas")
        history.record("marble")
        XCTAssertEqual(history.words, ["marble", "canvas"])

        history.record("Canvas")
        XCTAssertEqual(history.words, ["Canvas", "marble"], "a repeat moves to the front instead of sitting twice")
    }

    func testBlankLookupsNeverEnterTheHistory() {
        var history = DictionaryHistory()
        history.record("")
        history.record("   ")
        history.record("\n")
        XCTAssertTrue(history.words.isEmpty)
    }

    func testTheHistoryIsCappedAtTwentyMostRecent() {
        var history = DictionaryHistory()
        for index in 0..<25 { history.record("word\(index)") }
        XCTAssertEqual(history.words.count, DictionaryHistory.limit)
        XCTAssertEqual(history.words.first, "word24")
        XCTAssertEqual(history.words.last, "word5")
    }

    func testLoadingCapsAStoredListThatGrewSomehow() {
        let long = (0..<40).map { "w\($0)" }
        XCTAssertEqual(DictionaryHistory(words: long).words.count, DictionaryHistory.limit)
    }

    func testTheQueryFiltersTheHistory() {
        var history = DictionaryHistory()
        history.record("canvas")
        history.record("marble")
        history.record("cartography")
        XCTAssertEqual(history.matches("  "), ["cartography", "marble", "canvas"])
        XCTAssertEqual(history.matches("ca"), ["cartography", "canvas"])
        XCTAssertEqual(history.matches("car"), ["cartography"])
        XCTAssertEqual(history.matches("MAR"), ["marble"], "matching ignores case")
        XCTAssertEqual(history.matches("zzz"), [])
    }

    func testTheHistorySurvivesARoundTrip() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        var history = DictionaryHistory.load(from: defaults)
        XCTAssertTrue(history.words.isEmpty, "a fresh install starts empty")
        history.record("canvas")
        history.record("marble")
        history.save(to: defaults)

        let reloaded = DictionaryHistory.load(from: defaults)
        XCTAssertEqual(reloaded.words, ["marble", "canvas"])
    }

    func testTheWordOfTheDayIsStableWithinADayAndChangesAcrossDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 12))!

        let morning = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 8))!
        XCTAssertEqual(WordOfTheDay.word(on: morning, calendar: calendar),
                       WordOfTheDay.word(on: noon, calendar: calendar),
                       "the same day must not reshuffle")

        let tomorrow = calendar.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 12))!
        XCTAssertNotEqual(WordOfTheDay.word(on: noon, calendar: calendar),
                          WordOfTheDay.word(on: tomorrow, calendar: calendar),
                          "a new day advances the list")
    }

    func testEveryDayPicksAWordFromTheList() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        for offset in 0..<400 {
            let date = calendar.date(byAdding: .day, value: offset,
                                     to: calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!)!
            let index = WordOfTheDay.index(on: date, calendar: calendar)
            XCTAssertTrue((0..<WordOfTheDay.words.count).contains(index))
            XCTAssertFalse(WordOfTheDay.word(on: date, calendar: calendar).isEmpty)
        }
    }
}
