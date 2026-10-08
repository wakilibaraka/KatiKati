import Foundation
import Combine

public final class NowPlayingService: ObservableObject {
    @Published public private(set) var title: String?
    @Published public private(set) var artist: String?
    @Published public private(set) var isPlaying: Bool
    
    public init() {
        // To be wired to MediaRemote (MRMediaRemoteGetNowPlayingInfo)
        // For now, providing placeholder data to build the 3D visual aesthetic.
        self.title = "Blinding Lights"
        self.artist = "The Weeknd"
        self.isPlaying = true
    }
}
