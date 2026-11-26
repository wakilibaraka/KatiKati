import Foundation

// Phase 43 — the scriptable-player fallback behind the Live Island's music surfaces.
//
// `MRMediaRemoteGetNowPlayingInfo` answers only a trustworthily signed process: measured 2026-10-16, the
// very same call returns an empty dictionary from an ad-hoc build and the real 18 keys from an Apple-signed
// one — and with no signing identity at all, none of MediaRemote's callbacks fires. Spotify and Music are
// scriptable, so an ad-hoc build still shows the real track, its duration and position and its album art.
//
// Pure parsing (the script's tab-separated record to values) and the script itself live here, away from
// `NowPlayingService`, so the field rules and the script's syntax are unit-tested — the script shipped with
// an unbalanced `if` once, which made every read fail with -2741 while the island said "Not Playing".
// Dual-compiled into the app + test targets, exactly like `NowPlayingProgress.swift`.

enum AppleScriptNowPlaying {
    struct Reading: Equatable {
        let app: String            // "Spotify" | "Music"
        let isPlaying: Bool
        let title: String
        let artist: String
        let album: String
        /// 0 when the player reports none (a live stream): the surfaces then show no duration.
        let duration: TimeInterval
        let position: TimeInterval
        /// Spotify hands out an artwork URL; Music writes artwork 1's bytes to a file. Either may be nil.
        let artworkURL: URL?
        let artworkFile: URL?

        var bundleIdentifier: String { app == "Spotify" ? "com.spotify.client" : "com.apple.Music" }
    }

    /// Record shape: app, state, title, artist, album, duration(seconds), position(seconds), artwork.
    static func parse(_ raw: String) -> Reading? {
        let fields = raw.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\t")
        guard fields.count >= 7 else { return nil }
        let app = fields[0]
        guard app == "Spotify" || app == "Music" else { return nil }
        let title = fields[2]
        guard !title.isEmpty else { return nil }
        let duration = Double(fields[5]) ?? 0
        let position = Double(fields[6]) ?? 0
        var artworkURL: URL?, artworkFile: URL?
        if fields.count >= 8, !fields[7].isEmpty {
            if app == "Spotify" { artworkURL = URL(string: fields[7]) } else { artworkFile = URL(fileURLWithPath: fields[7]) }
        }
        return Reading(app: app, isPlaying: fields[1] == "playing", title: title,
                       artist: fields[3], album: fields[4],
                       duration: duration.isFinite && duration > 0 ? duration : 0,
                       position: position.isFinite && position > 0 ? position : 0,
                       artworkURL: artworkURL, artworkFile: artworkFile)
    }

    /// A running player that refused the ask: its name and the AppleScript error number it failed with.
    struct Refusal: Equatable {
        let player: String
        let errorNumber: Int
    }

    /// `REFUSED <tab> <player> <tab> <error number>` — the marker the script returns when it could read
    /// nothing and a running player said no. `nil` for a reading, an empty run, or anything else.
    static func refusal(in raw: String) -> Refusal? {
        let fields = raw.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\t")
        guard fields.count >= 3, fields[0] == "REFUSED",
              fields[1] == "Spotify" || fields[1] == "Music",
              let errorNumber = Int(fields[2]) else { return nil }
        return Refusal(player: fields[1], errorNumber: errorNumber)
    }

    /// Music has no artwork URL, so its branch exports artwork 1 to this file for us to read back.
    static var transientArtworkPath: String {
        (NSTemporaryDirectory() as NSString).appendingPathComponent("katikati-nowplaying-artwork")
    }

    /// One record per run; `is running` guards so a stopped player is never launched by asking it. A
    /// running player that refuses the ask (macOS Automation grant missing) is reported instead of
    /// swallowed — see `refusal(in:)` and `PlayerAccess`.
    static var source: String { source(includeSpotify: true, includeMusic: true) }

