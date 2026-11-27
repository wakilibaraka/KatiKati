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
            MusicPreviewTabsView(
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

// MARK: - Atmospheric music wings (ML-12)

/// Shared plumbing for the three Atmospheric wings: same service, same palette, same theme as the card, so a
/// wing and the desktop widget never disagree about the colour of a track.
private struct MusicWingChrome: View {
    let state: NowPlayingState
    var metrics: MusicTransportLayout
    var theme: MusicSurfaceTheme
    var palette: MusicArtworkPalette

    private var textColor: Color { theme.isDark ? .white : .black }
    private var accent: Color { Color(red: palette.accent.r, green: palette.accent.g, blue: palette.accent.b) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let data = state.artworkData, let image = NSImage(data: data) {
                GeometryReader { proxy in
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .overlay(
                            LinearGradient(stops: [
                                .init(color: .clear, location: 0.15),
                                .init(color: .black.opacity(theme.isDark ? 0.5 : 0.2), location: 0.7),
                                .init(color: .black.opacity(theme.isDark ? 0.78 : 0.3), location: 1)
                            ], startPoint: .top, endPoint: .bottom)
                        )
                }
            } else {
                LinearGradient(colors: [accent.opacity(0.45), accent.opacity(0.15)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: state.title ?? String(localized: "Not Playing"))
                    .font(.system(size: metrics.glyphSize, weight: .bold))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                if let artist = state.artist, !artist.isEmpty {
                    Text(verbatim: artist)
                        .font(.system(size: max(8, metrics.glyphSize - 3), weight: .medium))
                        .foregroundStyle(textColor.opacity(0.72))
                        .lineLimit(1)
                }
            }
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Full-bleed fade artwork, title/artist, scrubber, transport and the active output label.
struct DockMusicAtmosphericWingView: View {
    @Environment(\.widgetSize) private var size
    @Environment(\.dockWingVertical) private var isVertical
    @ObservedObject private var service = DesktopWidgetServices.nowPlaying
    @ObservedObject private var localPlayer = LocalAudioPlayer.shared
    @State private var defaultOutputName: String?

    private var state: NowPlayingState { localPlayer.isActive ? localPlayer.state : service.state }
    private var metrics: MusicTransportLayout { MusicTransportLayout(size: size) }
    private var theme: MusicSurfaceTheme { MusicSurfaceConfig.theme(for: .desktop) }
    private var palette: MusicArtworkPalette { MusicArtworkPaletteCache.shared.palette(for: state.artworkData) }

    var body: some View {
        ZStack(alignment: .bottom) {
            MusicWingChrome(state: state, metrics: metrics, theme: theme, palette: palette)
            VStack(spacing: 3) {
                if metrics.showsScrubber {
                    MusicScrubControl(state: state, tint: .white, style: .pill, labelColor: .white) { time in
                        if localPlayer.isActive { localPlayer.seek(to: time) } else { service.seek(to: time) }
                    }
                }
                HStack(spacing: metrics.spacing) {
                    control("backward.fill", label: String(localized: "Previous")) {
                        service.previousTrack()
                    }
                    playButton
                    control("forward.fill", label: String(localized: "Next")) {
                        service.nextTrack()
                    }
                    if !isVertical, metrics.showsDeviceLabel {
                        Spacer(minLength: 0)
                        if let device = defaultOutputName {
                            Text(verbatim: device)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(.bottom, 6)
        }
        .task(id: state.title ?? "") {
            guard !isVertical, metrics.showsDeviceLabel else { return }
            let name = await Task.detached(priority: .utility) { AudioOutputSwitcher.cachedDefaultOutputName() }.value
            guard !Task.isCancelled else { return }
            defaultOutputName = name
        }
    }

    private var playButton: some View {
        Button {
            if localPlayer.isActive { localPlayer.togglePlayPause() } else { service.togglePlayPause() }
        } label: {
            Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: metrics.glyphSize, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: metrics.playDiameter, height: metrics.playDiameter)
                .background(Color.white.opacity(0.18), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.isPlaying ? Text("Pause") : Text("Play"))
    }

    private func control(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: metrics.glyphSize - 3, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
    }
}

/// Bold left-aligned active line over the adaptive mesh, with the next lines dimmed underneath.
struct DockMusicLyricsWingView: View {
    @Environment(\.widgetSize) private var size
    @Environment(\.dockWingVertical) private var isVertical
    @ObservedObject private var service = DesktopWidgetServices.nowPlaying
    @ObservedObject private var localPlayer = LocalAudioPlayer.shared
    @ObservedObject private var lyricsStore = LyricsStore.shared

    private var state: NowPlayingState { localPlayer.isActive ? localPlayer.state : service.state }
    private var metrics: MusicTransportLayout { MusicTransportLayout(size: size) }
    private var theme: MusicSurfaceTheme { MusicSurfaceConfig.theme(for: .desktop) }
    private var palette: MusicArtworkPalette { MusicArtworkPaletteCache.shared.palette(for: state.artworkData) }
    private var textColor: Color { theme.isDark ? .white : .black }
    private var lines: [LyricsLine] { lyricsStore.lines(title: state.title, artist: state.artist) }

    private var activeIndex: Int {
        guard !lines.isEmpty else { return 0 }
        let elapsed = state.elapsed ?? 0
        return lines.lastIndex { $0.time <= elapsed + 0.1 } ?? 0
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: palette.accent.r, green: palette.accent.g, blue: palette.accent.b).opacity(0.5),
                         Color.black.opacity(0.55)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let data = state.artworkData, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 22, height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    Text(verbatim: state.title ?? String(localized: "Not Playing"))
                        .font(.system(size: max(9, metrics.glyphSize - 3), weight: .semibold))
                        .foregroundStyle(textColor.opacity(0.75))
                        .lineLimit(1)
                }
                ForEach(0..<metrics.lyricLines, id: \.self) { offset in
                    let index = activeIndex + offset
                    if index < lines.count {
                        Text(verbatim: lines[index].text)
                            .font(.system(size: offset == 0 ? max(10, metrics.glyphSize) : max(9, metrics.glyphSize - 2),
                                          weight: offset == 0 ? .bold : .medium))
                            .foregroundStyle(textColor.opacity(offset == 0 ? 0.98 : 0.4))
                            .lineLimit(isVertical ? 2 : 1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear { lyricsStore.loadIfNeeded(title: state.title, artist: state.artist) }
        .onChange(of: state.title) { _, _ in
            lyricsStore.loadIfNeeded(title: state.title, artist: state.artist)
        }
    }
}

/// Session history + local favourites with the quick Shuffle / Repeat controls. Zero permissions: the
/// upcoming queue exists only when the opt-in reader fills it, and this view never blocks on that.
struct DockMusicQueueWingView: View {
    @Environment(\.widgetSize) private var size
    @Environment(\.dockWingVertical) private var isVertical
    @State private var queue = MusicSurfaceConfig.queueModel()

    private var theme: MusicSurfaceTheme { MusicSurfaceConfig.theme(for: .desktop) }
    private var textColor: Color { theme.isDark ? .white : .black }
    private var metrics: MusicTransportLayout { MusicTransportLayout(size: size) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 9))
                Text("History").font(.system(size: max(9, metrics.glyphSize - 3), weight: .semibold))
                Spacer(minLength: 0)
                Button {
                    queue.isShuffled.toggle(); MusicSurfaceConfig.saveQueueModel(queue)
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(textColor.opacity(queue.isShuffled ? 1 : 0.45))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Shuffle"))
                Button {
                    queue.repeatsTrack.toggle(); MusicSurfaceConfig.saveQueueModel(queue)
                } label: {
                    Image(systemName: "repeat")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(textColor.opacity(queue.repeatsTrack ? 1 : 0.45))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Repeat"))
            }
            .foregroundStyle(textColor.opacity(0.6))

            let rows = Array(queue.history.prefix(isVertical ? 3 : 2))
            if rows.isEmpty {
                Text("Nothing played yet")
                    .font(.system(size: 9))
                    .foregroundStyle(textColor.opacity(0.45))
            }
            ForEach(rows) { entry in
                HStack(spacing: 4) {
                    Text(verbatim: entry.title)
                        .font(.system(size: max(9, metrics.glyphSize - 3), weight: .semibold))
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let artist = entry.artist, !artist.isEmpty {
                        Text(verbatim: artist)
                            .font(.system(size: 8))
                            .foregroundStyle(textColor.opacity(0.45))
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            LinearGradient(colors: [Color.black.opacity(theme.isDark ? 0.35 : 0.08), Color.black.opacity(0.05)],
                           startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear { queue = MusicSurfaceConfig.queueModel() }
    }
}
