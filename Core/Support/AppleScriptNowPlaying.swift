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
    static var source: String {
        """
        set sep to (ASCII character 9)
        set out to ""
        set refusal to ""
        if application "Spotify" is running then
        	tell application "Spotify"
        		try
        			set stateText to (player state as text)
        			set t to current track
        			set out to "Spotify" & sep & stateText & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & ((duration of t) / 1000) & sep & (player position) & sep & (artwork url of t)
        		on error errMsg number errNum
        			if refusal is "" then set refusal to "Spotify" & sep & errNum
        		end try
        	end tell
        end if
        if out is "" then
        	if application "Music" is running then
        		tell application "Music"
        			try
        				set stateText to (player state as text)
        				set t to current track
        				set out to "Music" & sep & stateText & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & (duration of t) & sep & (player position)
        				if (count of artworks of t) > 0 then
        					set d to (data of artwork 1 of t)
        					set f to (open for access (POSIX file "@ART@") with write permission)
        					set eof f to 0
        					write d to f
        					close access f
        					set out to out & sep & "@ART@"
        				end if
        			on error errMsg number errNum
        				if refusal is "" then set refusal to "Music" & sep & errNum
        			end try
        		end tell
        	end if
        end if
        if out is "" and refusal is not "" then
        	return "REFUSED" & sep & refusal
        end if
        return out
        """.replacingOccurrences(of: "@ART@", with: transientArtworkPath)
    }
}
