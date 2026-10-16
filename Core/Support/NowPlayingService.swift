import AppKit
import Foundation

// MARK: - MediaRemote Declarations

typealias MRMediaRemoteRegisterForNowPlayingNotificationsFunction = @convention(c) (DispatchQueue) -> Void
typealias MRMediaRemoteGetNowPlayingInfoFunction = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
typealias MRMediaRemoteSendCommandFunction = @convention(c) (UInt, Any?) -> Bool
typealias MRMediaRemoteSetElapsedTimeFunction = @convention(c) (Double) -> Void
typealias MRMediaRemoteGetNowPlayingApplicationPIDFunction = @convention(c) (DispatchQueue, @escaping (pid_t) -> Void) -> Void
typealias MRMediaRemoteGetNowPlayingApplicationIsPlayingFunction = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void

let kMRMediaRemoteNowPlayingInfoTitle = "kMRMediaRemoteNowPlayingInfoTitle"
let kMRMediaRemoteNowPlayingInfoArtist = "kMRMediaRemoteNowPlayingInfoArtist"
let kMRMediaRemoteNowPlayingInfoAlbum = "kMRMediaRemoteNowPlayingInfoAlbum"
let kMRMediaRemoteNowPlayingInfoPlaybackRate = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
let kMRMediaRemoteNowPlayingInfoDuration = "kMRMediaRemoteNowPlayingInfoDuration"
let kMRMediaRemoteNowPlayingInfoElapsedTime = "kMRMediaRemoteNowPlayingInfoElapsedTime"
let kMRMediaRemoteNowPlayingInfoTimestamp = "kMRMediaRemoteNowPlayingInfoTimestamp"
let kMRMediaRemoteNowPlayingInfoArtworkData = "kMRMediaRemoteNowPlayingInfoArtworkData"

// MARK: - NowPlayingState

public struct NowPlayingState: Equatable {
    public var isPlaying: Bool
    public var title: String?
    public var artist: String?
    public var album: String?
    public var bundleIdentifier: String?
    public var appName: String?
    /// Track length, elapsed time as of `elapsedAsOf`, and the playback rate (0 = paused). Use
    /// `progress(at:)` for a live fraction.
    public var duration: TimeInterval?
    public var elapsed: TimeInterval?
    public var elapsedAsOf: Date?
    public var rate: Double = 0
    public var artworkData: Data?

    public init(
        isPlaying: Bool,
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        bundleIdentifier: String? = nil,
        appName: String? = nil,
        duration: TimeInterval? = nil,
        elapsed: TimeInterval? = nil,
        elapsedAsOf: Date? = nil,
        rate: Double = 0,
        artworkData: Data? = nil
    ) {
        self.isPlaying = isPlaying
        self.title = title
        self.artist = artist
        self.album = album
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.duration = duration
        self.elapsed = elapsed
        self.elapsedAsOf = elapsedAsOf
        self.rate = rate
        self.artworkData = artworkData
    }

    /// 0...1 playback progress right now, or nil when unknown (live stream / missing data).
    public func progress(at now: Date) -> Double? {
        NowPlayingProgress.fraction(at: now, elapsed: elapsed, asOf: elapsedAsOf, rate: rate, duration: duration)
    }
}

// The scriptable-player fallback (`AppleScriptNowPlaying`) lives in its own dual-compiled file,
// `Core/Support/AppleScriptNowPlaying.swift`, so its parsing and its script syntax are unit-tested.

// MARK: - NowPlayingService

public final class NowPlayingService: ObservableObject {
    @Published public private(set) var state: NowPlayingState = NowPlayingState(isPlaying: false)
    /// Whether a player can actually be read right now (Phase 45). `.refused` is the case the surfaces
    /// used to hide: a running Spotify/Music whose Automation grant is missing returned an error that was
    /// thrown away, so the widget said "Not Playing" while the player was playing.
    @Published private(set) var playerAccess: PlayerAccess = .unknown
    
