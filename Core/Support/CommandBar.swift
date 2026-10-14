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

/// A running process, mapped from `ps` so the process-killer list stays pure and testable.
struct ProcessEntry: Equatable, Sendable {
    var pid: Int32
    var name: String
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
    /// Force-quit a running app (`forceTerminate()`; the UI confirms first). Phase 29b (`fq `).
    case forceQuit(RunningAppRef)
    /// A native macOS action (Phase 29b): run it.
    case action(BarMacro)
    /// A generated value (Phase 28a): copy it.
    case generator(CommandGenerator, value: String)
    /// A user-defined entry (Phase 28c): open a link or run a script.
    case custom(CustomCommand)
    /// Kill a process (Phase 28e, `!name`): confirmed, then SIGTERM / SIGKILL.
    case process(ProcessEntry)
    /// A `>` script payload (Phase 29a) run through `LauncherRunner`.
    case script(String)
    /// A `:` Shortcut name (Phase 29a) run through `LauncherRunner`.
    case shortcut(String)
    /// A `/` path (Phase 29a) to open.
    case path(String)
    /// A filesystem result (Phase 29g): open / reveal / trash.
    case file(FileEntry)
    /// A clipboard-history entry (Phase 29h): copy it back.
    case clip(ClipEntry)
    /// A Trash operation (Phase 30d/e).
    case trash(TrashAction)
    /// An emoji (Phase 30f): copy it.
    case emoji(EmojiEntry)
    /// A browser bookmark (Phase 30g): open it.
    case bookmark(Bookmark)
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
    /// The rows for `query`. Math/web → answer rows; the word routes (`/` `>` `:` `!`) → their own rows;
    /// plain search → generator / custom / app matches, each running app's Quit row right after it.
    static func build(query: String,
                      apps: [LauncherApp],
                      usage: [String: LauncherUsage],
                      running: [RunningAppRef],
                      custom: [CustomCommand] = [],
                      processes: [ProcessEntry] = [],
                      files: [FileEntry] = [],
                      clips: [ClipEntry] = [],
                      bookmarks: [Bookmark] = [],
                      generate: (CommandGenerator) -> String = { $0.value() }) -> [CommandBarResult] {
        let keyword = CommandKeyword.parse(query)
        if case .mode(let mode, let argument)? = keyword {
            return modeRows(mode, argument, apps: apps, usage: usage, running: running, processes: processes, files: files, clips: clips, bookmarks: bookmarks)
        }
        let routed = LauncherCommandParser.parse(query)
        switch routed {
        case .process(let term):
            return processRows(term, processes)
        case .script(let payload):
            return payload.isEmpty ? [] : [.script(payload)]
        case .shortcut(let name):
            return name.isEmpty ? [] : [.shortcut(name)]
        case .path(let path):
            return [.path(path)]
        case .math, .web:
            return LauncherAnswers.answers(for: routed).map(CommandBarResult.answer)
        case .apps(let term):
            if term.lowercased() == "trash" { return [.trash(.open), .trash(.empty)] }
            var rows = appRows(term, apps: apps, usage: usage, running: running, custom: custom, generate: generate)
            if case .macro(let macro)? = keyword { rows.insert(.action(macro), at: 0) }
            return rows
        }
    }

    /// Answers / generator → custom → app matches, with a running app's Quit row immediately after it
    /// (Phase 29a), then any leftover running match.
    private static func appRows(_ term: String, apps: [LauncherApp], usage: [String: LauncherUsage],
                                running: [RunningAppRef], custom: [CustomCommand],
                                generate: (CommandGenerator) -> String) -> [CommandBarResult] {
        guard !term.isEmpty else { return [] }
        var out: [CommandBarResult] = []
        if let generator = CommandGenerator.match(term) {
            let value = generate(generator)
            if !value.isEmpty { out.append(.generator(generator, value: value)) }
        }
        out += CustomCommand.matching(term, in: custom).map(CommandBarResult.custom)

        var used = Set<String>()
        for app in LauncherSearch.search(term, in: apps, usage: usage) {
            out.append(.app(app))
            if let ref = running.first(where: { !$0.bundleID.isEmpty && $0.bundleID == app.bundleID }) {
                out.append(.quit(ref))
                used.insert(ref.bundleID)
            }
        }
        out += running
            .filter { !used.contains($0.bundleID) && LauncherSearch.score(query: term, name: $0.name) != nil }
            .sorted { a, b in
                let sa = LauncherSearch.score(query: term, name: a.name) ?? 0
                let sb = LauncherSearch.score(query: term, name: b.name) ?? 0
                return sa != sb ? sa > sb : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            .map(CommandBarResult.quit)
        return out
    }

    /// Rows for a keyword mode. `kill`/`fq` list running apps; `kp` lists processes; `sc` runs a named
    /// Shortcut; `app` forces an app search.
    private static func modeRows(_ mode: CommandBarMode, _ argument: String, apps: [LauncherApp],
                                 usage: [String: LauncherUsage], running: [RunningAppRef],
                                 processes: [ProcessEntry], files: [FileEntry], clips: [ClipEntry],
                                 bookmarks: [Bookmark]) -> [CommandBarResult] {
        switch mode {
        case .file, .image:
            return files.map(CommandBarResult.file)
        case .bookmark:
            return BookmarkImport.matching(argument, in: bookmarks).prefix(30).map(CommandBarResult.bookmark)
        case .clipboard:
            let needle = argument.lowercased()
            let matched = needle.isEmpty ? clips : clips.filter { $0.text.lowercased().contains(needle) }
            return matched.map(CommandBarResult.clip)
        case .emoji:
            return EmojiCatalog.matching(argument).prefix(40).map(CommandBarResult.emoji)
        case .kill, .forceQuit:
            let matched = argument.isEmpty
                ? running
                : running.filter { LauncherSearch.score(query: argument, name: $0.name) != nil }
            return matched
                .sorted { a, b in
                    let sa = LauncherSearch.score(query: argument, name: a.name) ?? 0
                    let sb = LauncherSearch.score(query: argument, name: b.name) ?? 0
                    return sa != sb ? sa > sb : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
                .map { mode == .kill ? .quit($0) : .forceQuit($0) }
        case .killProcess:
            return processRows(argument, processes)
        case .shortcut:
            return argument.isEmpty ? [] : [.shortcut(argument)]
        case .apps:
            return appRows(argument, apps: apps, usage: usage, running: running, custom: [], generate: { _ in "" })
        }
    }

    private static func processRows(_ term: String, _ processes: [ProcessEntry]) -> [CommandBarResult] {
        guard !term.isEmpty else { return [] }
        return processes
            .filter { LauncherSearch.score(query: term, name: $0.name) != nil }
            .sorted { a, b in
                let sa = LauncherSearch.score(query: term, name: a.name) ?? 0
                let sb = LauncherSearch.score(query: term, name: b.name) ?? 0
                return sa != sb ? sa > sb : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            .map(CommandBarResult.process)
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
