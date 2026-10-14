import Foundation

/// Phase 30g: a browser bookmark (title + URL). Pure import from Chrome's JSON and Safari's plist.
struct Bookmark: Equatable, Sendable {
    var title: String
    var url: String
}

enum BookmarkImport {
    /// Chrome/Edge `Bookmarks` JSON: `roots.*.children[]`, leaves carry `name` + `url`.
    static func parseChrome(_ data: Data) -> [Bookmark] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let roots = root["roots"] as? [String: Any] else { return [] }
        var out: [Bookmark] = []
        func walk(_ node: [String: Any]) {
            if let children = node["children"] as? [[String: Any]] {
                children.forEach(walk)
            } else if let url = node["url"] as? String, let name = node["name"] as? String, !url.isEmpty {
                out.append(Bookmark(title: name.isEmpty ? url : name, url: url))
            }
        }
        for value in roots.values { if let dict = value as? [String: Any] { walk(dict) } }
        return out
    }

    /// Safari `Bookmarks.plist`: nested `Children` arrays; leaves carry `URLString` + `URIDictionary.title`.
    static func parseSafari(_ plist: Any) -> [Bookmark] {
        var out: [Bookmark] = []
        func walk(_ node: Any) {
            guard let dict = node as? [String: Any] else { return }
            if let url = dict["URLString"] as? String, !url.isEmpty {
                let title = (dict["URIDictionary"] as? [String: Any])?["title"] as? String ?? url
                out.append(Bookmark(title: title, url: url))
            }
            (dict["Children"] as? [Any])?.forEach(walk)
        }
        walk(plist)
        return out
    }

    /// Entries whose title or URL contains every whitespace-separated token of `query`.
    static func matching(_ query: String, in bookmarks: [Bookmark]) -> [Bookmark] {
        let tokens = query.lowercased().split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard !tokens.isEmpty else { return bookmarks }
        return bookmarks.filter { bookmark in
            let hay = (bookmark.title + " " + bookmark.url).lowercased()
            return tokens.allSatisfy { hay.contains($0) }
        }
    }
}
