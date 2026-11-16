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

/// Phase 30i: a calendar event (title + start), mapped from EventKit so the bar stays free of it.
struct EventEntry: Equatable, Sendable {
    var id: String
    var title: String
    var start: Date
    var allDay: Bool
}

/// One row in the command bar.
enum CommandBarResult: Equatable, Sendable, Identifiable {
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
    /// A calendar event (Phase 30i): open Calendar.
    case event(EventEntry)
    /// A menu item of the app that was frontmost when the bar opened (port plan #3): press it.
    case menuItem(MenuSearchEntry)
    /// A stored bar profile (port plan #4): apply it.
    case profile(BarProfileSummary)
    /// `profile save <name>`: store the bar as it is now under that name.
    case saveProfile(String)
    /// `define <word>`: open the dictionary panel on the word.
    case define(String)
    /// Port plan #4′: a user-defined quicklink template with its optional `{query}` argument.
    case quicklink(Quicklink, argument: String)
    /// Fallback row to search files across the system when direct search has no match.
    case searchFilesFallback(String)
    /// Fallback row to ask AI when direct search has no match.
    case askAI(String)

    var id: String {
        switch self {
        case .answer(let answer):
            switch answer {
            case .math(let expression, let value):
                return "answer:math:\(expression)=\(value)"
            case .web(let query):
                return "answer:web:\(query)"
            }
        case .searchFilesFallback(let term):
            return "fallback:files:\(term)"
        case .askAI(let term):
            return "fallback:ai:\(term)"
        case .app(let app):
            return "app:\(app.bundleID):\(app.path)"
        case .quit(let ref):
            return "quit:\(ref.bundleID):\(ref.pid)"
        case .forceQuit(let ref):
            return "forceQuit:\(ref.bundleID):\(ref.pid)"
        case .action(let macro):
            return "action:\(macro.keyword)"
        case .generator(let gen, let value):
            return "generator:\(gen.rawValue):\(value)"
        case .custom(let cmd):
            return "custom:\(cmd.name):\(cmd.target)"
        case .process(let entry):
            return "process:\(entry.pid):\(entry.name)"
        case .script(let payload):
            return "script:\(payload)"
        case .shortcut(let name):
            return "shortcut:\(name)"
        case .path(let path):
            return "path:\(path)"
        case .file(let entry):
            return "file:\(entry.path)"
        case .clip(let entry):
            return "clip:\(entry.id)"
        case .trash(let action):
            return "trash:\(action.rawValue)"
        case .emoji(let entry):
            return "emoji:\(entry.char):\(entry.name)"
        case .bookmark(let bookmark):
            return "bookmark:\(bookmark.title):\(bookmark.url)"
        case .event(let event):
            return "event:\(event.id)"
        case .menuItem(let entry):
            return "menu:\(entry.id)"
        case .profile(let summary):
            return "profile:\(summary.id)"
        case .saveProfile(let name):
            return "saveProfile:\(name)"
        case .define(let word):
            return "define:\(word)"
        case .quicklink(let link, let argument):
            return "quicklink:\(link.name):\(link.template):\(argument)"
        }
    }

    var kindBadge: String {
        switch self {
        case .answer(.math): return "Math"; case .answer(.web): return "Web Search"; case .app: return "Application"
        case .quit: return "Quit"; case .forceQuit: return "Force Quit"; case .action: return "System"
        case .generator: return "Generator"; case .custom: return "Custom"; case .process: return "Process"
        case .script: return "Script"; case .shortcut: return "Shortcut"; case .path: return "Path"
        case .file: return "File"; case .clip: return "Clipboard"; case .trash: return "Trash"
        case .emoji: return "Emoji"; case .bookmark: return "Bookmark"; case .event: return "Calendar"
        case .menuItem: return "Menu Item"; case .profile, .saveProfile: return "Profile"
        case .define: return "Dictionary"; case .quicklink: return "Quicklink"
        case .searchFilesFallback: return "Search Files"; case .askAI: return "AI"
        }
    }
}

// MARK: - Raycast ⌘K Action System (Slice 1.2)

enum CommandBarActionKind: String, CaseIterable, Sendable {
    case open
    case revealInFinder
    case quickLook
    case copyPath
    case copyValue
    case copyBundleID
    case uninstallApp
    case deleteAppData
    case moveToTrash
    case pasteDirectly
    case deleteEntry
    case killProcess
    case forceKillProcess
    case runAction
}

