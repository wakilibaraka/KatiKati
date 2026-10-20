import Foundation

/// What a click on the Now Playing chip does: one preset decides the single-click and double-click actions.
enum NowPlayingTapAction: Equatable {
    case playPause, openPlayer, openSourceApp
}

enum NowPlayingTapPreset: String, CaseIterable {
    case playPauseThenPlayer, playerThenPlayPause, sourceAppThenPlayPause

    static let `default`: NowPlayingTapPreset = .playPauseThenPlayer

    func action(forTaps taps: Int) -> NowPlayingTapAction {
        switch (self, taps) {
        case (.playPauseThenPlayer, 1): return .playPause
        case (.playPauseThenPlayer, _): return .openPlayer
        case (.playerThenPlayPause, 1): return .openPlayer
        case (.playerThenPlayPause, _): return .playPause
        case (.sourceAppThenPlayPause, 1): return .openSourceApp
        case (.sourceAppThenPlayPause, _): return .playPause
        }
    }
}
