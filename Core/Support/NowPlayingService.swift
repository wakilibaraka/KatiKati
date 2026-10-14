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

// MARK: - NowPlayingService

public final class NowPlayingService: ObservableObject {
    @Published public private(set) var state: NowPlayingState = NowPlayingState(isPlaying: false)
    
    private var mrGetNowPlayingInfo: MRMediaRemoteGetNowPlayingInfoFunction?
    private var mrSendCommand: MRMediaRemoteSendCommandFunction?
    private var mrSetElapsedTime: MRMediaRemoteSetElapsedTimeFunction?
    private var mrGetPID: MRMediaRemoteGetNowPlayingApplicationPIDFunction?
    private var mrGetIsPlaying: MRMediaRemoteGetNowPlayingApplicationIsPlayingFunction?

    private var activePID: pid_t = 0
    private var cachedAppName: String?
    private var cachedBundleId: String?
    
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
    }

    private func queryNowPlayingInfo() {
        guard let getInfo = mrGetNowPlayingInfo else { return }
        getInfo(DispatchQueue.main) { [weak self] info in
            guard let self else { return }
            let title = info[kMRMediaRemoteNowPlayingInfoTitle] as? String
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
    
    public func play() {
        if let sendCommand = mrSendCommand {
            _ = sendCommand(0, nil)
        }
    }

    public func pause() {
        if let sendCommand = mrSendCommand {
            _ = sendCommand(1, nil)
        }
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

