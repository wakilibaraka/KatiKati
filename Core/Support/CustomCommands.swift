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
    /// Phase 36g + Slice CS-1: parse snippet lines (or JSON `[TextSnippetItem]`) into `.snippet`
    /// entries whose `target` is the expansion. Only enabled items are returned.
    static func parseSnippets(_ raw: String) -> [CustomCommand] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("["), let data = trimmed.data(using: .utf8),
           let items = try? JSONDecoder().decode([TextSnippetItem].self, from: data) {
            return items.filter(\.isEnabled).map {
                CustomCommand(name: $0.trigger, target: $0.content, kind: .snippet)
            }
        }
        return parse(raw).map {
            CustomCommand(name: $0.name, target: $0.target.replacingOccurrences(of: "\\n", with: "\n"), kind: .snippet)
        }
    }
}

/// Slice CS-1: structured text snippet with lossless JSON storage and legacy migration.
struct TextSnippetItem: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var trigger: String
    var content: String
    var isEnabled: Bool
    var requireDelimiter: Bool

    init(
        id: UUID = UUID(),
        trigger: String,
        content: String,
        isEnabled: Bool = true,
        requireDelimiter: Bool = true
    ) {
        self.id = id
        self.trigger = trigger
        self.content = content
        self.isEnabled = isEnabled
        self.requireDelimiter = requireDelimiter
    }
}

enum TextSnippetStore {
    static let excludedAppsKey = "com.katikati.snippets.excludedApps"

    static func parse(_ raw: String) -> [TextSnippetItem] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("["), let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([TextSnippetItem].self, from: data) {
            return decoded
        }
        return CustomCommand.parse(raw).map {
            TextSnippetItem(
                trigger: $0.name,
                content: $0.target.replacingOccurrences(of: "\\n", with: "\n"),
                isEnabled: true,
                requireDelimiter: true
            )
        }
    }

    static func serialize(_ items: [TextSnippetItem]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(items),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    static func parseExcludedApps(_ raw: String) -> Set<String> {
        Set(raw.split { $0 == "," || $0.isWhitespace }.map(String.init).filter { !$0.isEmpty })
    }
}

/// Slice CS-1: expands `{clipboard}`, `{date}`, `{time}`, and `{cursor}` in snippet bodies.
enum SnippetVariableExpander {
    struct Result: Equatable, Sendable {
        var text: String
        var cursorLeftArrows: Int
    }

    static func expand(
        _ template: String,
        clipboard: String = "",
        now: Date = Date(),
        locale: Locale = .current
    ) -> Result {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        var expanded = template
            .replacingOccurrences(of: "{clipboard}", with: clipboard)
            .replacingOccurrences(of: "{date}", with: dateFormatter.string(from: now))
            .replacingOccurrences(of: "{time}", with: timeFormatter.string(from: now))

        guard let range = expanded.range(of: "{cursor}") else {
            return Result(text: expanded, cursorLeftArrows: 0)
        }
        let prefixCount = expanded[..<range.lowerBound].count
        expanded = expanded.replacingOccurrences(of: "{cursor}", with: "")
        let leftArrows = max(0, expanded.count - prefixCount)
        return Result(text: expanded, cursorLeftArrows: leftArrows)
    }
}

/// 53c + CS-1: system-wide snippet expansion over the typed buffer.
struct SnippetExpander: Equatable, Sendable {
    struct Expansion: Equatable, Sendable {
        /// What to paste: the expansion (plus the delimiter when `swallowedDelimiter` is true).
        var replacement: String
        /// How many characters of the typed trigger the service must delete first.
        var triggerCount: Int
        /// Whether the delimiter character was swallowed by the expander.
        var swallowedDelimiter: Bool = true
        /// How many left-arrow presses to emit after pasting to reach `{cursor}`.
        var cursorLeftArrows: Int = 0

        init(
            replacement: String,
            triggerCount: Int,
            swallowedDelimiter: Bool = true,
            cursorLeftArrows: Int = 0
        ) {
            self.replacement = replacement
            self.triggerCount = triggerCount
            self.swallowedDelimiter = swallowedDelimiter
            self.cursorLeftArrows = cursorLeftArrows
        }
    }

    static let maxWord = 40

    /// Triggers are single words: a name with whitespace could never match the buffer.
    static func triggers(from commands: [CustomCommand]) -> [String: String] {
        var map: [String: String] = [:]
        for command in commands where !command.name.contains(where: \.isWhitespace) {
            map[command.name] = command.target
        }
        return map
    }

    /// Password managers and Keychain: never expand there, even outside a secure field.
    static let ignoredApps: Set<String> = ["com.1password.1password", "com.agilebits.onepassword7",
                                          "com.bitwarden.desktop", "com.apple.keychainaccess"]
    static func isIgnored(bundleID: String?, extraExcluded: Set<String> = []) -> Bool {
        guard let bundleID else { return false }
        return ignoredApps.contains(bundleID) || extraExcluded.contains(bundleID)
    }

    private(set) var word = ""
    private var triggers: [String: String] = [:]
    private var immediateTriggers: [String: String] = [:]

    mutating func setTriggers(_ triggers: [String: String]) {
        self.triggers = triggers
        self.immediateTriggers = [:]
        word = ""
    }

    mutating func setSnippets(_ items: [TextSnippetItem]) {
        var delim: [String: String] = [:]
        var immediate: [String: String] = [:]
        for item in items where item.isEnabled && !item.trigger.contains(where: \.isWhitespace) && item.trigger.count >= 2 {
            if item.requireDelimiter {
                delim[item.trigger] = item.content
            } else {
                immediate[item.trigger] = item.content
            }
        }
        self.triggers = delim
        self.immediateTriggers = immediate
        word = ""
    }

    /// Feeds one typed character (never a shortcut's keycap). Returns an expansion when a trigger
    /// matches; when `swallowedDelimiter` is true, the caller must swallow that delimiter character.
    mutating func feed(_ text: String) -> Expansion? {
        guard text.count == 1, let char = text.first else { return nil }
        if char == " " || char == "\n" || char == "\t" {
            let trigger = word
            word = ""
            guard trigger.count >= 2, let expansion = triggers[trigger] else { return nil }
            return Expansion(replacement: expansion + String(char), triggerCount: trigger.count, swallowedDelimiter: true)
        }
        word.append(char)
        if word.count > Self.maxWord { word.removeFirst() }
        if let expansion = immediateTriggers[word] {
            let count = word.count
            word = ""
            return Expansion(replacement: expansion, triggerCount: count, swallowedDelimiter: false)
        }
        return nil
    }

    mutating func backspace() { if !word.isEmpty { word.removeLast() } }

    mutating func reset() { word = "" }
}
