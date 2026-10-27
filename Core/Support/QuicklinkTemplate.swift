import Foundation

/// A user-defined link with placeholders, e.g. `https://github.com/search?q={query}`.
/// Pure expansion only: callers supply the values, nothing here reads the pasteboard or the screen.
struct Quicklink: Codable, Equatable, Sendable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var template: String
    /// Bundle id of the app to open the result with. `nil` means the default handler.
    var openWith: String?
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
}
