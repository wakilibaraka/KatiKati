import Foundation

/// Phase 30k: a flat in-memory filename index (oil-find/Cling style) so `f ` is instant without
/// Spotlight. Pure: names are folded once; search narrows by "contains every term".
struct FileIndex: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        var path: String
        var name: String
        var isDirectory: Bool
    }

    private(set) var entries: [Entry] = []
    private var folded: [String] = []

    var count: Int { entries.count }

    mutating func rebuild(_ newEntries: [Entry]) {
        entries = newEntries
        folded = newEntries.map { $0.name.lowercased() }
    }

    /// Entries whose name contains every term (case-insensitive), capped at `limit`.
    func search(_ terms: [String], limit: Int = 40) -> [Entry] {
        let needles = terms.map { $0.lowercased() }.filter { !$0.isEmpty }
        guard !needles.isEmpty else { return [] }
        var out: [Entry] = []
        for (i, name) in folded.enumerated() where needles.allSatisfy({ name.contains($0) }) {
            out.append(entries[i])
            if out.count >= limit { break }
        }
        return out
    }

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp", "svg"]
}
