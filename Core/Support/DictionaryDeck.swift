import Foundation

/// SD-6: the EasyDict page's two pieces of state that deserve tests — the recent lookups and which word today
/// wears. Pure Foundation: the page owns the views and the system dictionary, so nothing here needs CoreServices.
struct DictionaryHistory: Equatable, Sendable {
    static let limit = 20
    static let defaultsKey = "com.katikati.dictionary.history"

    private(set) var words: [String] = []

    init(words: [String] = []) {
        self.words = Array(words.prefix(Self.limit))
    }

    /// A lookup that worked goes to the front, once. Matching ignores case and surrounding space, so "Canvas"
    /// never sits beside a stale "canvas".
    mutating func record(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        words.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        words.insert(trimmed, at: 0)
        if words.count > Self.limit { words.removeLast(words.count - Self.limit) }
    }

    /// The history as the page shows it: everything while the query is empty, otherwise the words that contain it.
    func matches(_ query: String) -> [String] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return words }
        return words.filter { $0.localizedCaseInsensitiveContains(needle) }
    }

    static func load(from defaults: UserDefaults = .standard) -> DictionaryHistory {
        DictionaryHistory(words: defaults.stringArray(forKey: defaultsKey) ?? [])
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(words, forKey: Self.defaultsKey)
    }
}

/// Today's word is picked by the calendar, not at random: the same day always shows the same word, so reopening
/// the page does not reshuffle it, and the list advances once a day.
enum WordOfTheDay {
    /// Words worth looking up, all answerable by the system dictionary, so the card never sends the owner to a
    /// blank entry.
    static let words: [String] = [
        "aplomb", "bucolic", "candour", "dapper", "ebullient", "fastidious", "garrulous", "halcyon",
        "idempotent", "jocular", "keen", "laconic", "munificent", "nadir", "obfuscate", "pellucid",
        "quixotic", "reticent", "sagacious", "taciturn", "ubiquitous", "verisimilitude", "wistful",
        "zealous", "abstruse", "brevity", "cogent", "diffident", "ephemeral", "frugal", "gregarious", "heuristic",
    ]

    static func index(on date: Date, calendar: Calendar = .current) -> Int {
        guard !words.isEmpty else { return 0 }
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return day % words.count
    }

    static func word(on date: Date = Date(), calendar: Calendar = .current) -> String {
        guard !words.isEmpty else { return "" }
        return words[index(on: date, calendar: calendar)]
    }
}
