import Foundation

/// Phase 27a: the pure command-bar core. `CommandBarResults.build` is the whole "what rows does the
/// palette show for this query" decision — answer rows, running-app quit rows, then app matches. The
/// platform layer (`NSWorkspace`/`NSRunningApplication`) only maps its objects into these value types.
/// No AppKit here.

/// A running application, mapped from `NSRunningApplication` so the ordering stays pure and testable.
struct RunningAppRef: Equatable, Sendable {
    var bundleID: String
    var name: String
    var pid: Int32
    var path: String
}

/// One row in the command bar.
enum CommandBarResult: Equatable, Sendable {
    /// A math or web answer (Phase 21's `LauncherAnswer`).
    case answer(LauncherAnswer)
    /// Launch (or focus) an installed app.
    case app(LauncherApp)
    /// Quit a running app (graceful `terminate()`; the UI confirms first).
    case quit(RunningAppRef)
    /// A generated value (Phase 28a): copy it.
    case generator(CommandGenerator, value: String)
}

/// Phase 28a: a generator row — type a keyword, get a fresh value to copy. The pure cases make their own
/// value here; system-backed ones (JSON / IP / Wi-Fi) are filled by the app layer when it calls
/// `CommandBarResults.build(generate:)`.
enum CommandGenerator: String, CaseIterable, Sendable {
    case uuid
    case nanoID = "nanoid"
    case loremIpsum = "lorem"
    case formatJSON = "json"
    case ipAddress = "ip"
    case wifiPassword = "wifi"

    var keyword: String { rawValue }

    /// Shown in the row (not localized — these are proper names).
    var displayName: String {
        switch self {
        case .uuid: return "UUID"
        case .nanoID: return "NanoID"
        case .loremIpsum: return "Lorem Ipsum"
        case .formatJSON: return "Format JSON"
        case .ipAddress: return "IP Address"
        case .wifiPassword: return "Wi-Fi Password"
        }
    }

    /// System-backed generators read the clipboard / network / keychain, so the app layer fills their
    /// value (`GeneratorService`); the pure cases make their own.
    var isSystemBacked: Bool {
        switch self {
        case .uuid, .nanoID, .loremIpsum: return false
        case .formatJSON, .ipAddress, .wifiPassword: return true
        }
    }

    /// Matches only the complete keyword (case-insensitive). Prefix matching would surface a generator
    /// for every app whose name starts with `u`/`n`/`l`, so the user types the word in full.
    static func match(_ query: String) -> CommandGenerator? {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return nil }
        return allCases.first { $0.keyword == q }
    }

    func value() -> String {
        var rng = SystemRandomNumberGenerator()
        return value(using: &rng)
    }

    func value<R: RandomNumberGenerator>(using rng: inout R) -> String {
        switch self {
        case .uuid: return UUID().uuidString
        case .nanoID: return Self.nanoID(using: &rng)
        case .loremIpsum: return Self.loremIpsum(using: &rng)
        case .formatJSON, .ipAddress, .wifiPassword: return ""   // filled by GeneratorService
        }
    }

    static let nanoIDLength = 21
    private static let alphabet = Array("_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

    private static func nanoID<R: RandomNumberGenerator>(using rng: inout R) -> String {
        String((0..<nanoIDLength).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &rng)] })
    }

    private static let loremWords = ["lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit",
                                     "sed", "do", "eiusmod", "tempor", "incididunt", "ut", "labore", "et", "dolore",
                                     "magna", "aliqua", "enim", "veniam", "quis", "nostrud", "exercitation"]

    private static func loremIpsum<R: RandomNumberGenerator>(using rng: inout R) -> String {
        let words = (0..<12).map { _ in loremWords[Int.random(in: 0..<loremWords.count, using: &rng)] }
        let sentence = words.joined(separator: " ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst() + "."
    }
}

/// Phase 28b: pretty-print a JSON string, or nil if it isn't valid JSON. Pure and unit-tested.
enum JSONPrettyPrinter {
    static func pretty(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let pretty = try? JSONSerialization.data(withJSONObject: object,
                                                       options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: pretty, encoding: .utf8) else { return nil }
        return text
    }
}

enum CommandBarResults {
    /// The rows for `query`, in display order: answers / generator → running-app quit rows → app matches.
    /// A non-app route (math/web) yields only its answer rows. Empty input yields nothing. `generate`
    /// fills a generator's value (the app layer handles the system-backed ones).
    static func build(query: String,
                      apps: [LauncherApp],
                      usage: [String: LauncherUsage],
                      running: [RunningAppRef],
                      generate: (CommandGenerator) -> String = { $0.value() }) -> [CommandBarResult] {
        let routed = LauncherCommandParser.parse(query)
        guard case .apps(let term) = routed else {
            return LauncherAnswers.answers(for: routed).map(CommandBarResult.answer)
        }
        guard !term.isEmpty else { return [] }

        var out: [CommandBarResult] = []
        if let generator = CommandGenerator.match(term) {
            let value = generate(generator)
            if !value.isEmpty { out.append(.generator(generator, value: value)) }
        }

        let quits = running
            .filter { LauncherSearch.score(query: term, name: $0.name) != nil }
            .sorted { a, b in
                let sa = LauncherSearch.score(query: term, name: a.name) ?? 0
                let sb = LauncherSearch.score(query: term, name: b.name) ?? 0
                return sa != sb ? sa > sb : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            .map(CommandBarResult.quit)

        return out + quits + LauncherSearch.search(term, in: apps, usage: usage).map(CommandBarResult.app)
    }
}

/// Phase 27a: the Spotlight hand-off. macOS has no API to take ⌘Space, so the bar guides the user to
/// free it. The steps are cases (the UI owns the localized copy, so this stays string-free); the URL
/// deep-links System Settings › Keyboard.
enum SpotlightHandoff {
    enum Step: Int, CaseIterable, Equatable, Sendable {
        case openKeyboard
        case openShortcuts
        case selectSpotlight
        case uncheckShowSearch
        case testHere
    }

    static let settingsURL = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"

    static func steps() -> [Step] { Step.allCases }
}
