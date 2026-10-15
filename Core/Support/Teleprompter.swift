import Foundation

// Phase 37a — pure teleprompter rules: scroll speed, links in a script, which links may be fetched, and
// readable-text extraction from a fetched page. No UI, no network, no clocks; tested in `TeleprompterTests`.

enum TeleprompterSpeed {
    static let wpmRange: ClosedRange<Double> = 60...260
    static let defaultWPM = 140.0
    static let fontRange: ClosedRange<Double> = 18...64
    static let defaultFont = 30.0

    /// shortcut: assumes ~6 words per line at the usual widths, so scroll speed is an estimate of the
    /// requested words-per-minute, not a measurement; upgrade to counting laid-out lines if pacing drifts.
    static func pointsPerSecond(wpm: Double, fontSize: Double) -> Double {
        let lineHeight = fontSize * 1.35
        return wpm / 60 / 6 * lineHeight
    }
}

/// Scroll position of the script. `offset` is how far the text has moved up, in points.
struct TeleprompterScroll: Equatable, Sendable {
    private(set) var offset = 0.0

    /// Moves by `dt` seconds of reading. Returns false once the end is reached (the caller stops the timer).
    mutating func advance(dt: Double, wpm: Double, fontSize: Double, contentHeight: Double) -> Bool {
        guard dt > 0, dt < 1 else { return true }          // ignore a stalled frame instead of jumping
        offset = min(max(contentHeight, 0), offset + dt * TeleprompterSpeed.pointsPerSecond(wpm: wpm, fontSize: fontSize))
        return offset < contentHeight
    }

    mutating func nudge(_ points: Double, contentHeight: Double) { offset = min(max(offset + points, 0), max(contentHeight, 0)) }
    mutating func reset() { offset = 0 }
}

enum ScriptLinks {
    /// http(s) links in the text, in order, without duplicates.
    static func urls(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        var seen = Set<URL>()
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let url = match.url, ["http", "https"].contains(url.scheme?.lowercased()), seen.insert(url).inserted else { return nil }
            return url
        }
    }
}

/// Which links the reader may fetch. Only on an explicit tap, only https, never a local/private address
/// (a script pasted from elsewhere must not be able to probe the user's network).
enum LinkFetchPolicy {
    enum Verdict: Equatable, Sendable { case allowed, insecure, privateHost }

    static func verdict(for url: URL) -> Verdict {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), !host.isEmpty else { return .insecure }
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".localhost") || host.hasSuffix(".internal") { return .privateHost }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4 {
            let (a, b) = (parts[0], parts[1])
            if a == 10 || a == 127 || a == 0 || (a == 169 && b == 254) || (a == 192 && b == 168) || (a == 172 && (16...31).contains(b)) { return .privateHost }
        }
        if host.contains(":") { return .privateHost }       // IPv6 literals: refuse rather than parse
        return .allowed
    }
}

enum ReadableText {
    /// A page shorter than this is treated as "not readable here" (JavaScript-only or paywalled).
    static let minimumUsefulLength = 200

    static func extract(html: String) -> (title: String?, text: String) {
        var page = html
        let title = firstMatch(#"<title[^>]*>(.*?)</title>"#, in: page).map(decode)?.trimmingCharacters(in: .whitespacesAndNewlines)
        page = replace(#"<!--.*?-->"#, in: page, with: "")
        page = replace(#"<(script|style|noscript|svg|nav|header|footer|aside|form|template)\b[^>]*>.*?</\1\s*>"#, in: page, with: "")
        if let article = firstMatch(#"<article\b[^>]*>(.*?)</article>"#, in: page), article.count > minimumUsefulLength { page = article }
        page = replace(#"</(p|div|h[1-6]|blockquote|section)\s*>"#, in: page, with: "\n\n")
        page = replace(#"<br\s*/?>|</li\s*>|</tr\s*>"#, in: page, with: "\n")
        page = replace(#"<[^>]+>"#, in: page, with: "")
        let lines = decode(page).components(separatedBy: .newlines)
            .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\u{00A0}" }).joined(separator: " ") }
        let text = replace(#"\n{3,}"#, in: lines.joined(separator: "\n"), with: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (title?.isEmpty == true ? nil : title, text)
    }

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
    }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let re = regex(pattern) else { return text }
        return re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = regex(pattern), let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static let named = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " ",
                                "&ndash;": "–", "&mdash;": "—", "&hellip;": "…", "&rsquo;": "’", "&lsquo;": "‘", "&ldquo;": "“", "&rdquo;": "”"]

    static func decode(_ text: String) -> String {
        var out = text
        for (entity, value) in named { out = out.replacingOccurrences(of: entity, with: value) }
        guard let re = try? NSRegularExpression(pattern: #"&#(x?)([0-9a-fA-F]+);"#) else { return out }
        for m in re.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed() {
            guard let whole = Range(m.range, in: out), let hex = Range(m.range(at: 1), in: out), let digits = Range(m.range(at: 2), in: out),
                  let code = UInt32(out[digits], radix: out[hex].isEmpty ? 10 : 16), let scalar = Unicode.Scalar(code) else { continue }
            out.replaceSubrange(whole, with: String(Character(scalar)))
        }
        return out
    }
}
