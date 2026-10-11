import Foundation

/// A note on the right-edge notes bar (Phase 7A-6). Pure value type; persistence lives elsewhere.
struct Note: Equatable, Identifiable, Sendable, Codable {
    var id: String
    /// Empty = derive from the first body line (never frozen into the file).
    var title: String
    var body: String
    var created: Date
    var modified: Date
    var pinned: Bool
    var archived: Bool
    /// Manual sort position among notes (lower first).
    var order: Int
    /// Palette index (`NotePalette`), wraps; 0 for notes that predate colours or come from foreign files.
    var color: Int

    init(id: String = UUID().uuidString, title: String = "", body: String = "",
         created: Date = Date(), modified: Date? = nil,
         pinned: Bool = false, archived: Bool = false, order: Int = 0, color: Int = 0) {
        self.id = id
        self.title = title
        self.body = body
        self.created = Note.wholeSeconds(created)
        self.modified = Note.wholeSeconds(modified ?? created)
        self.pinned = pinned
        self.archived = archived
        self.order = order
        self.color = color
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, body, created, modified, pinned, archived, order, color
    }

    /// Tolerant decoder: notes saved before `color` existed decode with colour 0.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        body = try c.decode(String.self, forKey: .body)
        created = try c.decode(Date.self, forKey: .created)
        modified = try c.decode(Date.self, forKey: .modified)
        pinned = try c.decode(Bool.self, forKey: .pinned)
        archived = try c.decode(Bool.self, forKey: .archived)
        order = try c.decode(Int.self, forKey: .order)
        color = try c.decodeIfPresent(Int.self, forKey: .color) ?? 0
    }

    /// Documents carry ISO-8601 timestamps with one-second resolution; all comparisons use that grain.
    static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    var hasCustomTitle: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Custom title, else the first non-empty body line, else empty.
    var displayTitle: String {
        if hasCustomTitle { return title }
        return body.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
    }
}

extension Array where Element == Note {
    /// List order for the notes bar: pinned first, then manual order, then oldest first.
    func inListOrder() -> [Note] {
        sorted { ($0.pinned ? 0 : 1, $0.order, $0.created, $0.id) < ($1.pinned ? 0 : 1, $1.order, $1.created, $1.id) }
    }
}

/// Reordering for the notes deck (Phase 7A-D1): pure so the drag rules are unit-tested.
enum NoteOrdering {
    /// Moves `id` by `slots` positions within `notes` (already in list order) and returns only the
    /// notes whose `order` changed, with orders rewritten densely (0, 1, 2…) so repeated drags cannot
    /// drift the values apart. Out-of-range moves clamp; no-ops return [].
    static func reorder(_ notes: [Note], id: String, by slots: Int) -> [Note] {
        guard slots != 0, let from = notes.firstIndex(where: { $0.id == id }) else { return [] }
        let to = min(max(0, from + slots), notes.count - 1)
        guard to != from else { return [] }
        var list = notes
        let moved = list.remove(at: from)
        list.insert(moved, at: to)
        var changed: [Note] = []
        for (rank, var n) in list.enumerated() where n.order != rank {
            n.order = rank
            changed.append(n)
        }
        return changed
    }
}