    /// Builds the fallback AppleScript containing only the players explicitly requested, so an uninstalled
    /// player (e.g. Spotify missing on disk) never triggers a compile-time "Where is <App>?" prompt.
    static func source(includeSpotify: Bool, includeMusic: Bool) -> String {
        guard includeSpotify || includeMusic else { return "" }
        var blocks: [String] = [
            "set sep to (ASCII character 9)",
            "set out to \"\"",
            "set refusal to \"\""
        ]
        if includeSpotify {
            blocks.append("""
            if application "Spotify" is running then
            \ttell application "Spotify"
            \t\ttry
            \t\t\tset stateText to (player state as text)
            \t\t\tset t to current track
            \t\t\tset out to "Spotify" & sep & stateText & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & ((duration of t) / 1000) & sep & (player position) & sep & (artwork url of t)
            \t\ton error errMsg number errNum
            \t\t\tif refusal is "" then set refusal to "Spotify" & sep & errNum
            \t\tend try
            \tend tell
            end if
            """)
        }
        if includeMusic {
            let musicBlock = """
            \tif application "Music" is running then
            \t\ttell application "Music"
            \t\t\ttry
            \t\t\t\tset stateText to (player state as text)
            \t\t\t\tset t to current track
            \t\t\t\tset out to "Music" & sep & stateText & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & (duration of t) & sep & (player position)
            \t\t\t\tif (count of artworks of t) > 0 then
            \t\t\t\t\tset d to (data of artwork 1 of t)
            \t\t\t\t\tset f to (open for access (POSIX file "@ART@") with write permission)
            \t\t\t\t\tset eof f to 0
            \t\t\t\t\twrite d to f
            \t\t\t\t\tclose access f
            \t\t\t\t\tset out to out & sep & "@ART@"
            \t\t\t\tend if
            \t\t\ton error errMsg number errNum
            \t\t\t\tif refusal is "" then set refusal to "Music" & sep & errNum
            \t\t\tend try
            \t\tend tell
            \tend if
            """.replacingOccurrences(of: "@ART@", with: transientArtworkPath)
            blocks.append(includeSpotify ? "if out is \"\" then\n\(musicBlock)\nend if" : musicBlock.replacingOccurrences(of: "\n\t", with: "\n").trimmingCharacters(in: CharacterSet(charactersIn: "\t")))
        }
        blocks.append("""
        if out is "" and refusal is not "" then
        \treturn "REFUSED" & sep & refusal
        end if
        return out
        """)
        return blocks.joined(separator: "\n")
    }

    // MARK: Transport target (Phase 47)

    /// The player a transport command must address. The fallback reading names the app it read;
    /// MediaRemote ever only left a bundle id behind — and in an unsigned build MediaRemote is the very
    /// reading that never arrives, so addressing the transport through that bundle id is what left the
    /// island's and the notch's buttons dead while the player was playing.
    static func transportTarget(fallbackApp: String?, bundleIdentifier: String?) -> String? {
        if let fallbackApp { return fallbackApp }
        switch bundleIdentifier {
        case "com.spotify.client": return "Spotify"
        case "com.apple.Music": return "Music"
        default: return nil
        }
    }

    /// Whether the AppleScript fallback is the live source and so has to be re-read on the tick: it is
    /// the source once it has named a player, and the only source while nothing is known yet.
    ///
    /// It used to be read only while the state was still empty, which froze every surface on the first
    /// track it found — the position interpolated off `elapsedAsOf` and nothing else ever moved again
    /// (Phase 47). With MediaRemote answering, `fallbackApp` is nil and a title is present, so the
    /// polling ends the moment the framework takes over.
    static func fallbackIsLive(fallbackApp: String?, title: String?) -> Bool {
        fallbackApp != nil || (title?.isEmpty ?? true)
    }
}

// MARK: - OW-5a: several players, one switcher

/// One running player with a current track. Two players can be open at once (Spotify in the background,
/// Music in the foreground); the surfaces show one, and this is the unit that says which.
struct MediaSession: Equatable, Sendable {
    /// `com.spotify.client` / `com.apple.Music`.
    let bundleID: String
    /// The AppleScript application name the reading came from.
    let app: String
    let title: String
    let artist: String
    let isPlaying: Bool
}

