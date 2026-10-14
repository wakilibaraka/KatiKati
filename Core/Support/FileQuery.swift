import Foundation

/// Phase 29g: one filesystem result. Pure value; the app layer fills it from `mdfind`.
struct FileEntry: Equatable, Sendable {
    var path: String
    var name: String
}

/// Phase 29g: the parsed `f `/`img ` query. Borrows oil-find's syntax (`ext:`/`kind:`/`in:`/`!`) and
/// Cling's type filters; builds a Spotlight (`mdfind`) predicate. Pure and unit-tested.
struct FileQuery: Equatable, Sendable {
    var terms: [String] = []
    var excluded: [String] = []
    var extensions: [String] = []
    var kinds: [String] = []
    var path: String?
    var imageOnly: Bool = false

    var isValid: Bool { !terms.isEmpty || !extensions.isEmpty || !kinds.isEmpty || imageOnly }

    static func parse(_ raw: String, imageOnly: Bool = false) -> FileQuery {
        var query = FileQuery(imageOnly: imageOnly)
        for token in raw.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
            let text = String(token)
            if text.isEmpty { continue }
            if text.hasPrefix("!") {
                let value = String(text.dropFirst()).lowercased()
                if !value.isEmpty { query.excluded.append(value) }
            } else if let value = value(text, prefix: "in:") {
                query.path = (value as NSString).expandingTildeInPath
            } else if let value = value(text, prefix: "ext:") {
                query.extensions += value.lowercased().split(separator: ";").map(String.init)
            } else if let value = value(text, prefix: "kind:") {
                query.kinds += value.lowercased().split(separator: ";").map(String.init)
            } else if text.hasPrefix("*.") {
                query.extensions.append(text.dropFirst(2).lowercased())
            } else if text.hasPrefix(".") {
                query.extensions.append(text.dropFirst().lowercased())
            } else {
                query.terms.append(text.lowercased())
            }
        }
        return query
    }

    /// A `mdfind` query string (empty when there is nothing to search).
    func predicate() -> String {
        var clauses: [String] = []
        for term in terms { clauses.append("kMDItemFSName == \"*\(term)*\"cd") }
        for ext in extensions where !ext.isEmpty { clauses.append("kMDItemFSName == \"*.\(ext)\"cd") }
        for kind in kinds { if let type = Self.contentType(kind) { clauses.append("kMDItemContentTypeTree == \"\(type)\"") } }
        if imageOnly { clauses.append("kMDItemContentTypeTree == \"public.image\"") }
        for ex in excluded { clauses.append("!(kMDItemFSName == \"*\(ex)*\"cd)") }
        return clauses.isEmpty ? "" : clauses.joined(separator: " && ")
    }

    static func contentType(_ kind: String) -> String? {
        switch kind {
        case "image": return "public.image"
        case "video", "movie": return "public.movie"
        case "audio", "music": return "public.audio"
        case "doc", "document", "text": return "public.text"
        case "code", "source": return "public.source-code"
        case "archive", "zip": return "public.archive"
        case "folder", "dir": return "public.folder"
        case "app", "application": return "com.apple.application-bundle"
        default: return nil
        }
    }

    private static func value(_ token: String, prefix: String) -> String? {
        guard token.lowercased().hasPrefix(prefix) else { return nil }
        return String(token.dropFirst(prefix.count))
    }
}
