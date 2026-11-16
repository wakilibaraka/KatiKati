import Foundation

/// A user-defined link with placeholders, e.g. `https://github.com/search?q={query}`.
/// Pure expansion only: callers supply the values, nothing here reads the pasteboard or the screen.
struct Quicklink: Codable, Equatable, Sendable, Identifiable {
    struct Match: Equatable, Sendable {
        var quicklink: Quicklink
        var argument: String
    }

    static let key = "com.katikati.commandbar.quicklinks"

    var id: UUID = UUID()
    var name: String
    var template: String
    /// Bundle id of the app to open the result with. `nil` means the default handler.
    var openWith: String?

    /// Parses `Name = template` lines (same editor syntax as `CustomCommand`), or a JSON `[Quicklink]` array.
    static func parse(_ raw: String) -> [Quicklink] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.hasPrefix("["), let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([Quicklink].self, from: data) {
            return decoded
        }
        return raw.split(whereSeparator: \.isNewline).compactMap { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard let equals = text.firstIndex(of: "=") else { return nil }
            let name = text[..<equals].trimmingCharacters(in: .whitespaces)
            let template = text[text.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !template.isEmpty else { return nil }
            return Quicklink(name: name, template: template)
        }
    }

    static func serialize(_ links: [Quicklink]) -> String {
        links.map { "\($0.name) = \($0.template)" }.joined(separator: "\n")
    }
}

struct QuicklinkValues: Equatable, Sendable {
    var query: String = ""
    var clipboard: String = ""
    var selection: String = ""
    var date: Date = Date()
}

enum QuicklinkTemplate {
    static let tokens = ["query", "clipboard", "selection", "date"]

    /// True when `template` uses at least one known token.
    static func hasPlaceholder(_ template: String) -> Bool {
        tokens.contains { template.contains("{\($0)}") }
    }

    /// Whether the link needs the typed argument (so the bar knows to wait for one).
    static func needsQuery(_ template: String) -> Bool { template.contains("{query}") }

    /// Replaces each known token. Values are percent-encoded for URL templates (those with a
    /// scheme) and inserted verbatim for anything else, such as a file path or a shell-free app argument.
    static func expand(_ template: String, values: QuicklinkValues, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let isURL = template.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) != nil
        func encode(_ text: String) -> String {
            guard isURL else { return text }
            var allowed = CharacterSet.urlQueryAllowed
            allowed.remove(charactersIn: "&+=#?/:@!$'()*,;")
            return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
        }
        let formatter = calendar.dateComponents([.year, .month, .day], from: values.date)
        let day = String(format: "%04d-%02d-%02d", formatter.year ?? 0, formatter.month ?? 0, formatter.day ?? 0)
        return template
            .replacingOccurrences(of: "{query}", with: encode(values.query))
            .replacingOccurrences(of: "{clipboard}", with: encode(values.clipboard))
            .replacingOccurrences(of: "{selection}", with: encode(values.selection))
            .replacingOccurrences(of: "{date}", with: day)
    }

    /// A URL for the expanded text, or nil when it does not parse as one.
    static func url(_ template: String, values: QuicklinkValues, calendar: Calendar = Calendar(identifier: .gregorian)) -> URL? {
        URL(string: expand(template, values: values, calendar: calendar))
    }

    /// Matches quicklinks against a command-bar query:
    /// - `<name> <argument>` matches a quicklink whose name equals `<name>` (case-insensitive) and uses `{query}`, passing `<argument>`.
    /// - Otherwise, matches quicklinks whose name has `query` as a case-insensitive prefix (with an empty argument).
    static func matching(_ query: String, in links: [Quicklink]) -> [Quicklink.Match] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let lower = trimmed.lowercased()
        var out: [Quicklink.Match] = []
        if let space = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) {
            let head = String(trimmed[..<space]).lowercased()
            let arg = String(trimmed[trimmed.index(after: space)...]).trimmingCharacters(in: .whitespaces)
            for link in links where link.name.lowercased() == head && needsQuery(link.template) {
                out.append(Quicklink.Match(quicklink: link, argument: arg))
            }
        }
        for link in links where link.name.lowercased().hasPrefix(lower) {
            if !out.contains(where: { $0.quicklink.id == link.id }) {
                out.append(Quicklink.Match(quicklink: link, argument: ""))
            }
        }
        return out
    }
}
