import AppKit
import SwiftUI

/// Left card of the full notch skin when music is the winning activity or nothing is active: album art,
/// title / artist, a thin progress bar (no time readout), and the transport row. Idle shows
/// "Not Playing" with a quick-actions row instead of the progress bar.
struct NotchMusicPanel: View {
    @ObservedObject var feed: LiveActivityFeed
    @ObservedObject private var lyricsStore = LyricsStore.shared
    @AppStorage(LyricsTrack.enabledKey) private var showLyrics = false
    @State private var showQueuePopover = false
    @State private var upcomingQueue: [NowPlayingQueueItem] = []
    var isIdle = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The artwork's reduced colour, white when the art is grey or missing.
    private func accent(_ state: NowPlayingState) -> Color {
        ArtworkAccentCache.accent(for: state.artworkData).map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? .white
    }

    var body: some View {
        let state = feed.nowPlayingState
        // A player we may not read says so, instead of the card claiming nothing is playing (Phase 45).
        let unreadable = isIdle ? feed.playerAccess.unreadableMessage : nil
        HStack(alignment: .top, spacing: 12) {
            art(isIdle ? nil : state.artworkData, isPlaying: !isIdle && state.isPlaying)
            VStack(alignment: .leading, spacing: 6) {
                if isIdle {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(unreadable ?? "Not Playing").font(.system(size: 14, weight: .bold, design: .rounded)).lineLimit(1)
                        if unreadable == nil {
                            Text("Play something to see it here").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                        } else {
                            Button("Open System Settings") {
                                if let url = PlayerAccess.automationSettingsURL { NSWorkspace.shared.open(url) }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    transport(state)
                    NotchQuickActions()
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(state.isPlaying ? accent(state) : Color.orange)
                                    .frame(width: 5, height: 5)
                                Text(verbatim: state.isPlaying ? "PLAYING" : "PAUSED")
                                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(state.isPlaying ? accent(state) : Color.orange)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill((state.isPlaying ? accent(state) : Color.orange).opacity(0.16)))
                            MarqueeText(text: state.title ?? "", font: .system(size: 15, weight: .bold, design: .rounded), nearEnd: (state.progress(at: Date()) ?? 0) > 0.88)
                            MarqueeText(text: state.artist ?? "", font: .system(size: 12)).foregroundStyle(.white.opacity(0.6))
                        }
                        .opensSourceApp(state.bundleIdentifier)
                        Spacer(minLength: 0)
                        MusicEqualizerBars(isActive: state.isPlaying && !reduceMotion, tint: accent(state))
                            .frame(width: 22, height: 18)
                    }
                    Spacer(minLength: 0)
                    progress(state)
                    transport(state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: NotchLayoutSpec.albumArtSize)
        .foregroundStyle(.white)
        .background {
            if !isIdle {
                // Artwork wash: the accent fades out left to right behind the card.
                LinearGradient(colors: [accent(state).opacity(0.30), .clear], startPoint: .leading, endPoint: .trailing)
                    .padding(-10).blur(radius: 14).allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.6), value: state.artworkData?.count)
            }
        }
    }

