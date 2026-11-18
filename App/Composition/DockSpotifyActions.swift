import AppKit
import Foundation

/// Coordinates Like & Share actions for the Dock II Spotify / Now Playing wing widget.
/// Uses opt-in `SpotifyAuthService` when enabled and signed in, Apple Music AppleScript `loved`
/// when Apple Music is playing, and a persisted local favorites list as universal baseline.
@MainActor
final class DockSpotifyActions: ObservableObject {
    static let shared = DockSpotifyActions()

    private static let likedStorageKey = "com.katikati.dockII.likedTracks.v1"

    @Published private(set) var likedTrackKeys: Set<String>
    @Published private(set) var resolvedSpotifyTrackIDByKey: [String: (id: String, webURL: URL?)] = [:]

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.likedStorageKey) ?? []
        likedTrackKeys = Set(saved)
    }

    static func trackKey(title: String?, artist: String?) -> String? {
        DockSpotifyTrackKey.make(title: title, artist: artist)
    }

    func isLiked(title: String?, artist: String?) -> Bool {
        guard let key = Self.trackKey(title: title, artist: artist) else { return false }
        return likedTrackKeys.contains(key)
    }

    func syncRemoteLikeStateIfNeeded(title: String?, artist: String?) {
        guard UserDefaults.standard.bool(forKey: "com.katikati.dockII.spotifyOAuthEnabled"),
              SpotifyAuthService.shared.isSignedIn,
              let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
              let key = Self.trackKey(title: title, artist: artist)
        else {
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let resolved: (id: String, webURL: URL?)?
            if let cached = self.resolvedSpotifyTrackIDByKey[key] {
                resolved = cached
            } else {
                resolved = await SpotifyAuthService.shared.searchTrackID(title: title, artist: artist)
                if let resolved {
                    self.resolvedSpotifyTrackIDByKey[key] = resolved
                }
            }
            guard let trackID = resolved?.id,
                  let saved = await SpotifyAuthService.shared.isTrackSaved(trackID: trackID)
            else {
                return
            }
            self.setLocalLiked(saved, key: key)
        }
    }

    func toggleLike(for state: NowPlayingState) {
        guard let title = state.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
              let key = Self.trackKey(title: title, artist: state.artist)
        else {
            return
        }

        let targetLiked = !likedTrackKeys.contains(key)
        setLocalLiked(targetLiked, key: key)

        if UserDefaults.standard.bool(forKey: "com.katikati.dockII.spotifyOAuthEnabled"),
           SpotifyAuthService.shared.isSignedIn {
            Task { [weak self] in
                guard let self else { return }
                let resolved: (id: String, webURL: URL?)?
                if let cached = self.resolvedSpotifyTrackIDByKey[key] {
                    resolved = cached
                } else {
                    resolved = await SpotifyAuthService.shared.searchTrackID(title: title, artist: state.artist)
                    if let resolved { self.resolvedSpotifyTrackIDByKey[key] = resolved }
                }
                if let id = resolved?.id {
                    _ = await SpotifyAuthService.shared.setTrackSaved(targetLiked, trackID: id)
                }
            }
        } else if state.bundleIdentifier == "com.apple.Music" || state.appName == "Music" {
            let source = "tell application \"Music\" to if player state is not stopped then set loved of current track to \(targetLiked ? "true" : "false")"
            Task.detached(priority: .utility) {
                var error: NSDictionary?
                NSAppleScript(source: source)?.executeAndReturnError(&error)
            }
        }
    }

    func shareTrack(_ state: NowPlayingState, anchorView: NSView?) {
        let title = state.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { return }
        let artist = state.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let summary = artist.isEmpty ? title : "\(title) — \(artist)"

        var items: [Any] = [summary]
        if let key = Self.trackKey(title: title, artist: artist),
           let spotifyURL = resolvedSpotifyTrackIDByKey[key]?.webURL {
            items.append(spotifyURL)
        }

        if let anchorView, anchorView.window != nil {
            let picker = NSSharingServicePicker(items: items)
            picker.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxY)
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(summary, forType: .string)
        }
    }

    private func setLocalLiked(_ liked: Bool, key: String) {
        if liked {
            likedTrackKeys.insert(key)
        } else {
            likedTrackKeys.remove(key)
        }
        UserDefaults.standard.set(Array(likedTrackKeys), forKey: Self.likedStorageKey)
    }
}
