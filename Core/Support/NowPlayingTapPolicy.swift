import Foundation

/// What a click on the Now Playing chip does: one preset decides the single-click and double-click actions.
enum NowPlayingTapAction: Equatable {
    case playPause, openPlayer, openSourceApp
}

enum NowPlayingTapPreset: String, CaseIterable {
    case playPauseThenPlayer, playerThenPlayPause, sourceAppThenPlayPause, playPauseThenSourceApp

    static let `default`: NowPlayingTapPreset = .playPauseThenSourceApp

    func action(forTaps taps: Int) -> NowPlayingTapAction {
        switch (self, taps) {
        case (.playPauseThenPlayer, 1): return .playPause
        case (.playPauseThenPlayer, _): return .openPlayer
        case (.playerThenPlayPause, 1): return .openPlayer
        case (.playerThenPlayPause, _): return .playPause
        case (.playPauseThenSourceApp, 1): return .playPause
        case (.playPauseThenSourceApp, _): return .openSourceApp
        case (.sourceAppThenPlayPause, 1): return .openSourceApp
        case (.sourceAppThenPlayPause, _): return .playPause
        }
    }
}

/// Tapping the artwork or the song text opens the player's own app; the owner can require a double-click
/// so a stray touch never launches it.
enum NowPlayingArtworkAccent {
    static let key = "com.katikati.nowplaying.artworkAccent"
    static var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

enum NowPlayingOpenTap {
    static let doubleTapKey = "com.katikati.nowplaying.openNeedsDoubleTap"
    static func tapCount(needsDouble: Bool) -> Int { needsDouble ? 2 : 1 }
}
