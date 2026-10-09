import Foundation

// MARK: - MediaRemote Declarations

typealias MRMediaRemoteRegisterForNowPlayingNotificationsFunction = @convention(c) (DispatchQueue) -> Void
typealias MRMediaRemoteGetNowPlayingInfoFunction = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
typealias MRMediaRemoteSendCommandFunction = @convention(c) (UInt, Any?) -> Bool

let kMRMediaRemoteNowPlayingInfoTitle = "kMRMediaRemoteNowPlayingInfoTitle"
let kMRMediaRemoteNowPlayingInfoArtist = "kMRMediaRemoteNowPlayingInfoArtist"
let kMRMediaRemoteNowPlayingInfoPlaybackRate = "kMRMediaRemoteNowPlayingInfoPlaybackRate"

// MARK: - NowPlayingService

public struct NowPlayingState: Equatable {
    public var isPlaying: Bool
    public var title: String?
    public var artist: String?
}

public final class NowPlayingService: ObservableObject {
    @Published public private(set) var state: NowPlayingState = NowPlayingState(isPlaying: false)
    
    private var mrGetNowPlayingInfo: MRMediaRemoteGetNowPlayingInfoFunction?
    private var mrSendCommand: MRMediaRemoteSendCommandFunction?
    
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
        
        NotificationCenter.default.addObserver(self, selector: #selector(nowPlayingInfoDidChange), name: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(nowPlayingInfoDidChange), name: NSNotification.Name("kMRMediaRemoteNowPlayingApplicationDidChangeNotification"), object: nil)
        
        refresh()
    }
    
    @objc private func nowPlayingInfoDidChange() {
        refresh()
    }
    
    private func refresh() {
        guard let getInfo = mrGetNowPlayingInfo else { return }
        getInfo(DispatchQueue.main) { [weak self] info in
            let title = info[kMRMediaRemoteNowPlayingInfoTitle] as? String
            let artist = info[kMRMediaRemoteNowPlayingInfoArtist] as? String
            let rate = info[kMRMediaRemoteNowPlayingInfoPlaybackRate] as? Double ?? 0.0
            let isPlaying = rate > 0.0
            
            self?.state = NowPlayingState(isPlaying: isPlaying, title: title, artist: artist)
        }
    }
    
    public func togglePlayPause() {
        guard let sendCommand = mrSendCommand else { return }
        // MRMediaRemoteCommandTogglePlayPause is 2
        _ = sendCommand(2, nil)
    }
}
