import Foundation

// Phase 52c — reads the hook log: one `<epoch> <event>` line per turn boundary. Tolerant by design:
// the file is appended to by a shell command, so a half-written or junk line must never hide the
// newest good one. Dual-compiled.

enum ClaudeHookStatus {
    /// `true` while the newest event says working, `false` once it says stopped. `nil` means "no
    /// override": no usable line, an unknown event, or an event older than `window` (the transcript
    /// mtime is then the only signal, as before this slice).
    static func workingOverride(log: String, now: Date, window: TimeInterval = 300) -> Bool? {
        guard let newest = newestEvent(log: log) else { return nil }
        guard now.timeIntervalSince(newest.date) <= window else { return nil }
        switch newest.event {
        case ClaudeHookEvent.working.rawValue: return true
        case ClaudeHookEvent.idle.rawValue: return false
        default: return nil
        }
    }

    static func newestEvent(log: String) -> (event: String, date: Date)? {
        for line in log.split(whereSeparator: \.isNewline).reversed() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2, let epoch = Double(parts[0]) else { continue }
            return (String(parts[1]), Date(timeIntervalSince1970: epoch))
        }
        return nil
    }
}
