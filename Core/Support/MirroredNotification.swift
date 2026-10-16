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