    private var mrGetNowPlayingInfo: MRMediaRemoteGetNowPlayingInfoFunction?
    private var mrSendCommand: MRMediaRemoteSendCommandFunction?
    private var mrSetElapsedTime: MRMediaRemoteSetElapsedTimeFunction?
    private var mrGetPID: MRMediaRemoteGetNowPlayingApplicationPIDFunction?
    private var mrGetIsPlaying: MRMediaRemoteGetNowPlayingApplicationIsPlayingFunction?

    private var activePID: pid_t = 0
    private var cachedAppName: String?
    private var cachedBundleId: String?
    /// Set while the reading comes from the AppleScript fallback, so transport and seek go to that player.
    private var fallbackApp: String?
    private var isReadingFallback = false
    private var lastFallbackRead = Date.distantPast
    private var artworkCache: [String: Data] = [:]
    /// AppleScript blocks the thread it runs on, so the fallback is throttled to this interval.
    private static let fallbackInterval: TimeInterval = 2
    private static let artworkCacheLimit = 8
    
    public init() {
        // Dynamically load MediaRemote
        let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
        guard handle != nil else { return }
        
        if let registerFunc = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            let register = unsafeBitCast(registerFunc, to: MRMediaRemoteRegisterForNowPlayingNotificationsFunction.self)
            register(DispatchQueue.main)
        }
        
