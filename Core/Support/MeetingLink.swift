import Foundation

/// A video-call service the dock can send you to straight from a calendar event.
enum MeetingProvider: String, CaseIterable, Sendable {
    case zoom
    case googleMeet
    case teams

    /// Brand-free SF Symbol; the provider name rides next to it as text.
    var symbolName: String { "video.fill" }

    func matches(host: String, path: String) -> Bool {
        switch self {
        case .zoom:
            return host == "zoom.us" || host.hasSuffix(".zoom.us") || host.hasSuffix(".zoomgov.com")
        case .googleMeet:
            return host == "meet.google.com" && path.count > 1 && !path.hasPrefix("/landing")
        case .teams:
            return (host == "teams.microsoft.com" && (path.hasPrefix("/l/meetup-join") || path.hasPrefix("/meet/")))
                || host == "teams.live.com" || host == "teams.microsoft.us"
        }
    }
}

/// The join link found in an event's URL / location / notes.
struct MeetingLink: Equatable, Sendable {
    let provider: MeetingProvider
    let url: URL

    /// First recognised video-call link across `fields`, searched in order (give the event's own URL first, then
    /// location, then notes). Notes from Outlook arrive HTML-escaped and wrapped in Safe Links, so each field is also
    /// scanned unescaped and percent-decoded.
    static func detect(in fields: [String?]) -> MeetingLink? {
        for field in fields.compactMap({ $0 }) where !field.isEmpty {
            let unescaped = field.replacingOccurrences(of: "&amp;", with: "&")
            for text in [unescaped, unescaped.removingPercentEncoding].compactMap({ $0 }) {
                if let link = firstLink(in: text) { return link }
            }
        }
        return nil
    }

    /// Lookahead so matches overlap: a link wrapped in a redirect (`?url=https://teams…`) is found as its own match.
    private static let urlPattern = try? NSRegularExpression(pattern: #"(?=((?:https?|zoommtg|zoomus)://[^\s<>"'\)\]]+))"#)

    private static func firstLink(in text: String) -> MeetingLink? {
        guard let urlPattern else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in urlPattern.matches(in: text, range: range) {
            guard let swiftRange = Range(match.range(at: 1), in: text) else { continue }
            let raw = String(text[swiftRange]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?>"))
            guard let url = URL(string: raw), let host = url.host?.lowercased() else { continue }
            if url.scheme == "zoommtg" || url.scheme == "zoomus" { return MeetingLink(provider: .zoom, url: url) }
            if let provider = MeetingProvider.allCases.first(where: { $0.matches(host: host, path: url.path) }) {
                return MeetingLink(provider: provider, url: url)
            }
        }
        return nil
    }
}