/// The players the AppleScript fallback can read, in the order a fresh cycle visits them.
enum MediaSessions {
    static let known: [(bundleID: String, app: String)] = [
        ("com.spotify.client", "Spotify"),
        ("com.apple.Music", "Music"),
    ]

    static func app(forBundleID bundleID: String?) -> String? {
        guard let bundleID else { return nil }
        return known.first { $0.bundleID == bundleID }?.app
    }

    static func bundleID(forApp app: String?) -> String? {
        guard let app else { return nil }
        return known.first { $0.app == app }?.bundleID
    }

    /// Records joined by newlines: `app <tab> state <tab> title <tab> artist`, one per running player that
    /// has a track. Empty when neither has one — the surfaces then show nothing, as before.
    static func parse(_ raw: String) -> [MediaSession] {
        raw.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.trimmingCharacters(in: .whitespaces).components(separatedBy: "\t")
            guard fields.count >= 4, fields[0] == "Spotify" || fields[0] == "Music",
                  let bundleID = bundleID(forApp: fields[0]) else { return nil }
            let title = fields[2]
            guard !title.isEmpty else { return nil }
            return MediaSession(bundleID: bundleID, app: fields[0], title: title,
                                artist: fields[3], isPlaying: fields[1] == "playing")
        }
    }

    /// The pinned player first, then the known order — so the switch is visible at the head of the list and
    /// clients never re-shuffle what the user just chose.
    static func ordered(_ sessions: [MediaSession], pinned bundleID: String?) -> [MediaSession] {
        let rank = known.map(\.bundleID)
        return sessions.sorted { left, right in
            if left.bundleID == bundleID { return right.bundleID != bundleID }
            if right.bundleID == bundleID { return false }
            let l = rank.firstIndex(of: left.bundleID) ?? rank.count
            let r = rank.firstIndex(of: right.bundleID) ?? rank.count
            return l == r ? left.bundleID < right.bundleID : l < r
        }
    }

    /// Reads every running player that has a track. Never launches a stopped one (`is running` guards).
    static var source: String { source(includeSpotify: true, includeMusic: true) }

    /// Builds the multi-session discovery script containing only requested players.
    static func source(includeSpotify: Bool, includeMusic: Bool) -> String {
        guard includeSpotify || includeMusic else { return "" }
        var blocks: [String] = [
            "set sep to (ASCII character 9)",
            "set out to \"\""
        ]
        if includeSpotify {
            blocks.append("""
            if application "Spotify" is running then
            \ttell application "Spotify"
            \t\ttry
            \t\t\tset stateText to (player state as text)
            \t\t\tset t to current track
            \t\t\tif (name of t) is not "" then
            \t\t\t\tset out to out & "Spotify" & sep & stateText & sep & (name of t) & sep & (artist of t) & linefeed
            \t\t\tend if
            \t\ton error errMsg number errNum
            \t\tend try
            \tend tell
            end if
            """)
        }
        if includeMusic {
            blocks.append("""
            if application "Music" is running then
            \ttell application "Music"
            \t\ttry
            \t\t\tset stateText to (player state as text)
            \t\t\tset t to current track
            \t\t\tif (name of t) is not "" then
            \t\t\t\tset out to out & "Music" & sep & stateText & sep & (name of t) & sep & (artist of t) & linefeed
            \t\t\tend if
            \t\ton error errMsg number errNum
            \t\tend try
            \tend tell
            end if
            """)
        }
        blocks.append("return out")
        return blocks.joined(separator: "\n")
    }

    /// One player's record (`Reading` shape) for the pinned session, so the surfaces follow the switch
    /// instead of whatever the system-wide route reports.
    static func readingSource(for app: String) -> String {
        let scriptName = app == "Spotify" ? "Spotify" : "Music"
        let tail = app == "Spotify"
            ? "\t\t\tset out to \"Spotify\" & sep & stateText & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & ((duration of t) / 1000) & sep & (player position) & sep & (artwork url of t)"
            : "\t\t\tset out to \"Music\" & sep & stateText & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & (duration of t) & sep & (player position)\n\t\t\tif (count of artworks of t) > 0 then\n\t\t\t\tset d to (data of artwork 1 of t)\n\t\t\t\tset f to (open for access (POSIX file \"@ART@\") with write permission)\n\t\t\t\tset eof f to 0\n\t\t\t\twrite d to f\n\t\t\t\tclose access f\n\t\t\t\tset out to out & sep & \"@ART@\"\n\t\t\tend if"
        let body = """
        set sep to (ASCII character 9)
        set out to ""
        if application "\(scriptName)" is running then
        \ttell application "\(scriptName)"
        \t\ttry
        \t\t\tset stateText to (player state as text)
        \t\t\tset t to current track
        \(tail)
        \t\ton error errMsg number errNum
        \t\t\treturn "REFUSED" & sep & "\(scriptName)" & sep & errNum
        \t\tend try
        \tend tell
        end if
        return out
        """
        return body.replacingOccurrences(of: "@ART@", with: AppleScriptNowPlaying.transientArtworkPath)
    }
}

