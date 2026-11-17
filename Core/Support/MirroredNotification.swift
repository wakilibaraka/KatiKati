import Foundation

// Phase 47c — mirrored notifications, the pure half: the value the notch's notifications page shows, the
// Notification Center database record it can be read back from, and the fold that turns a live banner's
// accessibility strings into a title and a body.
//
// Foundation-only and dual-compiled, so the field names Apple's store uses and the banner heuristic are
// unit-tested against synthesised input instead of against the owner's own notifications.

/// One notification as the page shows it, whatever source it came from.
struct MirroredNotification: Equatable, Sendable, Identifiable {
    let id: String
    /// Known for a history record (its `app` row) and for a banner only when the caller could resolve one.
    let bundleIdentifier: String?
    let title: String
    let subtitle: String?
    let body: String?
    let date: Date?

    /// The second line a row shows: the body, else the subtitle.
    var detail: String? { body ?? subtitle }
}

enum NotificationRecord {
    /// The store's per-notification `data` BLOB, already decoded: `req.titl` / `req.subt` / `req.body` plus
    /// the record's own `uuid` and `date`. `nil` for a record with no title — a row with nothing to show is
    /// not a row, and the mirror never invents one.
    static func notification(fromRecord record: [String: Any],
                             bundleIdentifier: String?,
                             date fallback: Date? = nil) -> MirroredNotification? {
        guard let request = record["req"] as? [String: Any], let title = text(request["titl"]) else { return nil }
        let id = (record["uuid"] as? Data).map { $0.map { String(format: "%02x", $0) }.joined() }
            ?? text(request["iden"]) ?? title
        return MirroredNotification(
            id: id,
            bundleIdentifier: bundleIdentifier ?? text(record["app"]),
            title: title,
            subtitle: text(request["subt"]),
            body: text(request["body"]),
            date: unixDate(record["date"]) ?? fallback
        )
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func unixDate(_ value: Any?) -> Date? {
        guard let seconds = (value as? NSNumber)?.doubleValue, seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

/// The banner heuristic, kept apart from the observer so it is testable: a live banner is read out of the
/// accessibility tree, which offers its text as a flat list of strings — not the app, not which string is
/// the title. The shape is private and moves between macOS releases, so this is deliberately easy to
/// change and deliberately fail-closed.
enum NotificationBannerText {
    /// Fold one banner's strings into a title and a body. Blanks and repeats are dropped; the first
    /// remaining string is the title and the last is the body, which is the order banners draw them in.
    /// `nil` when nothing readable came back — an unreadable banner shows nothing rather than a guess.
    static func fold(_ strings: [String]) -> (title: String, body: String?)? {
        var seen: [String] = []
        for raw in strings {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !seen.contains(text) else { continue }
            seen.append(text)
        }
        guard let title = seen.first else { return nil }
        return (title, seen.count > 1 ? seen.last : nil)
    }
}

// MARK: - Persistent Notification History Ring Buffer (Slice N-1)

/// One persisted notification entry in KatiKati's local history inbox.
struct NotificationHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let timestamp: Date
    var title: String
    var body: String?
    let appBundleId: String?
    var isRead: Bool

    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        title: String,
        body: String? = nil,
        appBundleId: String? = nil,
        isRead: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.title = title
        self.body = body
        self.appBundleId = appBundleId
        self.isRead = isRead
    }

    init(from mirrored: MirroredNotification, fallbackDate: Date = Date(), isRead: Bool = false) {
        self.id = mirrored.id
        self.timestamp = mirrored.date ?? fallbackDate
        self.title = mirrored.title
        self.body = mirrored.detail
        self.appBundleId = mirrored.bundleIdentifier
        self.isRead = isRead
    }
}

/// Pure ring-buffer reducer for persistent notification history, filtering, unread state, and redaction.
struct NotificationHistoryStore: Codable, Equatable, Sendable {
    static let defaultMaxCapacity = 250
    static let capacityChoices = [50, 100, 250]

    enum StorageKey {
        static let entries = "com.katikati.notifications.historyEntries"
        static let maxCapacity = "com.katikati.notifications.historyCapacity"
        static let quietMode = "com.katikati.notifications.quietMode"
        static let redactSensitive = "com.katikati.notifications.redactSensitive"
        static let sensitiveBundles = "com.katikati.notifications.sensitiveBundles"
    }

    static let defaultSensitiveBundleIDs: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.MobileSMS",
        "org.whispersystems.signal-desktop",
        "ru.keepcoder.Telegram",
        "net.whatsapp.WhatsApp",
    ]

    private(set) var entries: [NotificationHistoryEntry]
    private(set) var maxCapacity: Int