    /// The player's own artwork when it hands one over; the vinyl otherwise, spinning only while the
    /// track is playing (Phase 43 — it used to be a static note glyph either way).
    private func art(_ data: Data?, isPlaying: Bool) -> some View {
        let glow = ArtworkAccentCache.accent(for: data).map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? Color.black
        let size = NotchLayoutSpec.albumArtSize
        return Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(TurntableView(isPlaying: isPlaying).padding(2))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: NotchLayoutSpec.albumArtCorner, style: .continuous))
        .shadow(color: glow.opacity(0.55), radius: 12, y: 3)
        .opensSourceApp(isIdle ? nil : feed.nowPlayingState.bundleIdentifier)
    }

    @ViewBuilder
    private func progress(_ state: NowPlayingState) -> some View {
        // TimelineView only ticks while music is showing; the bar moves without the feed's own tick.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let fraction = state.progress(at: context.date) ?? 0
            let duration = state.duration ?? 0
            let elapsed = fraction * duration
            let lyricLines = showLyrics ? lyricsStore.lines(title: state.title, artist: state.artist) : []
            VStack(alignment: .leading, spacing: 3) {
                if showLyrics {
                    let window = LyricTimelineMatcher.window(in: lyricLines, at: elapsed, windowSize: 2)
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(window.enumerated()), id: \.offset) { _, line in
                            let isActive = (line.text == LyricsTrack.activeLine(in: lyricLines, at: elapsed))
                            Text(verbatim: line.text)
                                .font(.system(size: isActive ? 10.5 : 9, weight: isActive ? .semibold : .regular, design: .rounded))
                                .foregroundStyle(isActive ? .white : .white.opacity(0.45))
                                .lineLimit(1)
                        }
                    }
                }
                HStack(spacing: 8) {
                    Text(verbatim: Self.clock(elapsed)).frame(minWidth: 30, alignment: .trailing)
                    MusicScrubBar(progress: fraction, duration: duration, trackHeight: 4, tint: accent(state),
                                  onSeek: { feed.seek(to: $0) })
                    Text(verbatim: duration > 0 ? "-" + Self.clock(max(0, duration - elapsed)) : "–:––").frame(minWidth: 30, alignment: .leading)
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
            }
            .onAppear {
                if showLyrics { lyricsStore.loadIfNeeded(title: state.title, artist: state.artist) }
            }
            .onChange(of: state.title) { _, _ in
                if showLyrics { lyricsStore.loadIfNeeded(title: state.title, artist: state.artist) }
            }
        }
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func transport(_ state: NowPlayingState) -> some View {
        HStack(spacing: 16) {
            Button { feed.previousTrack() } label: { Image(systemName: "backward.end.fill").font(.system(size: 15)) }
            Button { feed.togglePlayPause() } label: {
                Image(systemName: state.isPlaying && !isIdle ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white))
            }
            Button { feed.nextTrack() } label: { Image(systemName: "forward.end.fill").font(.system(size: 15)) }
            Button { showQueuePopover.toggle() } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(showQueuePopover ? 1.0 : 0.6))
            }
            .popover(isPresented: $showQueuePopover) {
                NotchQueuePopoverView(queue: $upcomingQueue)
            }
            Button { showLyrics.toggle() } label: {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(showLyrics ? accent(state) : .white.opacity(0.55))
            }
            AudioOutputMenu {
                Image(systemName: "airplayaudio")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

/// Dedicated full-width Music page (split from Calendar): full-width player card with optional
/// synchronized LRC lyrics & audio output companion panel.
struct NotchMusicPageView: View {
    @ObservedObject var feed: LiveActivityFeed
    @ObservedObject private var lyricsStore = LyricsStore.shared
    @AppStorage(LyricsTrack.enabledKey) private var showLyrics = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let state = feed.nowPlayingState
        let isIdle = (state.title ?? "").isEmpty
        HStack(spacing: NotchDesignSpec.cardSpacing) {
            NotchMusicPanel(feed: feed, isIdle: isIdle)
                .padding(NotchDesignSpec.cardPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                        .fill(Color.white.opacity(NotchDesignSpec.cardFillOpacity))
                        .overlay(
                            RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                                .stroke(Color.white.opacity(NotchDesignSpec.cardStrokeOpacity), lineWidth: NotchDesignSpec.cardStrokeWidth)
                        )
                )

            if !isIdle {
                companionCard(state)
                    .frame(width: 175)
                    .padding(NotchDesignSpec.cardPadding)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                            .fill(Color.white.opacity(NotchDesignSpec.cardFillOpacity))
                            .overlay(
                                RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                                    .stroke(Color.white.opacity(NotchDesignSpec.cardStrokeOpacity), lineWidth: NotchDesignSpec.cardStrokeWidth)
                            )
                    )
            }
        }
    }

    private func companionCard(_ state: NowPlayingState) -> some View {
        let accentColor = ArtworkAccentCache.accent(for: state.artworkData).map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? .cyan
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: showLyrics ? "quote.bubble.fill" : "hifispeaker.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accentColor)
                Text(verbatim: showLyrics ? "Lyrics" : "Now Playing")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer(minLength: 0)
            }

            if showLyrics {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let fraction = state.progress(at: ctx.date) ?? 0
                    let elapsed = fraction * (state.duration ?? 0)
                    let lines = lyricsStore.lines(title: state.title, artist: state.artist)
                    let window = LyricTimelineMatcher.window(in: lines, at: elapsed, windowSize: 4)
                    if window.isEmpty {
                        Text(verbatim: "No synced lyrics found")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(maxHeight: .infinity)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(window.enumerated()), id: \.offset) { _, line in
                                let active = (line.text == LyricsTrack.activeLine(in: lines, at: elapsed))
                                Text(verbatim: line.text)
                                    .font(.system(size: active ? 11.5 : 10, weight: active ? .bold : .regular, design: .rounded))
                                    .foregroundStyle(active ? .white : .white.opacity(0.45))
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            } else {
                Spacer(minLength: 0)
                MusicEqualizerBars(isActive: state.isPlaying && !reduceMotion, tint: accentColor)
                    .frame(height: 36)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
                AudioOutputMenu {
                    HStack(spacing: 4) {
                        Image(systemName: "airplayaudio").font(.system(size: 10, weight: .semibold))
                        Text(verbatim: "Output").font(.system(size: 10, weight: .semibold))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                    .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
    }
}

/// Left half when something other than music is winning (timer, focus, stopwatch, countdown, clock):
/// the activity's glyph, label and value, large.
struct NotchActivityPanel: View {
    let activity: LiveActivity
    private let services = ProductivityServices.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: LiveIslandStyle.symbolName(for: activity.kind))
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(LiveIslandStyle.tint(for: activity.kind))
                .frame(width: NotchLayoutSpec.albumArtSize, height: NotchLayoutSpec.albumArtSize)
                .background(RoundedRectangle(cornerRadius: NotchLayoutSpec.albumArtCorner, style: .continuous).fill(Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 2) {
                LiveIslandStyle.labelText(for: activity.kind).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                if let value = LiveIslandStyle.valueText(for: activity) {
                    value.font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                }
                controls
            }
            Spacer(minLength: 0)
        }
        .frame(height: NotchLayoutSpec.albumArtSize)
    }
}