/// Which player the surfaces show when more than one has a session. Pinned choice wins until it disappears;
/// cycling **wraps**, because there is no "end" of a set of open players to stop at.
struct MediaSessionSwitcher: Equatable, Sendable {
    private(set) var pinnedBundleID: String?

    mutating func clearPin() {
        pinnedBundleID = nil
    }

    /// Moves to the next (or previous) session, wrapping at both ends. Returns the chosen bundle id, or nil
    /// when there is nothing to switch between.
    @discardableResult
    mutating func cycle(among sessions: [MediaSession], forward: Bool = true) -> String? {
        guard !sessions.isEmpty else {
            pinnedBundleID = nil
            return nil
        }
        let ids = sessions.map(\.bundleID)
        guard let current = pinnedBundleID.flatMap({ ids.firstIndex(of: $0) }) else {
            let first = forward ? ids[0] : ids[ids.count - 1]
            pinnedBundleID = first
            return first
        }
        let step = forward ? 1 : -1
        let next = (current + step + ids.count) % ids.count
        pinnedBundleID = ids[next]
        return ids[next]
    }
}

// MARK: - P1: ungive/mediaremote-adapter JSON stream & diff parser (BSD-3-Clause)

/// Stateful parser for `mediaremote-adapter.pl ... stream --micros` NDJSON output plus argument builders
/// for `stream`, `send`, and `seek`. Kept pure and dual-compiled so tests exercise diff merging,
/// microsecond scaling, `NSNull` clearing, WebKit parent bundle resolution, and malformed input handling.
struct MediaRemoteAdapterStream {
    struct Update: Equatable {
        var hasTrack: Bool
        var isPlaying: Bool = false
        var title: String?
        var artist: String?
        var album: String?
        var bundleIdentifier: String?
        var processIdentifier: Int32?
        var duration: TimeInterval?
        var elapsed: TimeInterval?
        var timestamp: Date?
        var rate: Double = 0
        var artworkData: Data?
    }

    private(set) var accumulatedPayload: [String: Any] = [:]
    private(set) var cachedArtworkData: Data?
    private(set) var cachedIdentityKey: String?

    mutating func reset() {
        accumulatedPayload.removeAll()
        cachedArtworkData = nil
        cachedIdentityKey = nil
    }

