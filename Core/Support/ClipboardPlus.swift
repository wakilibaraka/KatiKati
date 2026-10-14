import Foundation

/// Phase 22a: clipboard ignore-patterns and the toast policy. Pure and side-effect free; the monitor
/// (`Platform/Clipboard/ClipboardMonitor`) applies them. Settings (phase 12) edits the stored rules.
enum ClipboardIgnoreRules {
    /// One user rule: `/regex/` is a regular expression, anything else is a case-insensitive substring.
    enum Rule: Equatable, Sendable {
        case substring(String)
        case regex(String)
    }

    /// Parses one rule per line (blank lines dropped). A rule wrapped in slashes is a regex.
    static func parseLines(_ raw: String) -> [Rule] {
        raw.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.count > 2, trimmed.hasPrefix("/"), trimmed.hasSuffix("/") {
                return .regex(String(trimmed.dropFirst().dropLast()))
            }
            return .substring(trimmed.lowercased())
        }
    }

    /// True when `text` matches any rule: a match is never recorded (and so never toasted).
    static func matches(_ text: String, rules: [Rule]) -> Bool {
        guard !rules.isEmpty else { return false }
        let lowered = text.lowercased()
        for rule in rules {
            switch rule {
            case .substring(let needle):
                if lowered.contains(needle) { return true }
            case .regex(let pattern):
                guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
                if re.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) != nil { return true }
            }
        }
        return false
    }
}

/// Phase 22a: whether a recorded copy earns a toast. Nothing blank, nothing the preview would hide.
enum ClipboardToastPolicy {
    static func shouldToast(_ text: String) -> Bool { !ClipboardHistory.previewLine(text).isEmpty }
}
