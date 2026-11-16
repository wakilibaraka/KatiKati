import Foundation

// Phase 8b-6 — pure playback-progress maths for the Live Island's music surfaces.
//
// MediaRemote reports `elapsed` as of `timestamp`, not live; a surface that wants a moving bar must
// extrapolate `elapsed + rate * (now - timestamp)`. Kept pure (no MediaRemote, no clock reads — the
// caller passes `now`) so the clamps and the unknown-duration cases are unit-tested. Dual-compiled.

enum NowPlayingProgress {
    /// Seconds into the track right now, clamped to `0...duration` when a duration is known.
    static func elapsed(at now: Date, elapsed: TimeInterval?, asOf timestamp: Date?, rate: Double, duration: TimeInterval?) -> TimeInterval? {
        guard let elapsed, elapsed.isFinite, elapsed >= 0 else { return nil }
        var value = elapsed
        if rate > 0, let timestamp { value += rate * max(0, now.timeIntervalSince(timestamp)) }
        if let duration, duration.isFinite, duration > 0 { value = min(value, duration) }
        return value
    }

    /// 0...1, or `nil` when the duration is unknown / zero (a live stream) or the elapsed time is missing.
    static func fraction(at now: Date, elapsed: TimeInterval?, asOf timestamp: Date?, rate: Double, duration: TimeInterval?) -> Double? {
        guard let duration, duration.isFinite, duration > 0,
              let current = Self.elapsed(at: now, elapsed: elapsed, asOf: timestamp, rate: rate, duration: duration) else { return nil }
        return min(max(current / duration, 0), 1)
    }
}

// MARK: - Phase 50g: Opt-in Synced Lyrics (lrclib.net)

struct LyricsLine: Equatable, Sendable {
    var time: TimeInterval
    var text: String
}

enum LyricsTrack {
    static let enabledKey = "com.katikati.notch.lyrics"

    /// Parses standard `[mm:ss.xx]` or `[mm:ss]` LRC lines into sorted `LyricsLine` entries.
    static func parseLRC(_ raw: String) -> [LyricsLine] {
        var out: [LyricsLine] = []
        for rawLine in raw.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { continue }
            let tag = line[line.index(after: line.startIndex)..<close]
            let parts = tag.split(separator: ":")
            guard parts.count == 2,
                  let minutes = Double(parts[0]),
                  let seconds = Double(parts[1]),
                  minutes >= 0, seconds >= 0 else { continue }
            let lyric = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
            guard !lyric.isEmpty else { continue }
            out.append(LyricsLine(time: minutes * 60 + seconds, text: lyric))
        }
        return out.sorted { $0.time < $1.time }
    }

    /// Returns the most recent lyric line whose timestamp is `<= elapsed`.
    static func activeLine(in lines: [LyricsLine], at elapsed: TimeInterval) -> String? {
        guard !lines.isEmpty, elapsed >= 0 else { return nil }
        var current: String?
        for line in lines {
            if line.time <= elapsed + 0.15 {
                current = line.text
            } else {
                break
            }
        }
        return current ?? lines.first?.text
    }
}
