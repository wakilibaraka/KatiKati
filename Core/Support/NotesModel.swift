import Foundation

/// A note on the right-edge notes bar (Phase 7A-6). Pure value type; persistence lives elsewhere.
struct Note: Equatable, Identifiable, Sendable {
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

    init(id: String = UUID().uuidString, title: String = "", body: String = "",
         created: Date = Date(), modified: Date? = nil,
         pinned: Bool = false, archived: Bool = false, order: Int = 0) {
        self.id = id
        self.title = title
        self.body = body
        self.created = Note.wholeSeconds(created)
        self.modified = Note.wholeSeconds(modified ?? created)
        self.pinned = pinned
        self.archived = archived
        self.order = order
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
