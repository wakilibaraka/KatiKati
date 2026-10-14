import Foundation

/// Phase 21a: pure interpretation of a raw launcher string into a routing decision. No AppKit, no side
/// effects — the launcher grid (21b), the script runner (21c) and Settings all consume the result.
///
/// Grammar (HYBRID_PLAN §Phase 21): `>` script, `= math`, `@ web search`, `/ path`, `:` Shortcut,
/// anything else is a fuzzy app search. The prefix characters live in `LauncherCommandPrefixes` so a
/// Settings surface can swap them without touching the parser (owner 2026-10-14: "user can modify in
/// settings").

/// The prefix characters that route a query. Defaults match the plan; `~` is deliberately avoided for
/// Shortcuts because a home-relative path (`~/Docs`) starts with it.
struct LauncherCommandPrefixes: Equatable, Sendable {
    var script: Character = ">"
    var math: Character = "="
    var web: Character = "@"
    var path: Character = "/"
    var shortcut: Character = ":"
    var process: Character = "!"

    static let `default` = LauncherCommandPrefixes()
}

/// What the launcher should do with a query (Phase 21a). The payload is what the route acts on.
enum LauncherQuery: Equatable, Sendable {
    /// Fuzzy app search (the shipped 7B behavior); payload is the whole trimmed query.
    case apps(String)
    /// Arithmetic expression; evaluated by `CalculatorEngine` in 21b.
    case math(String)
    /// Web search terms; turned into a URL by `LauncherQuickAction` when submitted.
    case web(String)
    /// A filesystem path (absolute or `~`-relative) to open/reveal.
    case path(String)
    /// A shell / AppleScript payload for the runner (21c).
    case script(String)
    /// A Shortcuts.app shortcut name for the runner (21c).
    case shortcut(String)
    /// A process-name filter for the process killer (28e): `!safari`.
    case process(String)

    /// The text after the prefix, trimmed (for `.apps`, the whole trimmed query).
    var payload: String {
        switch self {
        case .apps(let s), .math(let s), .web(let s), .path(let s), .script(let s), .shortcut(let s), .process(let s):
            return s
        }
    }
}

enum LauncherCommandParser {
    /// Routes `raw` by its first non-whitespace character.
    ///
    /// Tolerant by design:
    /// - an empty or whitespace-only query → `.apps("")` (the empty search);
    /// - a bare prefix (`=`, `@`, …) or a prefix followed only by whitespace → `.apps` with the trimmed
    ///   original, so a stray prefix can never hijack the search;
    /// - an unrecognised first character → `.apps` with the trimmed original.
    ///
    /// The payload is trimmed; for `.path` it is made absolute (a leading `/` is restored), because the
    /// route marker and the path separator are the same character. Math stays verbatim for `CalculatorEngine`.
    static func parse(_ raw: String, prefixes: LauncherCommandPrefixes = .default) -> LauncherQuery {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return .apps("") }
        let payload = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return .apps(trimmed) }
        if first == prefixes.script { return .script(payload) }
        if first == prefixes.math { return .math(payload) }
        if first == prefixes.web { return .web(payload) }
        if first == prefixes.path { return .path(payload.hasPrefix("/") ? payload : "/" + payload) }
        if first == prefixes.shortcut { return .shortcut(payload) }
        if first == prefixes.process { return .process(payload) }
        return .apps(trimmed)
    }
}

/// Phase 21a: a conservative, purely advisory read of a script payload. The runner (21c) still confirms
/// before running; this only decides whether to warn. A missed destructive command is possible by design —
/// the confirm step, not this classifier, is the guarantee.
enum LauncherScriptSafety {
    enum Verdict: Equatable, Sendable { case benign, destructive }

    /// Command words that can destroy data or machine state. Matched against the first word of every
    /// `;` / `|` / `&` / newline-separated segment.
    private static let destructiveCommands: Set<String> = [
        "rm", "rmdir", "shred", "srm", "mkfs", "dd", "diskutil", "fdisk", "gpt", "truncate",
        "shutdown", "reboot", "halt", "nvram", "csrutil", "spctl", "launchctl",
        "kill", "killall", "pkill", "chmod", "chown", "defaults",
        "sudo", "su", "doas",
    ]

    static func classify(_ script: String) -> Verdict {
        let lowered = script.lowercased()
        // Patterns no word-split catches: fork bomb, output redirection, piping into a shell, and the
        // AppleScript shell escape.
        for marker in [":(){", "> /", ">/", "|sh", "| sh", "|bash", "| bash", "do shell script"] {
            if lowered.contains(marker) { return .destructive }
        }
        for segment in lowered.split(whereSeparator: { ";|\n&".contains($0) }) {
            guard let word = segment.split(whereSeparator: { $0 == " " || $0 == "\t" }).first else { continue }
            if destructiveCommands.contains(normalise(word)) { return .destructive }
        }
        return .benign
    }

    /// `/bin/mkfs.ext4` → `mkfs`: drop any directory and the sub-command suffix so the base name matches.
    private static func normalise(_ word: Substring) -> String {
        let base = word.split(separator: "/").last.map(String.init) ?? String(word)
        return base.split(separator: ".").first.map(String.init) ?? base
    }
}
