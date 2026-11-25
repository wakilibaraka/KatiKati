import Foundation

/// SD-7: the Notification Centre's grouping and the digest widget's summary — the two decisions the page and the
/// card share, kept pure so ordering, counts and previews are tested without an inbox.
struct NotificationGroup: Identifiable, Equatable, Sendable {
    let bundleID: String?
    let entries: [NotificationHistoryEntry]

    var id: String { bundleID ?? "—" }
    var unreadCount: Int { entries.reduce(0) { $0 + ($1.isRead ? 0 : 1) } }
}

enum NotificationDigest {
    static let previewLimit = 3

    /// Newest first, gathered by app. Groups follow their newest entry, and within a group the newest is first,
    /// so the page reads as one timeline sliced by app rather than a different order per group.
    static func groups(_ entries: [NotificationHistoryEntry]) -> [NotificationGroup] {
        let sorted = entries.sorted { $0.timestamp > $1.timestamp }
        var order: [String?] = []
        var buckets: [String: [NotificationHistoryEntry]] = [:]
        for entry in sorted {
            let key = entry.appBundleId ?? ""
            if buckets[key] == nil {
                order.append(entry.appBundleId)
                buckets[key] = []
            }
            buckets[key]?.append(entry)
        }
        return order.map { NotificationGroup(bundleID: $0, entries: buckets[$0 ?? ""] ?? []) }
    }

    static func unreadCount(_ entries: [NotificationHistoryEntry]) -> Int {
        entries.reduce(0) { $0 + ($1.isRead ? 0 : 1) }
    }

    /// The digest card's previews: the newest few, regardless of app, so a quiet inbox still shows something.
    static func previews(_ entries: [NotificationHistoryEntry], limit: Int = previewLimit) -> [NotificationHistoryEntry] {
        guard limit > 0 else { return [] }
        return Array(entries.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    /// What a group is called when the app drew no icon: the bundle id's last component reads as a name
    /// ("com.apple.Safari" → "Safari"), and an entry that names no app at all stays "Other".
    static func label(for bundleID: String?) -> String {
        guard let bundleID, !bundleID.isEmpty else { return "Other" }
        let last = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        return last.isEmpty ? "Other" : last
    }
}
