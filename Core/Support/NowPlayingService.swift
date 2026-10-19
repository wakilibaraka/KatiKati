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

// MARK: - System helper

/// MediaRemote answers only a platform-signed process (measured 2026-10-19: the same call is empty from an
/// ad-hoc build and complete — artwork bytes included — from `/usr/bin/swift`). So the system-wide
/// "currently playing app" is read by a long-lived interpreter that prints one JSON line per second and
/// takes `cmd <n>` / `seek <s>` lines on stdin. It sees whatever app is playing, scriptable or not.
/// shortcut: needs the Xcode command-line tools' /usr/bin/swift, upgrade to a perl-loaded helper dylib to
/// ship without them. Without it the service falls back to the AppleScript players as before.
final class NowPlayingHelper {
    private static let source = #"""
    import AppKit
    let h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)
    typealias GetInfo = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    typealias GetPID = @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void
    typealias Send = @convention(c) (UInt, Any?) -> Bool
    typealias SetElapsed = @convention(c) (Double) -> Void
    guard let h, let i = dlsym(h, "MRMediaRemoteGetNowPlayingInfo"), let p = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationPID") else { exit(2) }
    let getInfo = unsafeBitCast(i, to: GetInfo.self), getPID = unsafeBitCast(p, to: GetPID.self)
    let send = dlsym(h, "MRMediaRemoteSendCommand").map { unsafeBitCast($0, to: Send.self) }
    let setElapsed = dlsym(h, "MRMediaRemoteSetElapsedTime").map { unsafeBitCast($0, to: SetElapsed.self) }
    var lastArt = -1, lastTitle = "", lastNone = false
    func emit(_ o: [String: Any]) {
        if let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) { print(s); fflush(stdout) }
    }
    func poll() {
        getPID(.main) { pid in
            getInfo(.main) { info in
                let k = "kMRMediaRemoteNowPlayingInfo"
                guard let t = info[k + "Title"] as? String, !t.isEmpty else {
                    if !lastNone { lastNone = true; emit(["none": 1]) }
                    return
                }
                lastNone = false
                if t != lastTitle { lastTitle = t; lastArt = -1 }
                var o: [String: Any] = ["t": t, "r": info[k + "PlaybackRate"] as? Double ?? 0]
                if let v = info[k + "Artist"] as? String { o["a"] = v }
                if let v = info[k + "Album"] as? String { o["al"] = v }
                if let v = info[k + "Duration"] as? Double, v.isFinite { o["d"] = v }
                if let v = info[k + "ElapsedTime"] as? Double, v.isFinite { o["e"] = v }
                if let v = info[k + "Timestamp"] as? Date { o["ts"] = v.timeIntervalSince1970 }
                if pid > 0, let app = NSRunningApplication(processIdentifier: pid) {
                    o["b"] = app.bundleIdentifier ?? ""
                    o["n"] = app.localizedName ?? ""
                }
                if let d = info[k + "ArtworkData"] as? Data, d.count != lastArt { lastArt = d.count; o["art"] = d.base64EncodedString() }
                emit(o)
            }
        }
    }
    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in poll() }
    poll()
    Thread.detachNewThread {
        while let line = readLine() {
            let f = line.split(separator: " ")
            if f.count == 2, f[0] == "cmd", let c = UInt(f[1]) { _ = send?(c, nil) }
            if f.count == 2, f[0] == "seek", let s = Double(f[1]) { setElapsed?(s) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { poll() }
        }
        exit(0)   // the app closed our stdin
    }
    RunLoop.main.run()
    """#

    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    /// Called on the main queue with each decoded line; `onExit` when the process ends.
    var onLine: (([String: Any]) -> Void)?
    var onExit: (() -> Void)?

    func start() {
        let swift = "/usr/bin/swift"
        guard process == nil, FileManager.default.isExecutableFile(atPath: swift) else { return }
        let file = (NSTemporaryDirectory() as NSString).appendingPathComponent("katikati-nowplaying-helper.swift")
        guard (try? Self.source.write(toFile: file, atomically: true, encoding: .utf8)) != nil else { return }
        let task = Process(), out = Pipe(), inp = Pipe()
        task.executableURL = URL(fileURLWithPath: swift)
        task.arguments = [file]
        task.standardOutput = out
        task.standardInput = inp
        task.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            DispatchQueue.main.async { self?.consume(chunk) }
        }
        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                out.fileHandleForReading.readabilityHandler = nil
                self?.process = nil
                self?.input = nil
                self?.onExit?()
            }
        }
        guard (try? task.run()) != nil else { return }
        process = task
        input = inp.fileHandleForWriting
    }

    func send(_ line: String) {
        try? input?.write(contentsOf: Data((line + "\n").utf8))
    }

    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let end = buffer.firstIndex(of: 10) {
            let line = buffer[buffer.startIndex..<end]
            buffer.removeSubrange(buffer.startIndex...end)
            if let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { onLine?(json) }
        }
    }
}

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
    private let helper = NowPlayingHelper()
    /// True while the helper's system-wide reading is what the state shows: it then outranks the
    /// scriptable fallback, and transport goes through the helper so nothing is sent twice.
    private var helperHasTrack = false
    /// AppleScript blocks the thread it runs on, so the fallback is throttled to this interval.
    private static let fallbackInterval: TimeInterval = 2
    private static let artworkCacheLimit = 8
    
    public init() {
        helper.onLine = { [weak self] in self?.apply(helperLine: $0) }
        helper.onExit = { [weak self] in
            guard let self, self.helperHasTrack else { return }
            self.helperHasTrack = false
            self.state = NowPlayingState(isPlaying: false)
        }
        helper.start()
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
    /// players are read from here instead, at most once per `fallbackInterval`.
    ///
    /// Phase 47: that read no longer stops at the first track. Reading only while the state was empty
    /// froze the surfaces on it — a track changed in the player, or skipped by the surfaces' own Next,
    /// never appeared, so those buttons read as dead. The rule is now
    /// `AppleScriptNowPlaying.fallbackIsLive`, and MediaRemote's own answer still wins and ends the
    /// polling the moment it arrives.
    private func readFallbackIfIdle() {
        guard AppleScriptNowPlaying.fallbackIsLive(fallbackApp: fallbackApp, title: state.title) else { return }
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
                guard !self.helperHasTrack else { return }
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

    private func apply(helperLine line: [String: Any]) {
        guard let title = line["t"] as? String else {
            // Nothing playing system-wide: hand the surfaces back to the scriptable players.
            guard helperHasTrack else { return }
            helperHasTrack = false
            state = NowPlayingState(isPlaying: false)
            return
        }
        let artist = line["a"] as? String
        let sameTrack = state.title == title && state.artist == artist && helperHasTrack
        let rate = line["r"] as? Double ?? 0
        let art = (line["art"] as? String).flatMap { Data(base64Encoded: $0) }
        let next = NowPlayingState(
            isPlaying: rate > 0,
            title: title,
            artist: artist,
            album: line["al"] as? String,
            bundleIdentifier: (line["b"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            appName: (line["n"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            duration: line["d"] as? Double,
            elapsed: line["e"] as? Double,
            elapsedAsOf: (line["ts"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date(),
            rate: rate,
            artworkData: art ?? (sameTrack ? state.artworkData : nil)
        )
        var quiet = next
        quiet.elapsed = state.elapsed
        quiet.elapsedAsOf = state.elapsedAsOf
        // The surfaces extrapolate the position themselves, so a one-second tick that merely agrees with
        // that extrapolation is not worth a publish (every surface would re-render each second).
        if sameTrack, quiet == state,
           let expected = NowPlayingProgress.elapsed(at: next.elapsedAsOf ?? Date(), elapsed: state.elapsed, asOf: state.elapsedAsOf, rate: state.rate, duration: state.duration),
           let actual = next.elapsed, abs(expected - actual) < 1.5 { return }
        helperHasTrack = true
        fallbackApp = nil
        playerAccess = .readable
        state = next
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

    /// The player a transport command addresses, or nil when nothing scriptable can be commanded.
    private var scriptablePlayer: String? {
        AppleScriptNowPlaying.transportTarget(fallbackApp: fallbackApp, bundleIdentifier: state.bundleIdentifier)
    }

    /// Transport for the fallback player: the private framework command goes nowhere in an unsigned
    /// build, so this is the one that has to work — through the player the *reading* named. Phase 47: it
    /// used to be sent only when the state carried Spotify's or Music's bundle id, which is the value the
    /// fallback reading is what sets and the silent MediaRemote never set at all.
    private func fallbackTransport(_ command: String) {
        guard !helperHasTrack, let app = scriptablePlayer else { return }
        executeAppleScript("tell application \"" + app + "\" to " + command)
        reRead(after: 0.4)
    }

    /// The player applies a transport command a beat after it returns, so the surfaces ask again instead
    /// of waiting out the 2 s poll — otherwise a press reads as dead (Phase 47).
    private func reRead(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.lastFallbackRead = .distantPast
            self.readFallback()
        }
    }

    /// The surface must not wait for the player to confirm a press. Only applied when a scriptable player
    /// actually took the command: with none, nothing moved and the state must not claim it did.
    private func optimistically(_ mutate: (inout NowPlayingState) -> Void) {
        guard scriptablePlayer != nil || helperHasTrack else { return }
        var next = state
        mutate(&next)
        state = next
    }

    /// Play/pause is the one command whose own state the surfaces draw (the glyph, the ring), and the
    /// player reports it back a beat later: flip it now, moving the position's reference to the flip so
    /// the bar does not jump when the re-read lands (Phase 47).
    private func optimisticPlay(_ isPlaying: Bool) {
        optimistically { state in
            guard state.isPlaying != isPlaying else { return }
            state.elapsedAsOf = Date()
            state.isPlaying = isPlaying
            state.rate = isPlaying ? 1 : 0
        }
    }

    /// Synchronous script run, on the calling (background) queue. Empty string on any failure.
    private static func runAppleScript(_ source: String) -> String {
        guard let script = NSAppleScript(source: source) else { return "" }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return "" }
        return result.stringValue ?? ""
    }

    /// One route per press: the helper when it is the live source, the in-process framework otherwise.
    private func sendCommand(_ code: UInt) {
        if helperHasTrack { helper.send("cmd \(code)") } else if let send = mrSendCommand { _ = send(code, nil) }
    }

    public func play() {
        sendCommand(0)
        optimisticPlay(true)
        fallbackTransport("play")
    }

    public func pause() {
        sendCommand(1)
        optimisticPlay(false)
        fallbackTransport("pause")
    }

    public func togglePlayPause() {
        sendCommand(2)
        optimisticPlay(!state.isPlaying)
        fallbackTransport("playpause")
    }

    /// MRMediaRemoteCommandNextTrack = 4, PreviousTrack = 5. The skip itself is the player's; the new
    /// track comes back on the forced re-read, so the surfaces follow the button (Phase 47).
    public func nextTrack() {
        sendCommand(4)
        fallbackTransport("next track")
    }

    public func previousTrack() {
        sendCommand(5)
        fallbackTransport("previous track")
    }

    public func seek(to seconds: Double) {
        if helperHasTrack { helper.send("seek \(seconds)") } else { mrSetElapsedTime?(seconds) }
        optimistically { state in
            state.elapsed = Swift.max(0, seconds)
            state.elapsedAsOf = Date()
        }
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

