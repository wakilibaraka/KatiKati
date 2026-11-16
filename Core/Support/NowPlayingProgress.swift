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

// MARK: - Phase 60: Queue Reorder Intent & Multi-Line Timeline Matcher (Slice A-QueueLyrics)

/// Model representing a track in the playback queue.
struct NowPlayingQueueItem: Equatable, Sendable, Identifiable {
    let id: String
    var title: String
    var artist: String
    var duration: TimeInterval?

    init(id: String = UUID().uuidString, title: String, artist: String = "", duration: TimeInterval? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.duration = duration
    }
}

/// Pure queue manipulation logic.
enum NowPlayingQueueReorderPlan {
    /// Promotes the given track to the head of the upcoming queue (index 0).
    static func promoteTrackToTop(in queue: [NowPlayingQueueItem], id: String) -> [NowPlayingQueueItem] {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return queue }
        if index == 0 { return queue }
        var result = queue
        let item = result.remove(at: index)
        result.insert(item, at: 0)
        return result
    }

    /// Removes a track by identifier.
    static func removeTrack(in queue: [NowPlayingQueueItem], id: String) -> [NowPlayingQueueItem] {
        queue.filter { $0.id != id }
    }
}

/// Matcher that computes line windows and progress within the lyric timeline.
enum LyricTimelineMatcher {
    /// Finds the index of the active lyric line at the given elapsed time.
    static func activeIndex(in lines: [LyricsLine], at elapsed: TimeInterval) -> Int? {
        guard !lines.isEmpty, elapsed >= 0 else { return nil }
        var activeIdx: Int? = nil
        for (i, line) in lines.enumerated() {
            if line.time <= elapsed + 0.15 {
                activeIdx = i
            } else {
                break
            }
        }
        return activeIdx ?? 0
    }

    /// Returns a sliding window of lyric lines centered on or near the active line.
    static func window(in lines: [LyricsLine], at elapsed: TimeInterval, windowSize: Int = 3) -> [LyricsLine] {
        guard !lines.isEmpty else { return [] }
        guard let active = activeIndex(in: lines, at: elapsed) else { return Array(lines.prefix(windowSize)) }
        let half = windowSize / 2
        let start = max(0, min(lines.count - windowSize, active - half))
        let end = min(lines.count, start + windowSize)
        return Array(lines[start..<end])
    }

    /// Progress (0...1) from current line start time to next line start time.
    static func lineProgress(in lines: [LyricsLine], at elapsed: TimeInterval) -> Double {
        guard let activeIdx = activeIndex(in: lines, at: elapsed), lines.indices.contains(activeIdx) else { return 0.0 }
        let currentLine = lines[activeIdx]
        let nextTime = (activeIdx + 1 < lines.count) ? lines[activeIdx + 1].time : (currentLine.time + 4.0)
        let span = max(0.5, nextTime - currentLine.time)
        let prog = (elapsed - currentLine.time) / span
        return min(max(prog, 0.0), 1.0)
    }
}

/// Size profiles for detachable FloatingPlayerPanel.
enum FloatingPlayerSize: String, CaseIterable, Sendable {
    case mini
    case player
    case expanded

    var defaultDimensions: (width: CGFloat, height: CGFloat) {
        switch self {
        case .mini: return (180, 48)
        case .player: return (280, 120)
        case .expanded: return (340, 280)
        }
    }
}
