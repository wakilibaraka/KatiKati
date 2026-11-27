import AppKit
import Foundation

/// L2 + D4: shared non-blocking Up Next fetcher. Reads Spotify Web API `/v1/me/player/queue`
/// when signed in, or Apple Music's running `current playlist` (never launching Music, never on lock screen).
@MainActor
final class MusicQueueFetcher: ObservableObject {
    static let shared = MusicQueueFetcher()

    @Published private(set) var upcoming: [MusicQueueEntry] = []
    @Published private(set) var isLoading = false

    private var lastCacheKey: String = ""
    private var lastFetchAt: Date = .distantPast
    private var inFlightTask: Task<Void, Never>?

    private init() {}

    func refreshIfNeeded(appName: String?, currentTitle: String?, allowAppleScript: Bool = true) {
        let key = "\(appName ?? "")|\(currentTitle ?? "")|\(allowAppleScript)"
        if key == lastCacheKey, Date().timeIntervalSince(lastFetchAt) < 30 {
            return
        }
        inFlightTask?.cancel()
        lastCacheKey = key
        isLoading = true

        let isSpotify = SpotifyAuthService.shared.isSignedIn
            && (appName?.localizedCaseInsensitiveContains("spotify") == true || appName == nil)
        let isMusic = allowAppleScript
            && appName?.localizedCaseInsensitiveContains("music") == true

        inFlightTask = Task { [weak self] in
            var entries: [MusicQueueEntry] = []
            if isSpotify {
                entries = await SpotifyAuthService.shared.fetchQueue()
            } else if isMusic {
                entries = await Self.fetchAppleMusicQueue(limit: 8)
            }
            guard !Task.isCancelled, let self else { return }
            self.upcoming = entries
            self.lastFetchAt = Date()
            self.isLoading = false
        }
    }

    private static func fetchAppleMusicQueue(limit: Int) async -> [MusicQueueEntry] {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else {
            return []
        }
        return await Task.detached(priority: .utility) {
            let source = """
            tell application "Music"
                if not running then return ""
                try
                    set idx to index of current track
                    set pl to current playlist
                    set totalCount to count of tracks of pl
                    set outText to ""
                    set upperBound to idx + \(max(1, limit))
                    if upperBound > totalCount then set upperBound to totalCount
                    repeat with i from (idx + 1) to upperBound
                        set t to track i of pl
                        set outText to outText & (name of t) & "\t" & (artist of t) & "\n"
                    end repeat
                    return outText
                on error
                    return ""
                end try
            end tell
            """
            var error: NSDictionary?
            guard let script = NSAppleScript(source: source),
                  let raw = script.executeAndReturnError(&error).stringValue,
                  !raw.isEmpty else {
                return []
            }
            var result: [MusicQueueEntry] = []
            var seen = Set<String>()
            for line in raw.components(separatedBy: .newlines) where !line.isEmpty {
                let parts = line.components(separatedBy: "\t")
                let title = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !title.isEmpty else { continue }
                let artist = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                let entry = MusicQueueEntry(title: title, artist: artist.isEmpty ? nil : artist)
                if seen.insert(entry.key).inserted {
                    result.append(entry)
                }
            }
            return result
        }.value
    }
}
