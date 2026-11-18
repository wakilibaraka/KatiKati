import AppKit
import SwiftUI

/// DeXign Studio Dock II Now Playing / Spotify wing widget.
/// Powered by `LiveActivityFeed` (`NowPlayingService`), `DockSpotifyActions` (Like & Share), and `LyricsStore`.
struct DockSpotifyWidgetView: View {
    @Environment(\.widgetSize) private var size
    @Environment(\.dockWingVertical) private var isVertical
    @Environment(\.dockPopoverEdge) private var popoverEdge
    @ObservedObject private var feed = LiveActivityFeed.shared
    @ObservedObject private var actions = DockSpotifyActions.shared
    @State private var showDetail = false
    @State private var shareAnchorView: NSView?

    private let spotifyGreen = Color(red: 0.11, green: 0.73, blue: 0.33)

    var body: some View {
        let state = feed.nowPlayingState
        let hasTrack = !(state.title?.isEmpty ?? true)
        let title = hasTrack ? (state.title ?? "") : String(localized: "Not Playing")
        let artist = hasTrack ? (state.artist ?? state.appName ?? "") : String(localized: "Spotify / Music")
        let liked = actions.isLiked(title: state.title, artist: state.artist)
        let isSpotify = state.bundleIdentifier == "com.spotify.client" || state.appName == "Spotify"

        Group {
            if isVertical {
                VStack(spacing: size == .small ? 0 : 7) {
                    artworkThumbnail(state: state, isSpotify: isSpotify)
                        .onTapGesture { showDetail.toggle() }
                    if size != .small {
                        Button { feed.togglePlayPause() } label: {
                            ZStack {
                                Circle().fill(Color.white.opacity(0.92)).frame(width: 24, height: 24)
                                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.black)
                                    .offset(x: state.isPlaying ? 0 : 0.7)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(state.isPlaying ? Text("Pause") : Text("Play"))
                    }
                    if size == .large {
                        iconButton("forward.end.fill", size: 10) { feed.nextTrack() }
                            .accessibilityLabel(Text("Next Track"))
                    }
                }
                .padding(.vertical, 6).padding(.horizontal, 4)
            } else {
                HStack(spacing: 8) {
                    artworkThumbnail(state: state, isSpotify: isSpotify)
                        .onTapGesture {
                            showDetail.toggle()
                        }

                    if size != .small {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: title)
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(DockWidgetStyle.ink)
                                .lineLimit(1)
                            Text(verbatim: artist)
                                .font(.system(size: 10, weight: .regular, design: .rounded))
                                .foregroundStyle(DockWidgetStyle.ink.opacity(DockWidgetStyle.secondaryOpacity))
                                .lineLimit(1)
                        }
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showDetail.toggle()
                        }
                    }

                    transportRow(state: state, liked: liked, hasTrack: hasTrack)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(alignment: .leading) {
            if let data = state.artworkData, let accent = ArtworkAccentCache.accent(for: data) {
                LinearGradient(
                    colors: [
                        Color(red: accent.red, green: accent.green, blue: accent.blue).opacity(0.24),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .popover(isPresented: $showDetail, arrowEdge: popoverEdge) {
            DockSpotifyDetailPopover(
                state: state,
                isLiked: liked,
                onTogglePlay: { feed.togglePlayPause() },
                onPrevious: { feed.previousTrack() },
                onNext: { feed.nextTrack() },
                onSeek: { feed.seek(to: $0) },
                onToggleLike: { actions.toggleLike(for: state) },
                onShare: { actions.shareTrack(state, anchorView: shareAnchorView) }
            )
        }
        .onAppear {
            feed.retain()
            actions.syncRemoteLikeStateIfNeeded(title: state.title, artist: state.artist)
        }
        .onDisappear { feed.release() }
        .onChange(of: state.title) { newTitle in
            actions.syncRemoteLikeStateIfNeeded(title: newTitle, artist: state.artist)
        }
    }

    @ViewBuilder
    private func artworkThumbnail(state: NowPlayingState, isSpotify: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let data = state.artworkData, let img = NSImage(data: data) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.18, green: 0.22, blue: 0.30), Color(red: 0.08, green: 0.10, blue: 0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DockWidgetStyle.ink.opacity(0.8))
                    )
                }
            }
            .frame(width: 30, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.75)
            )

            if isSpotify || size == .small {
                Circle()
                    .fill(isSpotify ? spotifyGreen : Color.white.opacity(0.2))
                    .frame(width: 11, height: 11)
                    .overlay(
                        Image(systemName: isSpotify ? "dot.radiowaves.left.and.right" : "music.note")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(.black.opacity(0.85))
                    )
                    .offset(x: 2, y: 2)
            }
        }
        .accessibilityLabel(Text("Song details"))
    }

    @ViewBuilder
    private func transportRow(state: NowPlayingState, liked: Bool, hasTrack: Bool) -> some View {
        HStack(spacing: size == .large ? 6 : 4) {
            if size == .large {
                iconButton("backward.end.fill", size: 10) {
                    feed.previousTrack()
                }
                .accessibilityLabel(Text("Previous Track"))
            }

            Button {
                feed.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.92))
                        .frame(width: 24, height: 24)
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.black)
                        .offset(x: state.isPlaying ? 0 : 0.7)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.isPlaying ? Text("Pause") : Text("Play"))

            iconButton("forward.end.fill", size: 10) {
                feed.nextTrack()
            }
            .accessibilityLabel(Text("Next Track"))

            if size == .large {
                Button {
                    actions.toggleLike(for: state)
                } label: {
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(liked ? spotifyGreen : DockWidgetStyle.ink.opacity(0.82))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!hasTrack)
                .accessibilityLabel(liked ? Text("Unlike") : Text("Like"))

                Button {
                    actions.shareTrack(state, anchorView: shareAnchorView)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(DockWidgetStyle.ink.opacity(0.82))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                        .background(DockShareAnchorRepresentable(viewRef: $shareAnchorView))
                }
                .buttonStyle(.plain)
                .disabled(!hasTrack)
                .accessibilityLabel(Text("Share"))
            }
        }
    }

    private func iconButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(DockWidgetStyle.ink.opacity(0.88))
                .frame(width: 18, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct DockShareAnchorRepresentable: NSViewRepresentable {
    @Binding var viewRef: NSView?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { self.viewRef = view }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if viewRef !== nsView {
            DispatchQueue.main.async { self.viewRef = nsView }
        }
    }
}

