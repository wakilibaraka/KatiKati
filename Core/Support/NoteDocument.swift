import Foundation

/// On-disk form of a note in the sync folder: Markdown with a small front-matter header.
/// Pure string work (no file system), so the format is fully test-covered. Identity lives in the
/// header, never the filename, so renaming a file from a phone never duplicates a note.
enum NoteDocument {
    static let fence = "---"

    /// File-format keys — never localized, never renamed.
    enum Key {
        static let id = "katikati-id"
        static let created = "created"
        static let modified = "modified"
        static let archived = "archived"
        static let pinned = "pinned"
        static let order = "order"
        static let color = "color"
        static let title = "title"
    }

    private static func stamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    private static func date(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text).map(Note.wholeSeconds)
    }

    static func render(_ note: Note) -> String {
        var header = [
            "\(Key.id): \(note.id)",
            "\(Key.created): \(stamp(note.created))",
            "\(Key.modified): \(stamp(note.modified))",
            "\(Key.archived): \(note.archived)",
            "\(Key.pinned): \(note.pinned)",
            "\(Key.order): \(note.order)",
            "\(Key.color): \(note.color)",
        ]
        if note.hasCustomTitle { header.append("\(Key.title): \(singleLine(note.title))") }
        return fence + "\n" + header.joined(separator: "\n") + "\n" + fence + "\n\n" + note.body
    }

    private static func singleLine(_ s: String) -> String {
        s.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    struct Parsed: Equatable {
        var note: Note
        /// False when the file had no `katikati-id` (written from scratch elsewhere): the caller
        /// assigns the fresh id already on `note` and writes the file back.
        var hasIdentity: Bool
        /// True when the header declared a `modified` stamp (otherwise `note.modified` is a fallback).
        var hasDeclaredModified: Bool
    }

    /// `fallbackTitle` (usually the file name sans extension) is used only when the file has no
    /// header title; `fallbackDate` stands in for missing timestamps (the file's own mtime).
    static func parse(_ text: String, fallbackTitle: String, fallbackDate: Date) -> Parsed {
        var note = Note(title: "", body: text, created: fallbackDate, modified: fallbackDate)
        var hasIdentity = false
        var hasModified = false
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        if lines.first == fence, let close = lines.dropFirst().firstIndex(of: fence) {
            for line in lines[1..<close] {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                switch key {
                case Key.id where !value.isEmpty: note.id = value; hasIdentity = true
                case Key.created: if let d = date(value) { note.created = d }
                case Key.modified: if let d = date(value) { note.modified = d; hasModified = true }
                case Key.archived: note.archived = value == "true"
                case Key.pinned: note.pinned = value == "true"
                case Key.order: note.order = Int(value) ?? 0
                case Key.color: note.color = Int(value) ?? 0
                case Key.title: note.title = value
                default: break
                }
            }
            var body = Array(lines[(close + 1)...])
            if body.first == "" { body.removeFirst() }     // the blank line render() writes after the fence
            note.body = body.joined(separator: "\n")
        }
        if !note.hasCustomTitle, note.displayTitle.isEmpty { note.title = fallbackTitle }
        return Parsed(note: note, hasIdentity: hasIdentity, hasDeclaredModified: hasModified)
    }
}