        if let getInfoFunc = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            mrGetNowPlayingInfo = unsafeBitCast(getInfoFunc, to: MRMediaRemoteGetNowPlayingInfoFunction.self)
        }
        
        if let sendCommandFunc = dlsym(handle, "MRMediaRemoteSendCommand") {
            mrSendCommand = unsafeBitCast(sendCommandFunc, to: MRMediaRemoteSendCommandFunction.self)
        }

        if let setElapsedFunc = dlsym(handle, "MRMediaRemoteSetElapsedTime") {
            mrSetElapsedTime = unsafeBitCast(setElapsedFunc, to: MRMediaRemoteSetElapsedTimeFunction.self)
        }

        if let getPIDFunc = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID") {
            mrGetPID = unsafeBitCast(getPIDFunc, to: MRMediaRemoteGetNowPlayingApplicationPIDFunction.self)
        }

        if let getIsPlayingFunc = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
            mrGetIsPlaying = unsafeBitCast(getIsPlayingFunc, to: MRMediaRemoteGetNowPlayingApplicationIsPlayingFunction.self)
        }
        
        // Listen to all relevant MediaRemote notifications across macOS
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(nowPlayingInfoDidChange), name: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"), object: nil)
        nc.addObserver(self, selector: #selector(nowPlayingInfoDidChange), name: NSNotification.Name("kMRMediaRemoteNowPlayingApplicationDidChangeNotification"), object: nil)
        nc.addObserver(self, selector: #selector(nowPlayingInfoDidChange), name: NSNotification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"), object: nil)
        nc.addObserver(self, selector: #selector(nowPlayingInfoDidChange), name: NSNotification.Name("kMRMediaRemoteNowPlayingPlaybackQueueDidChangeNotification"), object: nil)
        
        refresh()
    }
    
    @objc private func nowPlayingInfoDidChange() {
        refresh()
    }
    
    public func refresh() {
        // First resolve the active playing application PID if possible
        if let getPID = mrGetPID {
            getPID(DispatchQueue.main) { [weak self] pid in
                guard let self else { return }
                self.activePID = pid
                if pid > 0, let app = NSRunningApplication(processIdentifier: pid) {
                    self.cachedAppName = app.localizedName
                    self.cachedBundleId = app.bundleIdentifier
                } else {
                    self.cachedAppName = nil
                    self.cachedBundleId = nil
                }
                self.queryNowPlayingInfo()
            }
        } else {
            queryNowPlayingInfo()
        }
        readFallbackIfIdle()
    }

    /// MediaRemote can stay completely silent for an ad-hoc-signed process — measured 2026-10-16 with a
    /// minimal `dlopen` probe, none of the three callbacks above fires at all (the earlier measurement
    /// saw an empty dictionary instead). `queryNowPlayingInfo()` then never runs, so the scriptable
    /// players are read from here instead, at most once per `fallbackInterval` and only while the state
    /// is still empty, so MediaRemote's own answer always wins when it does arrive.
    private func readFallbackIfIdle() {
        guard state.title?.isEmpty ?? true else { return }
        readFallback()
    }

    private func queryNowPlayingInfo() {
        guard let getInfo = mrGetNowPlayingInfo else {
            readFallback()          // framework missing: the scriptable players are the only route left
            return
        }
        getInfo(DispatchQueue.main) { [weak self] info in
            guard let self else { return }
            let title = info[kMRMediaRemoteNowPlayingInfoTitle] as? String
            guard let title, !title.isEmpty else {
                // MediaRemote answered nothing (an unsigned process gets an empty dictionary, measured
                // 2026-10-16): read the scriptable players and leave the transport to them.
                readFallback()
                return
            }
            self.fallbackApp = nil
            let artist = info[kMRMediaRemoteNowPlayingInfoArtist] as? String
            let album = info[kMRMediaRemoteNowPlayingInfoAlbum] as? String
            let rate = info[kMRMediaRemoteNowPlayingInfoPlaybackRate] as? Double ?? 0.0

            let duration = info[kMRMediaRemoteNowPlayingInfoDuration] as? Double
            let elapsed = info[kMRMediaRemoteNowPlayingInfoElapsedTime] as? Double
            let elapsedAsOf = info[kMRMediaRemoteNowPlayingInfoTimestamp] as? Date
            let artworkData = info[kMRMediaRemoteNowPlayingInfoArtworkData] as? Data

            // Also check MRMediaRemoteGetNowPlayingApplicationIsPlaying for extra confirmation
            if let getIsPlaying = self.mrGetIsPlaying {
                getIsPlaying(DispatchQueue.main) { [weak self] isAppPlaying in
                    guard let self else { return }
                    let playing = isAppPlaying || rate > 0.0
                    self.playerAccess = .readable
                    self.state = NowPlayingState(
                        isPlaying: playing,
                        title: title,
                        artist: artist,
                        album: album,
                        bundleIdentifier: self.cachedBundleId,
                        appName: self.cachedAppName,
                        duration: duration,
                        elapsed: elapsed,
                        elapsedAsOf: elapsedAsOf,
                        rate: rate > 0.0 ? rate : (playing ? 1.0 : 0.0),
                        artworkData: artworkData
                    )
                }
            } else {
                let playing = rate > 0.0
                self.playerAccess = .readable
                self.state = NowPlayingState(
                    isPlaying: playing,
                    title: title,
                    artist: artist,
                    album: album,
                    bundleIdentifier: self.cachedBundleId,
                    appName: self.cachedAppName,
                    duration: duration,
                    elapsed: elapsed,
                    elapsedAsOf: elapsedAsOf,
                    rate: rate,
                    artworkData: artworkData
                )
            }
        }
    }
    
    // MARK: AppleScript fallback

    /// Runs the script on a background queue and hops back to publish. Called only when MediaRemote
    /// gave nothing, at most once per `fallbackInterval` and never twice at a time.
    private func readFallback() {
        let now = Date()
        guard !isReadingFallback, now.timeIntervalSince(lastFallbackRead) >= Self.fallbackInterval else { return }
        isReadingFallback = true
        lastFallbackRead = now
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let raw = Self.runAppleScript(AppleScriptNowPlaying.source)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isReadingFallback = false
                guard let reading = AppleScriptNowPlaying.parse(raw) else {
                    // Nothing scriptable is playing — or a running player refused the ask. The refusal is
                    // the one case the surfaces must speak up about instead of showing "Not Playing"
                    // (Phase 45); with no player running there is nothing to explain.
                    self.playerAccess = PlayerAccess.probe(scriptOutput: raw)
                    // Drop a stale reading instead of showing a dead track.
                    guard self.fallbackApp != nil else { return }
                    self.fallbackApp = nil
                    self.state = NowPlayingState(isPlaying: false)
                    return
                }
                self.apply(reading)
            }
        }
    }

    private func apply(_ reading: AppleScriptNowPlaying.Reading) {
        let sameTrack = state.title == reading.title && state.artist == reading.artist
        playerAccess = .readable
        fallbackApp = reading.app
        state = NowPlayingState(
            isPlaying: reading.isPlaying,
            title: reading.title,
            artist: reading.artist,
            album: reading.album,
            bundleIdentifier: reading.bundleIdentifier,
            appName: reading.app,
            duration: reading.duration > 0 ? reading.duration : nil,
            elapsed: reading.position,
            elapsedAsOf: Date(),
            rate: reading.isPlaying ? 1 : 0,
            artworkData: sameTrack ? state.artworkData : artworkCache[artworkKey(reading)]
        )
        if !sameTrack { loadArtwork(for: reading) }
    }

    /// Artwork is cached per track, so the 2 s re-read never re-downloads (Spotify) or re-reads (Music).
    private func artworkKey(_ reading: AppleScriptNowPlaying.Reading) -> String {
        reading.artworkURL?.absoluteString ?? "\(reading.app)|\(reading.artist)|\(reading.album)|\(reading.title)"
    }

    private func loadArtwork(for reading: AppleScriptNowPlaying.Reading) {
        let key = artworkKey(reading)
        defer {
            while artworkCache.count > Self.artworkCacheLimit, let oldest = artworkCache.keys.first(where: { $0 != key }) {
                artworkCache.removeValue(forKey: oldest)
            }
        }
        guard artworkCache[key] == nil else { return }
        if let url = reading.artworkURL {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, !data.isEmpty else { return }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.artworkCache[key] = data
                    if self.state.title == reading.title { self.state.artworkData = data }
                }
            }.resume()
        } else if let file = reading.artworkFile, let data = try? Data(contentsOf: file), !data.isEmpty {
            artworkCache[key] = data
            state.artworkData = data
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Transport for the fallback player: the private framework command goes nowhere in an unsigned build.
    private func fallbackTransport(_ command: String) {
        guard let app = fallbackApp else { return }
        executeAppleScript("tell application \"" + app + "\" to " + command)
    }

    /// Synchronous script run, on the calling (background) queue. Empty string on any failure.
    private static func runAppleScript(_ source: String) -> String {
        guard let script = NSAppleScript(source: source) else { return "" }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return "" }
        return result.stringValue ?? ""
    }

    public func play() {
        if let sendCommand = mrSendCommand {
            _ = sendCommand(0, nil)
        }
        fallbackTransport("play")
    }

    public func pause() {
        if let sendCommand = mrSendCommand {
            _ = sendCommand(1, nil)
        }
        fallbackTransport("pause")
    }

    public func togglePlayPause() {
        if let sendCommand = mrSendCommand {
            _ = sendCommand(2, nil)
        }
        // Fallback for Music / Spotify if needed
        if state.bundleIdentifier == "com.apple.Music" {
            executeAppleScript("tell application \"Music\" to playpause")
        } else if state.bundleIdentifier == "com.spotify.client" {
            executeAppleScript("tell application \"Spotify\" to playpause")
        }
    }

    /// MRMediaRemoteCommandNextTrack = 4, PreviousTrack = 5.
    public func nextTrack() {
        if let sendCommand = mrSendCommand {
            _ = sendCommand(4, nil)
        }
        if state.bundleIdentifier == "com.apple.Music" {
            executeAppleScript("tell application \"Music\" to next track")
        } else if state.bundleIdentifier == "com.spotify.client" {
            executeAppleScript("tell application \"Spotify\" to next track")
        }
    }

    public func previousTrack() {
        if let sendCommand = mrSendCommand {
            _ = sendCommand(5, nil)
        }
        if state.bundleIdentifier == "com.apple.Music" {
            executeAppleScript("tell application \"Music\" to previous track")
        } else if state.bundleIdentifier == "com.spotify.client" {
            executeAppleScript("tell application \"Spotify\" to previous track")
        }
    }

    public func seek(to seconds: Double) {
        mrSetElapsedTime?(seconds)
        fallbackTransport("set player position to " + String(Swift.max(0, seconds)))
    }

    private func executeAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let script = NSAppleScript(source: source) {
                script.executeAndReturnError(&error)
            }
        }
    }
}