struct CommandBarActionItem: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let kind: CommandBarActionKind
    let shortcutHint: String?
    let isDestructive: Bool

    init(id: String = UUID().uuidString, title: String, kind: CommandBarActionKind, shortcutHint: String? = nil, isDestructive: Bool = false) {
        self.id = id
        self.title = title
        self.kind = kind
        self.shortcutHint = shortcutHint
        self.isDestructive = isDestructive
    }
}

enum CommandBarActionResolver {
    static func actions(for result: CommandBarResult) -> [CommandBarActionItem] {
        switch result {
        case .app:
            return [
                CommandBarActionItem(id: "open", title: "Open Application", kind: .open, shortcutHint: "⏎"),
                CommandBarActionItem(id: "reveal", title: "Reveal in Finder", kind: .revealInFinder, shortcutHint: "⌘⏎"),
                CommandBarActionItem(id: "copyPath", title: "Copy Path", kind: .copyPath, shortcutHint: "⌘C"),
                CommandBarActionItem(id: "copyBundleID", title: "Copy Bundle ID", kind: .copyBundleID, shortcutHint: "⌥⌘C"),
                CommandBarActionItem(id: "uninstall", title: "Uninstall Application...", kind: .uninstallApp, shortcutHint: "⌘⌫", isDestructive: true),
                CommandBarActionItem(id: "deleteData", title: "Delete App Data & Leftovers...", kind: .deleteAppData, isDestructive: true)
            ]
        case .file:
            return [
                CommandBarActionItem(id: "open", title: "Open File", kind: .open, shortcutHint: "⏎"),
                CommandBarActionItem(id: "quickLook", title: "Quick Look", kind: .quickLook, shortcutHint: "⌘Y"),
                CommandBarActionItem(id: "reveal", title: "Reveal in Finder", kind: .revealInFinder, shortcutHint: "⌘⏎"),
                CommandBarActionItem(id: "copyPath", title: "Copy File Path", kind: .copyPath, shortcutHint: "⌘C"),
                CommandBarActionItem(id: "trash", title: "Move to Trash", kind: .moveToTrash, shortcutHint: "⌘⌫", isDestructive: true)
            ]
        case .clip:
            return [
                CommandBarActionItem(id: "copy", title: "Copy to Clipboard", kind: .copyValue, shortcutHint: "⏎"),
                CommandBarActionItem(id: "paste", title: "Paste into Active App", kind: .pasteDirectly, shortcutHint: "⌘⏎"),
                CommandBarActionItem(id: "delete", title: "Delete from History", kind: .deleteEntry, shortcutHint: "⌘⌫", isDestructive: true)
            ]
        case .answer(let answer):
            switch answer {
            case .math:
                return [
                    CommandBarActionItem(id: "copy", title: "Copy Result", kind: .copyValue, shortcutHint: "⏎ / ⌘C")
                ]
            case .web:
                return [
                    CommandBarActionItem(id: "open", title: "Search in Browser", kind: .open, shortcutHint: "⏎"),
                    CommandBarActionItem(id: "copy", title: "Copy Query", kind: .copyValue, shortcutHint: "⌘C")
                ]
            }
        case .process:
            return [
                CommandBarActionItem(id: "kill", title: "Terminate Process", kind: .killProcess, shortcutHint: "⏎"),
                CommandBarActionItem(id: "forceKill", title: "Force Kill (SIGKILL)", kind: .forceKillProcess, shortcutHint: "⌘⌫", isDestructive: true)
            ]
        case .action:
            return [
                CommandBarActionItem(id: "run", title: "Execute Action", kind: .runAction, shortcutHint: "⏎")
            ]
        default:
            return [
                CommandBarActionItem(id: "open", title: "Open", kind: .open, shortcutHint: "⏎")
            ]
        }
    }
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
    case wifiPassword = "wifipw"

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