private struct DockSpotifyDetailPopover: View {
    let state: NowPlayingState
    let isLiked: Bool
    let onTogglePlay: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSeek: (Double) -> Void
    let onToggleLike: () -> Void
    let onShare: () -> Void

    @ObservedObject private var lyricsStore = LyricsStore.shared
    @State private var showLyrics = false
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let hasTrack = !(state.title?.isEmpty ?? true)
        let title = hasTrack ? (state.title ?? "") : String(localized: "Not Playing")
        let artist = state.artist ?? state.appName ?? ""
        let lines = lyricsStore.lines(title: state.title, artist: state.artist)

        DockPreviewCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Group {
                        if let data = state.artworkData, let img = NSImage(data: data) {
                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.white.opacity(0.1)
                                .overlay(Image(systemName: "music.note").font(.title3).foregroundStyle(.white.opacity(0.7)))
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .lineLimit(2)
                        if !artist.isEmpty {
                            Text(verbatim: artist)
                                .dockCaption()
                        }
                        if let album = state.album, !album.isEmpty {
                            Text(verbatim: album)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }

                if let progress = state.progress(at: now), let duration = state.duration, duration > 0 {
                    VStack(spacing: 4) {
                        Slider(
                            value: Binding(
                                get: { progress * duration },
                                set: { onSeek($0) }
                            ),
                            in: 0...duration
                        )
                        .controlSize(.mini)
                        HStack {
                            Text(verbatim: NotchLayoutSpec.clockText(progress * duration))
                            Spacer()
                            Text(verbatim: NotchLayoutSpec.clockText(duration))
                        }
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 14) {
                    Button(action: onToggleLike) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .foregroundStyle(isLiked ? Color.green : Color.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasTrack)

                    Spacer()

                    Button(action: onPrevious) { Image(systemName: "backward.fill") }
                        .buttonStyle(.plain)
                    Button(action: onTogglePlay) {
                        Image(systemName: state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 26))
                    }
                    .buttonStyle(.plain)
                    Button(action: onNext) { Image(systemName: "forward.fill") }
                        .buttonStyle(.plain)

                    Spacer()

                    Button {
                        showLyrics.toggle()
                        if showLyrics {
                            lyricsStore.loadIfNeeded(title: state.title, artist: state.artist)
                        }
                    } label: {
                        Image(systemName: "quote.bubble")
                            .foregroundStyle(showLyrics ? Color.accentColor : Color.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasTrack)

                    Button(action: onShare) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasTrack)
                }
                .font(.system(size: 13, weight: .semibold))

                if showLyrics {
                    Divider().opacity(0.25)
                    if lines.isEmpty {
                        Text("No lyrics cached. Enable synced lyrics in Now Playing settings to fetch.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(lines.prefix(12).enumerated()), id: \.offset) { _, line in
                                    Text(verbatim: line.text)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.white.opacity(0.86))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 110)
                    }
                }
            }
        }
        .onReceive(timer) { now = $0 }
    }
}