extension NotchActivityPanel {
    /// Pause/resume and stop for the activities KatiKati owns; the event countdown has nothing to control.
    @ViewBuilder fileprivate var controls: some View {
        switch activity.kind {
        case .focus: controlRow(toggle: { services.focus.toggle() }, stop: { services.focus.reset() })
        case .timer: controlRow(toggle: { services.timer.toggle() }, stop: { services.timer.reset() })
        case .stopwatch: controlRow(toggle: { services.stopwatch.toggle() }, stop: { services.stopwatch.reset() })
        default: EmptyView()
        }
    }

    private func controlRow(toggle: @escaping () -> Void, stop: @escaping () -> Void) -> some View {
        HStack(spacing: 18) {
            Button(action: toggle) { Image(systemName: "playpause.fill").font(.system(size: 16)) }
            Button(action: stop) { Image(systemName: "stop.fill").font(.system(size: 16)) }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.top, 4)
    }
}

/// Idle extras under the Now Playing placeholder (instead of a clock): start a Pomodoro or a 5-minute
/// timer. (Volume lives in the header's right cluster.)
struct NotchQuickActions: View {
    private let services = ProductivityServices.shared

    var body: some View {
        HStack(spacing: 8) {
            chip("timer", Text("Timer")) { services.timer.set(seconds: 300); services.timer.toggle() }
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
    }

    private func chip(_ symbol: String, _ title: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 11))
                title.font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Queue Popover & Detachable Floating Player (Slice 2.4)

struct NotchQueuePopoverView: View {
    @Binding var queue: [NowPlayingQueueItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "Playing Next")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            if queue.isEmpty {
                Text(verbatim: "No upcoming tracks")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(queue) { item in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: item.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            if !item.artist.isEmpty {
                                Text(verbatim: item.artist)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.25)) {
                                queue = NowPlayingQueueReorderPlan.promoteTrackToTop(in: queue, id: item.id)
                            }
                        } label: {
                            Image(systemName: "arrow.up.to.line")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .help("Promote to top of queue")
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(10)
        .frame(width: 180)
    }
}

/// Detachable floating music player panel supporting 3 responsive sizes (mini, player, expanded).
struct FloatingPlayerPanel: View {
    @ObservedObject var feed: LiveActivityFeed
    @State var size: FloatingPlayerSize = .player
    @State private var queue: [NowPlayingQueueItem] = []
    @ObservedObject private var lyricsStore = LyricsStore.shared

    var body: some View {
        let state = feed.nowPlayingState
        let dims = size.defaultDimensions
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )

            switch size {
            case .mini:
                miniContent(state)
            case .player:
                playerContent(state)
            case .expanded:
                expandedContent(state)
            }
        }
        .frame(width: dims.width, height: dims.height)
        .shadow(color: Color.black.opacity(0.35), radius: 12, y: 6)
    }

    private func miniContent(_ state: NowPlayingState) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
            Text(verbatim: state.title ?? "Not Playing")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            Spacer()
            Button { feed.togglePlayPause() } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
    }

    private func playerContent(_ state: NowPlayingState) -> some View {
        HStack(spacing: 12) {
            if let data = state.artworkData, let img = NSImage(data: data) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 48, height: 48)
                    .overlay(Image(systemName: "music.note").foregroundColor(.white.opacity(0.5)))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: state.title ?? "Not Playing")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(verbatim: state.artist ?? "")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                HStack(spacing: 12) {
                    Button { feed.previousTrack() } label: { Image(systemName: "backward.fill").font(.system(size: 11)) }
                    Button { feed.togglePlayPause() } label: { Image(systemName: state.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 13, weight: .bold)) }
                    Button { feed.nextTrack() } label: { Image(systemName: "forward.fill").font(.system(size: 11)) }
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
                .padding(.top, 2)
            }
            Spacer()
        }
        .padding(12)
    }

    private func expandedContent(_ state: NowPlayingState) -> some View {
        VStack(spacing: 8) {
            playerContent(state)
            Divider().background(Color.white.opacity(0.1))
            let lines = lyricsStore.lines(title: state.title, artist: state.artist)
            let window = LyricTimelineMatcher.window(in: lines, at: state.elapsed ?? 0, windowSize: 3)
            VStack(spacing: 4) {
                ForEach(Array(window.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line.text)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            Spacer()
        }
    }
}