    mutating func consume(jsonLine: Data, now: Date = Date()) -> Update? {
        guard !jsonLine.isEmpty,
              let root = try? JSONSerialization.jsonObject(with: jsonLine) as? [String: Any] else {
            return nil
        }
        if let type = root["type"] as? String, type != "data" {
            return nil
        }
        guard let payload = root["payload"] as? [String: Any] else {
            return nil
        }

        let isDiff = (root["diff"] as? Bool) ?? false
        if isDiff {
            for (key, value) in payload {
                if value is NSNull {
                    accumulatedPayload.removeValue(forKey: key)
                    if key == "artworkData" { cachedArtworkData = nil }
                } else {
                    accumulatedPayload[key] = value
                }
            }
        } else {
            if payload.isEmpty {
                reset()
                return Update(hasTrack: false)
            }
            var fresh: [String: Any] = [:]
            for (key, value) in payload where !(value is NSNull) {
                fresh[key] = value
            }
            accumulatedPayload = fresh
        }

        let rawTitle = accumulatedPayload["title"] as? String
        let title = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title, !title.isEmpty else {
            reset()
            return Update(hasTrack: false)
        }

        let artist = (accumulatedPayload["artist"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let album = (accumulatedPayload["album"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let parentBundle = (accumulatedPayload["parentApplicationBundleIdentifier"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
        let clientBundle = (accumulatedPayload["bundleIdentifier"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
        let bundleIdentifier = parentBundle ?? clientBundle
        let pid = (accumulatedPayload["processIdentifier"] as? NSNumber)?.int32Value

        let rateNum = (accumulatedPayload["playbackRate"] as? NSNumber)?.doubleValue
        let playingFlag = (accumulatedPayload["playing"] as? NSNumber)?.boolValue
        let isPlaying = playingFlag ?? ((rateNum ?? 0) > 0)
        let rate = rateNum ?? (isPlaying ? 1.0 : 0.0)

        let duration: TimeInterval? = {
            if let micros = (accumulatedPayload["durationMicros"] as? NSNumber)?.doubleValue,
               micros.isFinite, micros > 0 {
                return micros / 1_000_000.0
            }
            if let secs = (accumulatedPayload["duration"] as? NSNumber)?.doubleValue,
               secs.isFinite, secs > 0 {
                return secs
            }
            return nil
        }()

        let elapsed: TimeInterval? = {
            if let micros = (accumulatedPayload["elapsedTimeMicros"] as? NSNumber)?.doubleValue,
               micros.isFinite, micros >= 0 {
                return micros / 1_000_000.0
            }
            if let secs = (accumulatedPayload["elapsedTime"] as? NSNumber)?.doubleValue,
               secs.isFinite, secs >= 0 {
                return secs
            }
            return nil
        }()

        let timestamp: Date = {
            if let epochMicros = (accumulatedPayload["timestampEpochMicros"] as? NSNumber)?.doubleValue,
               epochMicros.isFinite, epochMicros > 0 {
                return Date(timeIntervalSince1970: epochMicros / 1_000_000.0)
            }
            if let isoString = accumulatedPayload["timestamp"] as? String,
               let parsed = Self.isoFormatter.date(from: isoString) {
                return parsed
            }
            return now
        }()

        let identityKey = "\(bundleIdentifier ?? "")|\(title)|\(artist ?? "")|\(album ?? "")"
        if identityKey != cachedIdentityKey {
            cachedIdentityKey = identityKey
            cachedArtworkData = nil
        }

        if let artworkBase64 = payload["artworkData"] as? String,
           let decoded = Data(base64Encoded: artworkBase64), !decoded.isEmpty {
            cachedArtworkData = decoded
        } else if cachedArtworkData == nil,
                  let artworkBase64 = accumulatedPayload["artworkData"] as? String,
                  let decoded = Data(base64Encoded: artworkBase64), !decoded.isEmpty {
            cachedArtworkData = decoded
        }

        return Update(
            hasTrack: true,
            isPlaying: isPlaying,
            title: title,
            artist: artist,
            album: album,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: pid,
            duration: duration,
            elapsed: elapsed,
            timestamp: timestamp,
            rate: rate,
            artworkData: cachedArtworkData
        )
    }

    static func streamArguments(scriptPath: String, frameworkPath: String) -> [String] {
        [scriptPath, frameworkPath, "stream", "--micros", "--debounce=100"]
    }

    static func sendArguments(scriptPath: String, frameworkPath: String, command: UInt) -> [String] {
        [scriptPath, frameworkPath, "send", "--force", "\(command)"]
    }

    static func seekArguments(scriptPath: String, frameworkPath: String, seconds: Double) -> [String] {
        let clamped = seconds.isFinite ? max(0, seconds) : 0
        let micros = Int64((clamped * 1_000_000.0).rounded())
        return [scriptPath, frameworkPath, "seek", "\(micros)"]
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
