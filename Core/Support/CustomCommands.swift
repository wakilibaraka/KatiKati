import Foundation

/// Phase 28c: user-defined command-bar entries — a name plus a target. A target that looks like a URL is
/// a link (opened); anything else is a script run through `LauncherRunner`. Stored as one entry per line:
/// `Name = target`. Pure parsing/serialization.
struct CustomCommand: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable { case link, command, snippet }

    static let key = "com.katikati.commandbar.custom"
    /// Phase 36g: text snippets, stored as `trigger = text` lines (`\n` in the text is a line break).
    static let snippetsKey = "com.katikati.commandbar.snippets"

    var name: String
    var target: String
    var kind: Kind

    var id: String { name.lowercased() }

    static func parse(_ raw: String) -> [CustomCommand] {
        raw.split(whereSeparator: \.isNewline).compactMap { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard let equals = text.firstIndex(of: "=") else { return nil }
            let name = text[..<equals].trimmingCharacters(in: .whitespaces)
            let target = text[text.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !target.isEmpty else { return nil }
            return CustomCommand(name: name, target: target, kind: kind(of: target))
        }
    }

    static func serialize(_ commands: [CustomCommand]) -> String {
        commands.map { "\($0.name) = \($0.target)" }.joined(separator: "\n")
    }

    static func kind(of target: String) -> Kind {
        let lower = target.lowercased()
        return (lower.hasPrefix("http://") || lower.hasPrefix("https://")) ? .link : .command
    }

    /// The entries whose name the query is a case-insensitive prefix of.
    static func matching(_ query: String, in commands: [CustomCommand]) -> [CustomCommand] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return commands.filter { $0.name.lowercased().hasPrefix(q) }
    }
}

extension CustomCommand {
    /// Phase 36g: parse snippet lines into `.snippet` entries whose `target` is the expansion. The expansion
    /// is only ever copied/pasted, never run — so a snippet can hold any text, including shell-looking text.
    static func parseSnippets(_ raw: String) -> [CustomCommand] {
        parse(raw).map { CustomCommand(name: $0.name, target: $0.target.replacingOccurrences(of: "\\n", with: "\n"), kind: .snippet) }
    }
}
