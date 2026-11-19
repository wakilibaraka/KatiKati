import Foundation

struct DesktopCaptureEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var text: String
    var created: Date

    init(id: UUID = UUID(), text: String, created: Date = Date()) {
        self.id = id
        self.text = text
        self.created = created
    }
}

/// Newest-first inbox behind the Desktop Quick Capture widget. Pure value type; persistence lives in `DesktopQuickCaptureStore`.
struct DesktopCaptureLog: Codable, Equatable, Sendable {
    static let capacity = 200
    static let maxEntryLength = 4000

    var entries: [DesktopCaptureEntry] = []

    init(entries: [DesktopCaptureEntry] = []) { self.entries = entries }

    private enum CodingKeys: String, CodingKey { case entries }

    init(from decoder: Decoder) throws {
        entries = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent([DesktopCaptureEntry].self, forKey: .entries) ?? []
    }

    /// Blank text is a no-op; long text is clamped; the oldest entries fall off past `capacity`.
    @discardableResult
    mutating func add(_ text: String, now: Date = Date()) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let entry = DesktopCaptureEntry(text: String(trimmed.prefix(Self.maxEntryLength)), created: now)
        entries.insert(entry, at: 0)
        if entries.count > Self.capacity { entries.removeLast(entries.count - Self.capacity) }
        return entry.id
    }

    mutating func delete(_ id: UUID) { entries.removeAll { $0.id == id } }
}