    /// Fuzzy matching for generators by keyword prefix or display name.
    static func matching(_ query: String) -> [CommandGenerator] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return allCases.filter { gen in
            gen.keyword.hasPrefix(q) || gen.displayName.lowercased().contains(q)
        }
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
                      quicklinks: [Quicklink] = [],
                      processes: [ProcessEntry] = [],
                      files: [FileEntry] = [],
                      clips: [ClipEntry] = [],
                      bookmarks: [Bookmark] = [],
                      events: [EventEntry] = [],
                      menuItems: [MenuSearchEntry] = [],
                      profiles: [BarProfileSummary] = [],
                      generate: (CommandGenerator) -> String = { $0.value() }) -> [CommandBarResult] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return apps.filter { (usage[$0.bundleID]?.launches ?? 0) > 0 }
                .sorted { a, b in
                    let left = usage[a.bundleID]!, right = usage[b.bundleID]!
                    if left.launches != right.launches { return left.launches > right.launches }
                    if left.lastLaunched != right.lastLaunched { return left.lastLaunched > right.lastLaunched }
                    return LauncherAppIndex.nameOrder(a, b)
                }.prefix(8).map(CommandBarResult.app)
        }
        let keyword = CommandKeyword.parse(query)
        if case .mode(let mode, let argument)? = keyword {
            return modeRows(mode, argument, apps: apps, usage: usage, running: running, processes: processes, files: files, clips: clips, bookmarks: bookmarks, events: events, menuItems: menuItems, profiles: profiles)
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
            var rows = appRows(term, apps: apps, usage: usage, running: running, custom: custom, quicklinks: quicklinks, generate: generate)
            if case .macro(let macro)? = keyword { rows.insert(.action(macro), at: 0) }

            // Guarded inline math check (e.g. 24 * 7, 100 / 4)
            if let math = LauncherAnswers.inlineMathAnswer(for: term) {
                rows.insert(.answer(math), at: 0)
            }

            // Fallback rows when query produces no direct results (requires letters/digits, excluding lone command prefixes)
            let isSinglePrefix = term.count == 1 && ["=", "@", "/", ">", ":", "!"].contains(term)
            if rows.isEmpty && !isSinglePrefix && term.contains(where: { $0.isLetter || $0.isNumber }) {
                rows.append(.answer(.web(query: term)))
                rows.append(.searchFilesFallback(term))
                rows.append(.askAI(term))
            }
            return rows
        }
    }

    /// Answers / generator → custom / quicklinks → app matches, with a running app's Quit row immediately after it
    /// (Phase 29a), then any leftover running match.
    private static func appRows(_ term: String, apps: [LauncherApp], usage: [String: LauncherUsage],
                                running: [RunningAppRef], custom: [CustomCommand],
                                quicklinks: [Quicklink] = [],
                                generate: (CommandGenerator) -> String) -> [CommandBarResult] {
        guard !term.isEmpty else { return [] }
        var out: [CommandBarResult] = []
        if let generator = CommandGenerator.match(term) {
            let value = generate(generator)
            if !value.isEmpty { out.append(.generator(generator, value: value)) }
        }
        out += CustomCommand.matching(term, in: custom).map(CommandBarResult.custom)
        out += QuicklinkTemplate.matching(term, in: quicklinks).map { .quicklink($0.quicklink, argument: $0.argument) }

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
    /// `profile <text>` lists profiles whose name contains the text; `profile save <name>` offers to store
    /// the bar under that name (replacing a profile of the same name).
    static func profileRows(_ argument: String, _ profiles: [BarProfileSummary]) -> [CommandBarResult] {
        let trimmed = argument.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        if lower == "save" || lower.hasPrefix("save ") {
            let name = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? [] : [.saveProfile(name)]
        }
        return profiles
            .filter { lower.isEmpty || $0.name.lowercased().contains(lower) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map(CommandBarResult.profile)
    }

    private static func modeRows(_ mode: CommandBarMode, _ argument: String, apps: [LauncherApp],
                                 usage: [String: LauncherUsage], running: [RunningAppRef],
                                 processes: [ProcessEntry], files: [FileEntry], clips: [ClipEntry],
                                 bookmarks: [Bookmark], events: [EventEntry],
                                 menuItems: [MenuSearchEntry], profiles: [BarProfileSummary]) -> [CommandBarResult] {
        switch mode {
        case .file, .image:
            return files.map(CommandBarResult.file)
        case .bookmark:
            return BookmarkImport.matching(argument, in: bookmarks).prefix(30).map(CommandBarResult.bookmark)
        case .event:
            return events.map(CommandBarResult.event)
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
        case .menu:
            return MenuSearch.rank(argument, in: menuItems).map(CommandBarResult.menuItem)
        case .profile:
            return profileRows(argument, profiles)
        case .define:
            return argument.isEmpty ? [] : [.define(argument)]
        case .brewSearch:
            return argument.isEmpty ? [] : [.script("brew search \(argument)")]
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