    init(entries: [NotificationHistoryEntry] = [], maxCapacity: Int = NotificationHistoryStore.defaultMaxCapacity) {
        self.maxCapacity = max(1, maxCapacity)
        self.entries = Array(entries.sorted { $0.timestamp > $1.timestamp }.prefix(self.maxCapacity))
    }

    var unreadCount: Int {
        entries.reduce(0) { $0 + ($1.isRead ? 0 : 1) }
    }

    /// Inserts or updates an entry at the front (newest-first) and evicts oldest items beyond `maxCapacity`.
    mutating func append(_ entry: NotificationHistoryEntry) {
        if let existingIndex = entries.firstIndex(where: { $0.id == entry.id }) {
            let wasRead = entries[existingIndex].isRead
            entries.remove(at: existingIndex)
            var updated = entry
            updated.isRead = entry.isRead || wasRead
            entries.insert(updated, at: 0)
        } else {
            entries.insert(entry, at: 0)
        }
        entries.sort { $0.timestamp > $1.timestamp }
        trimToCapacity()
    }

    mutating func append(contentsOf newEntries: [NotificationHistoryEntry]) {
        for entry in newEntries {
            append(entry)
        }
    }

    mutating func setMaxCapacity(_ capacity: Int) {
        maxCapacity = max(1, capacity)
        trimToCapacity()
    }

    mutating func markRead(id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isRead = true
    }

    mutating func markAllRead() {
        for index in entries.indices {
            entries[index].isRead = true
        }
    }

    mutating func clear() {
        entries.removeAll()
    }

    /// Drops one row (the deck's dismiss). The rest of the inbox keeps its order.
    mutating func remove(id: String) {
        entries.removeAll { $0.id == id }
    }

    /// Returns entries filtered by unread state and search query (`localizedStandardContains`).
    func filtered(query: String, unreadOnly: Bool) -> [NotificationHistoryEntry] {
        Self.filter(entries, query: query, unreadOnly: unreadOnly)
    }

    /// Returns a privacy-redacted copy of all entries for matching sensitive bundle IDs.
    func redacted(
        sensitiveBundleIDs: Set<String>,
        placeholder: String = "Notification content hidden"
    ) -> [NotificationHistoryEntry] {
        Self.redact(entries, sensitiveBundleIDs: sensitiveBundleIDs, placeholder: placeholder)
    }

    /// Redacts sensitive entries first so search queries cannot match hidden content.
    func visibleEntries(
        query: String,
        unreadOnly: Bool,
        sensitiveBundleIDs: Set<String>,
        placeholder: String = "Notification content hidden"
    ) -> [NotificationHistoryEntry] {
        let safeEntries = redacted(sensitiveBundleIDs: sensitiveBundleIDs, placeholder: placeholder)
        return Self.filter(safeEntries, query: query, unreadOnly: unreadOnly)
    }

    private mutating func trimToCapacity() {
        if entries.count > maxCapacity {
            entries.removeLast(entries.count - maxCapacity)
        }
    }

    static func filter(
        _ source: [NotificationHistoryEntry],
        query: String,
        unreadOnly: Bool
    ) -> [NotificationHistoryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return source.filter { entry in
            if unreadOnly && entry.isRead { return false }
            guard !trimmed.isEmpty else { return true }
            if entry.title.localizedStandardContains(trimmed) { return true }
            if let body = entry.body, body.localizedStandardContains(trimmed) { return true }
            if let bundleId = entry.appBundleId, bundleId.localizedStandardContains(trimmed) { return true }
            return false
        }
    }

    static func redact(
        _ source: [NotificationHistoryEntry],
        sensitiveBundleIDs: Set<String>,
        placeholder: String = "Notification content hidden"
    ) -> [NotificationHistoryEntry] {
        guard !sensitiveBundleIDs.isEmpty else { return source }
        return source.map { entry in
            guard let bundleId = entry.appBundleId, sensitiveBundleIDs.contains(bundleId) else {
                return entry
            }
            return NotificationHistoryEntry(
                id: entry.id,
                timestamp: entry.timestamp,
                title: placeholder,
                body: nil,
                appBundleId: bundleId,
                isRead: entry.isRead
            )
        }
    }

    static func load(defaults: UserDefaults = .standard) -> NotificationHistoryStore {
        let storedCapacity = defaults.integer(forKey: StorageKey.maxCapacity)
        let capacity = storedCapacity > 0 ? storedCapacity : defaultMaxCapacity
        guard let data = defaults.data(forKey: StorageKey.entries),
              let decoded = try? JSONDecoder().decode([NotificationHistoryEntry].self, from: data) else {
            return NotificationHistoryStore(maxCapacity: capacity)
        }
        return NotificationHistoryStore(entries: decoded, maxCapacity: capacity)
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(maxCapacity, forKey: StorageKey.maxCapacity)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: StorageKey.entries)
    }
}
